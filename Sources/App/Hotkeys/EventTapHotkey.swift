import AppKit
import CoreGraphics
import Foundation
import AirdraftCore
import os

/// Global hotkey via a CGEventTap. Supports modifier-only keys (Right ⌥, fn)
/// as well as key combinations. Trigger Delay withholds ordinary key events
/// until a hold qualifies, or replays a short press. Needs Accessibility.
/// Main-thread only.
final class EventTapHotkey {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "hotkey")
    var hotkey: Hotkey = .controlOption { didSet { releaseHeldKey(reason: "shortcut changed") } }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var triggerDelayMilliseconds = 0
    var shouldDelayPress: () -> Bool = { true }
    /// While true, events pass through untouched (used by the recorder UI).
    var suspended = false {
        didSet {
            if suspended { releaseHeldKey(reason: "monitor suspended") }
        }
    }

    var isActive: Bool {
        guard let tap, CFMachPortIsValid(tap) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var trigger = HotkeyTriggerState()
    private var triggerTimer: Timer?
    private var bufferedEvents: [CGEvent] = []
    private var bufferedTarget: pid_t?
    private var interruptionObservers: [NSObjectProtocol] = []
    private static let replayMarker: Int64 = 0x4144_5452_4947

    init() {
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            interruptionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.cancelPendingPress() })
        }
    }

    deinit {
        for observer in interruptionObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        triggerTimer?.invalidate()
    }

    func cancelPendingPress() { apply(trigger.cancelPending()) }

    func start() {
        guard tap == nil, retryTimer == nil else { return }
        if !createTap() {
            retryTimer?.invalidate()
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                guard let self, self.tap == nil else { return }
                if self.createTap() { self.retryTimer?.invalidate(); self.retryTimer = nil }
            }
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
        releaseHeldKey(reason: "monitor stopped")
    }

    /// Also runs after wake through the service's common-mode health timer.
    /// A cached "created successfully" flag cannot detect a disabled/dead tap.
    func refresh(afterInterruption: Bool = false) {
        guard let tap else { start(); return }
        guard CFMachPortIsValid(tap) else {
            Self.log.error("event tap invalid; recreating")
            stop()
            start()
            return
        }
        let wasDisabled = !CGEvent.tapIsEnabled(tap: tap)
        if wasDisabled || afterInterruption {
            Self.log.notice("event tap disabled; re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
            reconcileKeyState(afterInterruption: true)
        }
    }

    private func reconcileKeyState(afterInterruption: Bool) {
        guard afterInterruption, !suspended, trigger.isDown else { return }
        apply(trigger.reconcile(
            hotkey: hotkey,
            modifierFlags: CGEventSource.flagsState(.combinedSessionState).rawValue,
            keyIsDown: CGEventSource.keyState(.combinedSessionState, key: hotkey.keyCode)
        ))
    }

    private func releaseHeldKey(reason: String) {
        Self.log.debug("reset shortcut: \(reason, privacy: .public)")
        apply(trigger.reset())
    }

    private func deliver(_ transition: HotkeyPressState.Transition?) {
        switch transition {
        case .pressed: onPress?()
        case .released: onRelease?()
        case nil: break
        }
    }

    private func createTap() -> Bool {
        guard AXIsProcessTrusted() else {
            Self.log.notice("event tap: not trusted yet")
            return false
        }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventTapHotkey>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(proxy: proxy, type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("CGEvent.tapCreate returned nil despite Accessibility trust")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        Self.log.notice("event tap created")
        return true
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.log.notice("event tap interrupted: type=\(type.rawValue, privacy: .public)")
            refresh(afterInterruption: true)
            return Unmanaged.passUnretained(event)
        }
        guard !suspended else { return Unmanaged.passUnretained(event) }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            apply(trigger.cancelPending(), proxy: proxy)
            return Unmanaged.passUnretained(event)
        }

        let kind: HotkeyPressState.Event
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return Unmanaged.passUnretained(event)
        }
        let result = trigger.handle(
            kind,
            hotkey: hotkey,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            modifierKeyIsDown: CGEventSource.keyState(.combinedSessionState, key: hotkey.keyCode),
            now: ProcessInfo.processInfo.systemUptime,
            delayMilliseconds: shouldDelayPress() ? triggerDelayMilliseconds : 0
        )
        apply(result, proxy: proxy)
        switch result.disposition {
        case .buffer:
            guard let copy = event.copy() else {
                // Never eat a key when it cannot be safely returned later.
                apply(trigger.cancelPending(), proxy: proxy)
                return Unmanaged.passUnretained(event)
            }
            if bufferedEvents.isEmpty {
                bufferedTarget = NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
            bufferedEvents.append(copy)
            return nil
        case .consume: return nil
        case .pass: return Unmanaged.passUnretained(event)
        }
    }

    private func apply(_ result: HotkeyTriggerState.Result, proxy: CGEventTapProxy? = nil) {
        if result.replayBuffered {
            var events = bufferedEvents
            bufferedEvents.removeAll()
            if proxy == nil, let last = events.last,
               bufferedTarget != NSWorkspace.shared.frontmostApplication?.processIdentifier ||
                !CGEventSource.keyState(.combinedSessionState,
                    key: UInt16(truncatingIfNeeded: last.getIntegerValueField(.keyboardEventKeycode))),
               let release = last.copy() {
                // A focus change or missed release must not leave the original
                // app with a held key. This never releases an active dictation.
                release.type = .keyUp
                release.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                events.append(release)
            }
            for event in events {
                if let proxy {
                    // Apple guarantees these precede the event returned by the
                    // callback, preserving down/up and ordinary typing order.
                    event.tapPostEvent(proxy)
                } else if let target = bufferedTarget {
                    event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
                    event.postToPid(target)
                } else {
                    event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
                    event.post(tap: .cgSessionEventTap)
                }
            }
            bufferedTarget = nil
        }
        if result.discardBuffered {
            bufferedEvents.removeAll()
            bufferedTarget = nil
        }
        syncTimer()
        deliver(result.transition)
    }

    private func syncTimer() {
        guard let deadline = trigger.deadline else {
            triggerTimer?.invalidate()
            triggerTimer = nil
            return
        }
        guard triggerTimer == nil else { return }
        let timer = Timer(timeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.triggerTimer = nil
            self.apply(self.trigger.fire(now: ProcessInfo.processInfo.systemUptime))
        }
        RunLoop.main.add(timer, forMode: .common)
        triggerTimer = timer
    }
}
