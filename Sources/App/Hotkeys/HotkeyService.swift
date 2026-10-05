import AppKit
import Foundation
import Observation
import AirdraftCore
import os

/// Picks the right backend for the configured hotkey:
/// - immediate key combinations: Carbon (no permission needed)
/// - delayed shortcuts, modifier-only keys and fn: CGEventTap (needs Accessibility)
@MainActor
@Observable
final class HotkeyService {
    enum Backend: Equatable { case none, carbon, eventTap }

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "hotkey")

    private(set) var backend: Backend = .none
    private(set) var isActive = false
    /// Human-readable state for the menu and settings.
    private(set) var statusText = "Not started"

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Stop/cancel actions bypass the start threshold.
    var shouldDelayPress: () -> Bool = { true }
    private(set) var triggerDelayMilliseconds = 0
    var suspended = false {
        didSet {
            guard suspended != oldValue else { return }
            eventTap.suspended = suspended
            // Carbon consumes registered shortcuts before the recorder's local
            // monitor receives them. Unregister both backends while recording.
            apply(hotkey, triggerDelayMilliseconds: triggerDelayMilliseconds)
        }
    }

    private let carbon = CarbonHotkey()
    private let eventTap = EventTapHotkey()
    private let permissions: SystemPermissions
    private(set) var hotkey: Hotkey = .controlOption

    init(permissions: SystemPermissions) {
        self.permissions = permissions
        carbon.onPress = { [weak self] in self?.press() }
        carbon.onRelease = { [weak self] in self?.release() }
        eventTap.onPress = { [weak self] in self?.press() }
        eventTap.onRelease = { [weak self] in self?.release() }
        eventTap.shouldDelayPress = { [weak self] in self?.shouldDelayPress() ?? true }
        // The permission monitor's timer also checks the event tap's health.
        permissions.didRefresh = { [weak self] in self?.refreshEventTapStatus() }
    }

    func apply(_ hotkey: Hotkey, triggerDelayMilliseconds: Int = 0) {
        self.hotkey = hotkey
        self.triggerDelayMilliseconds = HotkeyTriggerState.clampedDelay(triggerDelayMilliseconds)
        carbon.unregister()
        eventTap.stop()

        guard !suspended else {
            backend = .none
            isActive = false
            statusText = "Paused while recording a shortcut"
            return
        }

        if self.triggerDelayMilliseconds == 0, CarbonHotkey.canRegister(hotkey) {
            let ok = carbon.register(hotkey)
            backend = ok ? .carbon : .none
            isActive = ok
            statusText = ok ? "Active (\(hotkey.displayString))" : "Could not register \(hotkey.displayString); another app may own it."
            Self.log.notice("hotkey backend=carbon active=\(ok, privacy: .public) key=\(hotkey.displayString, privacy: .public)")
            return
        }

        eventTap.hotkey = hotkey
        eventTap.triggerDelayMilliseconds = self.triggerDelayMilliseconds
        eventTap.start()
        backend = .eventTap
        refreshEventTapStatus()
    }

    var needsAccessibility: Bool {
        backend == .eventTap && !permissions.accessibilityGranted
    }

    func cancelPendingPress() { eventTap.cancelPendingPress() }

    func refreshPermissionState() {
        guard backend == .eventTap else { return }
        if permissions.accessibilityGranted {
            eventTap.start()
        } else {
            eventTap.stop()
        }
        refreshEventTapStatus()
    }

    private func refreshEventTapStatus() {
        guard backend == .eventTap else { return }
        eventTap.refresh()
        let active = eventTap.isActive
        if active != isActive {
            Self.log.notice("event tap active=\(active) key=\(self.hotkey.displayString)")
        }
        isActive = active
        statusText = active
            ? "Active (\(hotkey.displayString))"
            : permissions.accessibilityGranted
                ? "Permission granted, but the shortcut monitor is unavailable. Quit and reopen Airdraft."
                : "Waiting for Accessibility permission (needed for \(hotkey.displayString))"
    }

    private func press() {
        guard !suspended else { return }
        Self.log.notice("press \(self.hotkey.displayString, privacy: .public)")
        onPress?()
    }

    private func release() {
        Self.log.notice("release \(self.hotkey.displayString, privacy: .public)")
        onRelease?()
    }
}
