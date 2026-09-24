import AppKit
import CoreGraphics
import Foundation
import AirdraftCore
import os

/// Global hotkey via a CGEventTap. Supports modifier-only keys (Right ⌥, fn)
/// as well as key combinations, and swallows the combination so it never
/// reaches the frontmost app. Needs Accessibility; retries until granted.
/// Main-thread only.
final class EventTapHotkey {
    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "hotkey")
    var hotkey: Hotkey = .controlOption { didSet { releaseHeldKey(reason: "shortcut changed") } }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
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
    private var pressState = HotkeyPressState()

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
        guard !suspended, pressState.isDown else { return }
        if let transition = pressState.reconcile(
            afterInterruption: afterInterruption,
            hotkey: hotkey,
            modifierFlags: CGEventSource.flagsState(.combinedSessionState).rawValue,
            keyIsDown: CGEventSource.keyState(.combinedSessionState, key: hotkey.keyCode)
        ) {
            Self.log.notice("recovered missed release for \(self.hotkey.displayString, privacy: .public)")
            deliver(transition)
        }
    }

    private func releaseHeldKey(reason: String) {
        if let transition = pressState.reset() {
            Self.log.notice("reset held shortcut: \(reason, privacy: .public)")
            deliver(transition)
        }
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
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventTapHotkey>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.log.notice("event tap interrupted: type=\(type.rawValue, privacy: .public)")
            refresh(afterInterruption: true)
            return Unmanaged.passUnretained(event)
        }
        guard !suspended else { return Unmanaged.passUnretained(event) }

        let kind: HotkeyPressState.Event
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return Unmanaged.passUnretained(event)
        }
        let result = pressState.handle(
            kind,
            hotkey: hotkey,
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: event.flags.rawValue,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            modifierKeyIsDown: CGEventSource.keyState(.combinedSessionState, key: hotkey.keyCode)
        )
        deliver(result.transition)
        return result.consumesEvent ? nil : Unmanaged.passUnretained(event)
    }
}
