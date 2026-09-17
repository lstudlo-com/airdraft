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
    var hotkey: Hotkey = .optionSpace { didSet { isDown = false } }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// While true, events pass through untouched (used by the recorder UI).
    var suspended = false

    private(set) var isActive = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var isDown = false

    func start() {
        guard tap == nil else { return }
        if !createTap() {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                guard let self, self.tap == nil else { return }
                if self.createTap() { self.retryTimer?.invalidate(); self.retryTimer = nil }
            }
        }
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        isActive = false
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
        isActive = true
        Self.log.notice("event tap created")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard !suspended else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue & Hotkey.relevantModifierMask

        if hotkey.isModifierOnly {
            guard type == .flagsChanged, keyCode == hotkey.keyCode,
                  let bit = Hotkey.modifierFlag(for: keyCode) else { return Unmanaged.passUnretained(event) }
            let down = flags & bit != 0
            if down, !isDown {
                isDown = true
                onPress?()
            } else if !down, isDown {
                isDown = false
                onRelease?()
            }
            return Unmanaged.passUnretained(event)
        }

        guard keyCode == hotkey.keyCode else { return Unmanaged.passUnretained(event) }
        switch type {
        case .keyDown:
            guard flags == hotkey.modifiers else { return Unmanaged.passUnretained(event) }
            let repeatFlag = event.getIntegerValueField(.keyboardEventAutorepeat)
            if repeatFlag == 0, !isDown {
                isDown = true
                onPress?()
            }
            return nil // swallow
        case .keyUp:
            guard isDown else { return Unmanaged.passUnretained(event) }
            isDown = false
            onRelease?()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
