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
    private(set) var statusText = String(localized: "Not started")

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Profile and Edit shortcuts (AD-104), each with its own backend.
    var onExtraPress: ((HotkeyAction) -> Void)?
    var onExtraRelease: ((HotkeyAction) -> Void)?
    private var extras: [ExtraChannel] = []
    private var extraBindings: [HotkeyBinding] = []
    /// Extra shortcuts that could not be registered, for Settings.
    private(set) var extraIssues: [HotkeyAction: String] = [:]
    /// Stop/cancel actions bypass the start threshold.
    var shouldDelayPress: () -> Bool = { true }
    private(set) var triggerDelayMilliseconds = 0
    var suspended = false {
        didSet { if suspended != oldValue { suspensionChanged() } }
    }
    /// Onboarding's shortcut practice pauses dictation independently of the
    /// recorder and cleanup, so neither can resume it early.
    var rehearsing = false {
        didSet { if rehearsing != oldValue { suspensionChanged() } }
    }
    private var isSuspended: Bool { suspended || rehearsing }

    private func suspensionChanged() {
        eventTap.suspended = isSuspended
        // Carbon consumes registered shortcuts before the recorder's local
        // monitor receives them. Unregister both backends while recording.
        apply(hotkey, triggerDelayMilliseconds: triggerDelayMilliseconds)
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
        applyExtras()

        guard !isSuspended else {
            backend = .none
            isActive = false
            statusText = rehearsing ? String(localized: "Paused while practicing the shortcut") : String(localized: "Paused while recording a shortcut")
            return
        }

        if self.triggerDelayMilliseconds == 0, CarbonHotkey.canRegister(hotkey) {
            let ok = carbon.register(hotkey)
            backend = ok ? .carbon : .none
            isActive = ok
            statusText = ok ? String(localized: "Active (\(hotkey.localizedDisplayString))") : String(localized: "Could not register \(hotkey.localizedDisplayString); another app may own it.")
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
        (backend == .eventTap || extras.contains { $0.usesEventTap }) && !permissions.accessibilityGranted
    }

    /// Registers profile and Edit shortcuts beside the dictation shortcut. A
    /// binding equal to another shortcut is skipped and reported.
    func applyExtras(_ bindings: [HotkeyBinding]) {
        extraBindings = bindings
        applyExtras()
    }

    private func applyExtras() {
        for channel in extras { channel.stop() }
        extras = []
        extraIssues = [:]
        guard !isSuspended else { return }
        var used: Set<Hotkey> = [hotkey]
        for binding in extraBindings {
            guard used.insert(binding.hotkey).inserted else {
                extraIssues[binding.action] = String(localized: "This shortcut is already used by another shortcut.")
                continue
            }
            let channel = ExtraChannel(action: binding.action)
            channel.onPress = { [weak self] action in
                guard let self, !self.isSuspended else { return }
                Self.log.notice("press extra \(binding.hotkey.displayString, privacy: .public)")
                self.onExtraPress?(action)
            }
            channel.onRelease = { [weak self] action in self?.onExtraRelease?(action) }
            channel.shouldDelayPress = { [weak self] in self?.shouldDelayPress() ?? true }
            if let issue = channel.start(binding.hotkey, triggerDelayMilliseconds: triggerDelayMilliseconds,
                                         accessibilityGranted: permissions.accessibilityGranted) {
                extraIssues[binding.action] = issue
            }
            extras.append(channel)
        }
    }

    func cancelPendingPress() {
        eventTap.cancelPendingPress()
        for channel in extras { channel.cancelPendingPress() }
    }

    func refreshPermissionState() {
        if extras.contains(where: \.usesEventTap) { applyExtras() }
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
            ? String(localized: "Active (\(hotkey.localizedDisplayString))")
            : permissions.accessibilityGranted
                ? String(localized: "Permission granted, but the shortcut monitor is unavailable. Quit and reopen Airdraft.")
                : String(localized: "Waiting for Accessibility permission (needed for \(hotkey.localizedDisplayString))")
    }

    private func press() {
        guard !isSuspended else { return }
        Self.log.notice("press \(self.hotkey.displayString, privacy: .public)")
        onPress?()
    }

    private func release() {
        Self.log.notice("release \(self.hotkey.displayString, privacy: .public)")
        onRelease?()
    }
}

/// What a profile or Edit shortcut does (AD-104).
enum HotkeyAction: Hashable {
    case profile(UUID)
    case edit
}

struct HotkeyBinding: Equatable {
    var action: HotkeyAction
    var hotkey: Hotkey
}

/// One extra shortcut with the same backend rules as dictation's: Carbon for an
/// immediate key combination, the event tap for modifier-only keys, fn and a
/// trigger delay.
@MainActor
private final class ExtraChannel {
    let action: HotkeyAction
    var onPress: ((HotkeyAction) -> Void)?
    var onRelease: ((HotkeyAction) -> Void)?
    var shouldDelayPress: () -> Bool = { true }
    private let carbon = CarbonHotkey()
    private let eventTap = EventTapHotkey()
    private(set) var usesEventTap = false

    init(action: HotkeyAction) {
        self.action = action
        carbon.onPress = { [weak self] in self?.press() }
        carbon.onRelease = { [weak self] in self?.release() }
        eventTap.onPress = { [weak self] in self?.press() }
        eventTap.onRelease = { [weak self] in self?.release() }
        eventTap.shouldDelayPress = { [weak self] in self?.shouldDelayPress() ?? true }
    }

    /// Returns why the shortcut cannot work now, or nil.
    func start(_ hotkey: Hotkey, triggerDelayMilliseconds: Int, accessibilityGranted: Bool) -> String? {
        if triggerDelayMilliseconds == 0, CarbonHotkey.canRegister(hotkey) {
            return carbon.register(hotkey) ? nil
                : String(localized: "Could not register \(hotkey.localizedDisplayString); another app may own it.")
        }
        usesEventTap = true
        eventTap.hotkey = hotkey
        eventTap.triggerDelayMilliseconds = triggerDelayMilliseconds
        guard accessibilityGranted else {
            return String(localized: "Waiting for Accessibility permission (needed for \(hotkey.localizedDisplayString))")
        }
        eventTap.start()
        return nil
    }

    func stop() {
        carbon.unregister()
        eventTap.stop()
    }

    func cancelPendingPress() { eventTap.cancelPendingPress() }

    private func press() { onPress?(action) }
    private func release() { onRelease?(action) }
}
