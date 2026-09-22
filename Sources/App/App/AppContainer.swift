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
    static let shared = AppContainer()
    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "app")

    let settings: AppSettings
    let dictionary: DictionaryStore
    let profiles: ProfileStore
    let history: HistoryStore?
    let engineStatus: EngineStatus
    let factory: EngineFactory
    let models: ModelLifecycle
    let pipeline: DictationPipeline
    let permissions = SystemPermissions()
    let hotkeys: HotkeyService
    let microphones = MicrophoneStore()
    @ObservationIgnored lazy var updates = AppUpdater { [weak self] in
        self?.pipeline.isBusy ?? false
    }
    let navigation = Navigation()
    private let escapeHotkey = CarbonHotkey()
    private var started = false
    private var indicator: IndicatorPanelController?

    init(settings suppliedSettings: AppSettings? = nil, dataDirectory: URL? = nil) {
        hotkeys = HotkeyService(permissions: permissions)
        let dir = dataDirectory ?? AppSettings.supportDirectory
        let settings = suppliedSettings ?? AppSettings()
        self.settings = settings
        engineStatus = EngineStatus()
        factory = EngineFactory(status: engineStatus)
        models = ModelLifecycle(settings: settings, factory: factory, engineStatus: engineStatus)
        dictionary = DictionaryStore(directory: dir)
        profiles = ProfileStore(directory: dir)

        do {
            history = try HistoryStore(directory: dir)
        } catch {
            history = nil
            Self.log.error("history unavailable: \(error.localizedDescription, privacy: .public)")
        }

        pipeline = DictationPipeline(
            settings: settings,
            dictionary: dictionary,
            profiles: profiles,
            history: history,
            factory: factory
        )
    }

    /// Call once from the app delegate.
    func start() {
        guard !started else { return }
        started = true
        Self.log.notice("start: accessibilityTrusted=\(AppContextReader.isAccessibilityTrusted, privacy: .public)")

        let panel = IndicatorPanelController(pipeline: pipeline) { [weak self] in self?.settings.hudStyle ?? .classic }
        indicator = panel
        pipeline.onStateChange = { [weak panel, weak self] state in
            AppContainer.log.notice("pipeline state: \(String(describing: state), privacy: .public)")
            panel?.update(for: state)
            // Esc cancels only while recording, so it never steals Esc elsewhere.
            if state == .recording { self?.escapeHotkey.register(.escape) } else { self?.escapeHotkey.unregister() }
        }
        escapeHotkey.onPress = { [weak self] in self?.pipeline.cancel() }

        permissions.accessibilityDidChange = { [weak self] in self?.hotkeys.refreshPermissionState() }
        permissions.startMonitoring()
        registerHotkeys()
        applyAppearance()
        observeAppearance()
        observeWindows()
        pipeline.onLLMUsed = { [weak self] instance in self?.models.noteLLMUsed(instance) }
        pipeline.llmNeedsLoad = { [weak self] in await self?.models.llmNeedsLoad() ?? false }
        pipeline.loadLLM = { [weak self] in await self?.models.loadLLMIfNeeded() }
        models.start()
    }

    /// SwiftUI's window opener, captured by the menu-bar label so AppKit callbacks can use it.
    @ObservationIgnored var openWindowAction: OpenWindowAction?

    func showMainWindow(_ open: OpenWindowAction? = nil) {
        NSApp.setActivationPolicy(.regular)
        (open ?? openWindowAction)?(id: "main")
        NSApp.activate(ignoringOtherApps: true)
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
                    NSApp.activate(ignoringOtherApps: true)
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

    private func applyAppearance() {
        switch settings.appearance {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func observeAppearance() {
        withObservationTracking {
            _ = settings.appearance
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyAppearance()
                self.observeAppearance()
            }
        }
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
        hotkeys.onPress = { [weak self] in
            guard let self else { return }
            switch self.settings.hotkeyBehavior {
            case .hold: self.pipeline.startRecording()
            case .toggle: self.pipeline.toggle()
            }
        }
        hotkeys.onRelease = { [weak self] in
            guard let self, self.settings.hotkeyBehavior == .hold else { return }
            self.pipeline.stopAndProcess()
        }
        hotkeys.apply(settings.hotkey)
        observeHotkeyChanges()
    }

    /// Re-arms the monitor whenever Settings changes the hotkey.
    private func observeHotkeyChanges() {
        withObservationTracking {
            _ = settings.hotkey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.hotkeys.apply(self.settings.hotkey)
                self.observeHotkeyChanges()
            }
        }
    }
}
