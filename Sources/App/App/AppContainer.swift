import AppKit
import Observation
import AirdraftCore
import SwiftUI
import os

/// Owns every long-lived object. One instance for the process; `start()` is
/// called from `applicationDidFinishLaunching` so event taps, Carbon hotkeys
/// and panels are created only once the app is fully up.
@MainActor
@Observable
final class AppContainer {
    static let shared: AppContainer = {
        #if DEBUG
        // UI automation may relaunch a crashed copied bundle without its arguments.
        // Such a launch must stop before opening the user's real preferences/data.
        if Bundle.main.bundleIdentifier?.hasSuffix(".e2e") == true, !LocalE2E.isActive {
            print("E2E bundle requires --e2e-local; refusing normal startup")
            exit(64)
        }
        if LocalE2E.isActive { return LocalE2E.makeContainer() }
        #endif
        return AppContainer()
    }()
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "app")

    let dataDirectory: URL
    let cleanup: DataCleanupCoordinator
    let dataLease: DataDirectoryLease?
    let isolatedData: Bool
    var dataAccessIssue: String? { dataLease?.holdsLease != true ? "Another app copy may be changing local data, or the data folder is unavailable. Quit other copies, check folder access, then reopen Airdraft." : nil }
    let settings: AppSettings
    let dictionary: DictionaryStore
    let profiles: ProfileStore
    var speechConfig: ASRConfig { profiles.activeProfile.speechConfig(default: settings.asr) }
    var history: HistoryStore? { pipeline.historyStore }
    let engineStatus: EngineStatus
    let factory: EngineFactory
    let models: ModelLifecycle
    let pipeline: DictationPipeline
    let license: LicenseStore
    let permissions = SystemPermissions()
    let hotkeys: HotkeyService
    let microphones = MicrophoneStore()
    let downloads = ModelDownloadStore()
    @ObservationIgnored lazy var updates = AppUpdater { [weak self] in
        self?.pipeline.isBusy ?? false
    }
    let navigation = Navigation()
    private let escapeHotkey = CarbonHotkey()
    private var started = false
    @ObservationIgnored private var startupCompleted = false
    @ObservationIgnored private var shutdownStarted = false
    @ObservationIgnored private var appearanceUpdatesStarted = false
    private var indicator: IndicatorPanelController?
    private var audioCleanupTask: Task<Void, Never>?

    init(settings suppliedSettings: AppSettings? = nil, dataDirectory: URL? = nil, license suppliedLicense: LicenseStore? = nil) {
        hotkeys = HotkeyService(permissions: permissions)
        let dir = dataDirectory ?? AppSettings.supportDirectory
        self.dataDirectory = dir
        isolatedData = suppliedSettings != nil || dataDirectory != nil || RenderMode.isActive || RenderMode.excludesCredentials
        cleanup = DataCleanupCoordinator(directory: dir)
        dataLease = try? DataDirectoryLease(directory: dir)
        let settings = suppliedSettings ?? AppSettings()
        self.settings = settings
        let license = suppliedLicense ?? AppLicense.make(isolated: suppliedSettings != nil || RenderMode.isActive || RenderMode.excludesCredentials)
        self.license = license
        engineStatus = EngineStatus()
        #if DEBUG
        if LocalE2E.isActive {
            factory = EngineFactory(status: engineStatus, credentialReader: { _ in nil })
        } else {
            factory = EngineFactory(status: engineStatus)
        }
        #else
        factory = EngineFactory(status: engineStatus)
        #endif
        // A copy blocked by another process's cleanup must not read, repair or
        // write the shared JSON stores. The blocking sheet permits only Quit.
        let readableDirectory = dataLease == nil
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Airdraft-Unavailable-\(UUID())") : dir
        dictionary = DictionaryStore(directory: readableDirectory)
        profiles = ProfileStore(directory: readableDirectory)
        models = ModelLifecycle(settings: settings, factory: factory, engineStatus: engineStatus, profiles: profiles)

        let history: HistoryStore?
        do {
            guard dataLease != nil else { throw CleanupError.otherInstance }
            history = try HistoryStore(directory: dir)
        } catch {
            history = nil
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
        }

        var recordingPreflight: (@MainActor (ASRConfig, LLMConfig, Bool, MicrophonePreference, Bool) async throws -> Void)? = nil
        #if DEBUG
        if LocalE2E.isActive {
            recordingPreflight = { asr, llm, refinementEnabled, microphone, insertionEnabled in
                try LocalE2E.checkRecording(asr: asr, llm: llm, refinementEnabled: refinementEnabled,
                                            microphone: microphone, insertionEnabled: insertionEnabled)
            }
        }
        #endif
        pipeline = DictationPipeline(
            settings: settings,
            dictionary: dictionary,
            profiles: profiles,
            history: history,
            historyDirectory: dir,
            factory: factory,
            recordingPreflight: recordingPreflight,
            accessCheck: { try await license.requireAccess() }
        )
        if cleanup.blocksWork || dataLease == nil { try? pipeline.beginDataMaintenance() }
    }

    /// Call once from the app delegate.
    func start() {
        guard !started, !shutdownStarted else { return }
        started = true
        Task { await license.load(); await license.refresh() }
        Self.log.notice("start: accessibilityTrusted=\(AppContextReader.isAccessibilityTrusted, privacy: .public)")

        let panel = IndicatorPanelController(pipeline: pipeline) { [weak self] in self?.settings.hudStyle ?? .classic }
        indicator = panel
        pipeline.onOutputDelivered = { [weak panel, weak self] in
            panel?.deliveryCompleted()
            self?.settings.onboarding.noteDelivery()
        }
        pipeline.onRecordingBlocked = { [weak self] in
            guard let self else { return }
            self.permissions.refresh()
            if !self.license.access.allowsUse { self.license.isPresented = true }
            self.navigation.page = .home
            self.showMainWindow()
        }
        pipeline.onStateChange = { [weak panel, weak self] state in
            // Failure and notice text can quote provider responses; keep it out of the public log.
            let (name, detail): (String, String) = switch state {
            case .failed(let message): ("failed", message)
            case .notice(let message, _): ("notice", message)
            default: (String(describing: state), "")
            }
            AppContainer.log.notice("pipeline state: \(name, privacy: .public) \(detail, privacy: .private)")
            panel?.update(for: state)
            self?.hotkeys.cancelPendingPress()
            self?.models.setDictationBusy(state.isBusy)
            // Esc cancels only while recording, so it never steals Esc elsewhere.
            if state == .recording { self?.escapeHotkey.register(.escape) } else { self?.escapeHotkey.unregister() }
        }
        escapeHotkey.onPress = { [weak self] in self?.pipeline.cancel() }

        permissions.accessibilityDidChange = { [weak self] in self?.hotkeys.refreshPermissionState() }
        permissions.startMonitoring()
        registerHotkeys()
        startAppearanceUpdates()
        observeWindows()
        pipeline.onLLMUsed = { [weak self] instance, config in self?.models.noteLLMUsed(instance, config: config) }
        pipeline.llmNeedsLoad = { [weak self] config in await self?.models.llmNeedsLoad(config: config) ?? false }
        pipeline.loadLLM = { [weak self] config in await self?.models.loadLLMIfNeeded(config: config) }
        if !cleanup.blocksWork && dataLease != nil { models.start() }
        audioCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pipeline.pruneSavedAudio()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
        if cleanup.blocksWork || dataLease == nil { navigation.page = .configuration; showMainWindow() }
        observeAudioRetention()
        observeLivePreview()
        startupCompleted = true
    }

    /// Background intents can arrive during launch. Wait for the delegate's normal
    /// startup instead of creating panels or event taps before the app is ready.
    func prepareForAutomation() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !startupCompleted, !shutdownStarted {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw RecordingPrerequisiteError("Airdraft startup timed out. Open Airdraft, then try this action again.")
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        guard !shutdownStarted else {
            throw RecordingPrerequisiteError("Airdraft is quitting. Reopen it before running this action.")
        }
    }

    /// Called only after quitting has been approved, before asynchronous cleanup.
    func beginShutdown() {
        shutdownStarted = true
        audioCleanupTask?.cancel()
    }

    private func observeLivePreview() {
        observeChanges({ [weak self] in
            _ = self?.settings.livePreviewEnabled
            _ = self?.settings.hudStyle
        }) { [weak self] in
            guard let self else { return }
            if !self.settings.livePreviewEnabled || self.settings.hudStyle == .none {
                self.pipeline.disableLivePreview()
            }
            self.indicator?.update(for: self.pipeline.state, isStateChange: false)
        }
    }

    private func observeAudioRetention() {
        observeChanges({ [weak self] in _ = self?.settings.audioRetention }) { [weak self] in
            guard let self else { return }
            Task { await self.pipeline.pruneSavedAudio() }
        }
    }

    /// SwiftUI's window opener, captured by the menu-bar label so AppKit callbacks can use it.
    @ObservationIgnored var openWindowAction: OpenWindowAction?

    func showMainWindow(_ open: OpenWindowAction? = nil) {
        NSApp.setActivationPolicy(.regular)
        (open ?? openWindowAction)?(id: "main")
        NSApp.activate()
    }

    func showOnboarding() {
        guard !pipeline.isBusy else { return }
        settings.onboarding.present()
        showMainWindow()
    }

    func showLicense() {
        guard !pipeline.isMaintainingData else { return }
        license.isPresented = true
        showMainWindow()
    }

    /// A menu-bar (accessory) app has no menu bar of its own, so while a window is open
    /// the menu bar kept showing the previous app. Become a regular app (menu bar and Dock
    /// icon) while any normal window is open, and go back to menu-bar only when the last closes.
    private func observeWindows() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, Self.isAppWindow(window) else { return }
            MainActor.assumeIsolated {
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
            }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let closing = note.object as? NSWindow, Self.isAppWindow(closing) else { return }
            MainActor.assumeIsolated {
                let othersOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && Self.isAppWindow($0) }
                if !othersOpen { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    /// Titled document-style windows; excludes the HUD panel and menu-bar extras.
    private nonisolated static func isAppWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    /// Interactive previews share theme handling without starting dictation services.
    func startAppearanceUpdates() {
        guard !appearanceUpdatesStarted else { return }
        appearanceUpdatesStarted = true
        applyAppearance()
        observeAppearance()
    }

    private func applyAppearance() {
        switch settings.appearance {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func observeAppearance() {
        observeChanges({ [weak self] in _ = self?.settings.appearance }) { [weak self] in self?.applyAppearance() }
    }

    func openAccessibilitySettings() {
        permissions.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var menuIcon: String {
        switch pipeline.state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .preparingModel, .transcribing, .refining: return "waveform"
        case .inserting: return "text.cursor"
        case .failed: return "mic.slash"
        case .notice: return "exclamationmark.circle"
        }
    }

    private func registerHotkeys() {
        var pressedBehavior: HotkeyBehavior?
        hotkeys.shouldDelayPress = { [weak self] in
            guard let self else { return true }
            return self.settings.hotkeyBehavior != .toggle || !self.pipeline.isBusy
        }
        hotkeys.onPress = { [weak self] in
            guard let self else { return }
            pressedBehavior = self.settings.hotkeyBehavior
            switch self.settings.hotkeyBehavior {
            case .hold: self.pipeline.startRecording()
            case .toggle: self.pipeline.toggle()
            }
        }
        hotkeys.onRelease = { [weak self] in
            let behavior = pressedBehavior
            pressedBehavior = nil
            guard let self, behavior == .hold else { return }
            self.pipeline.stopAndProcess()
        }
        hotkeys.apply(settings.hotkey, triggerDelayMilliseconds: settings.triggerDelayMilliseconds)
        observeHotkeyChanges()
    }

    /// Cancel pending holds when the shortcut, behavior or threshold changes.
    private func observeHotkeyChanges() {
        observeChanges({ [weak self] in
            _ = self?.settings.hotkey
            _ = self?.settings.hotkeyBehavior
            _ = self?.settings.triggerDelayMilliseconds
        }) { [weak self] in
            guard let self else { return }
            self.hotkeys.apply(self.settings.hotkey, triggerDelayMilliseconds: self.settings.triggerDelayMilliseconds)
        }
    }
}
