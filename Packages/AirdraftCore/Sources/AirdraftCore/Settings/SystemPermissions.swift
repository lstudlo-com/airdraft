import AppKit
import ApplicationServices
import AVFoundation
import Observation

/// A live, process-specific view of macOS permissions. Never persisted or
/// inferred from an earlier prompt, another installed copy, or a saved setting.
@MainActor
@Observable
public final class SystemPermissions {
    public private(set) var accessibilityGranted: Bool
    public private(set) var microphone: AVAuthorizationStatus
    @ObservationIgnored public var accessibilityDidChange: (() -> Void)?
    @ObservationIgnored private let checkAccessibility: () -> Bool
    @ObservationIgnored private let checkMicrophone: () -> AVAuthorizationStatus
    @ObservationIgnored private let promptAccessibility: () -> Void
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    public init(
        checkAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
        checkMicrophone: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        promptAccessibility: @escaping () -> Void = {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    ) {
        self.checkAccessibility = checkAccessibility
        self.checkMicrophone = checkMicrophone
        self.promptAccessibility = promptAccessibility
        accessibilityGranted = checkAccessibility()
        microphone = checkMicrophone()
    }

    public func refresh() {
        let granted = checkAccessibility()
        let changed = granted != accessibilityGranted
        accessibilityGranted = granted
        microphone = checkMicrophone()
        if changed { accessibilityDidChange?() }
    }

    /// Apple's prompt is asynchronous; requesting access does not grant it.
    public func requestAccessibility() {
        if !checkAccessibility() { promptAccessibility() }
        refresh()
    }

    public func requestMicrophone() async {
        if checkMicrophone() == .notDetermined {
            _ = await MicrophonePermission.shared.request()
        }
        refresh()
    }

    public func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        // The app is usually in the menu bar while the user changes Settings.
        // Activation alone therefore cannot detect a grant or revocation.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        activationObserver = nil
        wakeObserver = nil
    }
}
