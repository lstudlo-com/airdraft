import AppKit
import Foundation
import Observation
import AirdraftCore
import os

/// Picks the right backend for the configured hotkey:
/// - key combinations: Carbon (no permission needed)
/// - modifier-only keys and fn: CGEventTap (needs Accessibility)
@MainActor
@Observable
final class HotkeyService {
    enum Backend: Equatable { case none, carbon, eventTap }

    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "hotkey")

    private(set) var backend: Backend = .none
    private(set) var isActive = false
    /// Human-readable state for the menu and settings.
    private(set) var statusText = "Not started"

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var suspended = false {
        didSet { eventTap.suspended = suspended }
    }

    private let carbon = CarbonHotkey()
    private let eventTap = EventTapHotkey()
    private let permissions: SystemPermissions
    private var pollTimer: Timer?
    private(set) var hotkey: Hotkey = .optionSpace

    init(permissions: SystemPermissions) {
        self.permissions = permissions
        carbon.onPress = { [weak self] in self?.press() }
        carbon.onRelease = { [weak self] in self?.release() }
        eventTap.onPress = { [weak self] in self?.press() }
        eventTap.onRelease = { [weak self] in self?.release() }
    }

    func apply(_ hotkey: Hotkey) {
        self.hotkey = hotkey
        carbon.unregister()
        eventTap.stop()
        pollTimer?.invalidate()
        pollTimer = nil

        if CarbonHotkey.canRegister(hotkey) {
            let ok = carbon.register(hotkey)
            backend = ok ? .carbon : .none
            isActive = ok
            statusText = ok ? "Active (\(hotkey.displayString))" : "Could not register \(hotkey.displayString); another app may own it."
            Self.log.notice("hotkey backend=carbon active=\(ok, privacy: .public) key=\(hotkey.displayString, privacy: .public)")
            return
        }

        eventTap.hotkey = hotkey
        eventTap.start()
        backend = .eventTap
        refreshEventTapStatus()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshEventTapStatus() }
        }
    }

    var needsAccessibility: Bool {
        backend == .eventTap && !permissions.accessibilityGranted
    }

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
        Self.log.notice("press \(self.hotkey.displayString, privacy: .public)")
        onPress?()
    }

    private func release() {
        Self.log.notice("release \(self.hotkey.displayString, privacy: .public)")
        onRelease?()
    }
}
