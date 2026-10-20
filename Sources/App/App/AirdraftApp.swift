import AppKit
import AirdraftCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shutdownStarted = false
    private var shutdownFinished = false
    /// The bounded delivery wait that a quit request started, if any.
    private var deliveryWait: Task<Void, Never>?
    /// Set only by that wait's own terminate request and consumed by the next
    /// `applicationShouldTerminate`, so no cancel path can leave it behind.
    private var resumingAfterDeliveryWait = false

    /// `.terminateLater` spins a nested run loop that cannot run main-actor work
    /// queued behind the caller, so quitting deadlocked. Instead: cancel, free the
    /// models, then terminate again.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        // Offscreen renders own disposable containers. Do not instantiate the
        // user's shared container or enter normal model cleanup while exiting.
        if RenderMode.isActive { return .terminateNow }
        #endif
        if shutdownFinished { return .terminateNow }
        // Every quit request after a finished wait waits again for newer deliveries.
        let resumed = resumingAfterDeliveryWait
        resumingAfterDeliveryWait = false
        if !shutdownStarted {
            let app = AppContainer.shared
            if app.cleanup.isRunning { return .terminateCancel }
            // Repeated quit requests join the wait already running.
            if deliveryWait != nil { return .terminateCancel }
            // A delivered dictation releases the pipeline before its history
            // is saved. Finish that tail (bounded) and restore the clipboard
            // now, then ask again; anything still unsaved reaches the alert.
            if app.pipeline.hasPendingDelivery && !resumed {
                deliveryWait = Task { @MainActor [weak self] in
                    let pipeline = AppContainer.shared.pipeline
                    _ = try? await OperationDeadline.run(seconds: 5) { @MainActor in
                        await pipeline.finishPendingDelivery(flushClipboard: true)
                    }
                    self?.deliveryWait = nil
                    self?.resumingAfterDeliveryWait = true
                    NSApp.terminate(nil)
                    // Consumed by the call above; never carried to a later quit.
                    self?.resumingAfterDeliveryWait = false
                }
                return .terminateCancel
            }
            // A copy that never opened app data has no unsaved work to discard.
            // Its unavailable HistoryStore must not open another quit alert.
            if app.dataLease != nil && app.cleanup.finishedScope != .reset && (app.pipeline.hasRecoverableRecording || app.pipeline.historyStorageError != nil || app.pipeline.isFinishingDelivery ||
               app.dictionary.persistenceError != nil || app.profiles.persistenceError != nil ||
               (app.pipeline.isBusy && !app.pipeline.isMaintainingData) || app.downloads.isBusy) {
                let alert = NSAlert()
                alert.messageText = String(localized: "Quit with unfinished work?")
                alert.informativeText = app.meeting?.isBusy == true
                    ? String(localized: "Airdraft will stop and save the meeting before quitting. If saving fails, captured audio remains available for recovery in Meetings.")
                    : String(localized: "Saved media jobs can resume from Meetings. Unsaved changes and captured audio kept for retry will be lost. Active dictation and downloads will stop. Keep Airdraft open to finish or save your work.")
                alert.addButton(withTitle: String(localized: "Keep Open"))
                alert.addButton(withTitle: app.meeting?.isBusy == true ? String(localized: "Save Meeting and Quit") : String(localized: "Quit and Discard"))
                guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
                app.media?.cancel()
                app.pipeline.cancel()
                app.downloads.cancelAll()
            }
            shutdownStarted = true
            app.beginShutdown()
            Task { @MainActor [weak self] in
                await AppContainer.shared.meeting?.prepareForQuit()
                await AppContainer.shared.models.shutdown()
                self?.shutdownFinished = true
                NSApp.terminate(nil)
            }
        }
        return .terminateCancel
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it runs shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppContainer.shared.showMainWindow()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if runDebugEntryPoint() { return }
        #endif
        AppContainer.shared.start()
        AppContainer.shared.updates.start()
    }

    #if DEBUG
    /// Renders and self-tests. Returns true when one of them owns this launch.
    @MainActor private func runDebugEntryPoint() -> Bool {
        // Debug aid: `airdraft --render-hud /path/out.png` writes the HUD as an
        // image and exits, so the design can be checked without screen recording.
        let args = CommandLine.arguments
        if LocalE2E.isActive {
            if LocalE2E.runAction() { return true }
            if !args.contains("--render-window"), !args.contains("--render-hud") {
                AppContainer.shared.start()
                AppContainer.shared.showMainWindow()
                if args.contains("--e2e-menu") {
                    Task { @MainActor in
                        await Task.yield()
                        AppContainer.shared.openWindowAction?(id: "e2e-menu")
                    }
                }
                return true
            }
        }
        if let idx = args.firstIndex(of: "--preview-profiles"), idx + 1 < args.count {
            ProfilePreview.open(directory: URL(fileURLWithPath: args[idx + 1]))
            return true
        }
        if let idx = args.firstIndex(of: "--render-profile-states"), idx + 1 < args.count {
            ProfilePreview.render(to: URL(fileURLWithPath: args[idx + 1]))
            NSApp.terminate(nil)
            return true
        }
        if let idx = args.firstIndex(of: "--render-hud"), idx + 1 < args.count {
            DebugRender.renderHUD(to: URL(fileURLWithPath: args[idx + 1]))
            NSApp.terminate(nil)
            return true
        }
        // `airdraft --render-window <page> <dir> [height]` writes <dir>/<page>-{dark,light}.png and exits.
        if let idx = args.firstIndex(of: "--render-window"), idx + 2 < args.count {
            let height = args.count > idx + 3 ? Double(args[idx + 3]) ?? 660 : 660
            DebugRender.renderWindow(pageName: args[idx + 1], toDirectory: URL(fileURLWithPath: args[idx + 2]), height: height)
            NSApp.terminate(nil)
            return true
        }
        if ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST"] == "microphones" {
            MicrophoneSelfTest.run()
            return true
        }
        if ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST"] == "connections" {
            SelfTest.run(mode: "connections")
            return true
        }
        if ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST_ISOLATED"] == "1",
           let path = ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST"] {
            IsolatedPipelineSelfTest.run(path: path)
            return true
        }
        // Self-test: AIRDRAFT_SELFTEST=mic records 3 s from the microphone;
        // AIRDRAFT_SELFTEST=<path.wav> feeds that file. Either way the HUD, the
        // engines, the dictionary and history run for real; insertion is skipped.
        guard let mode = ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST"] else { return false }
        AppContainer.shared.start()
        SelfTest.run(mode: mode)
        return true
    }
    #endif
}

@main
struct AirdraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let container = AppContainer.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(container)
        } label: {
            MenuBarLabel(container: container)
        }
        .menuBarExtraStyle(.menu)

        #if DEBUG
        Window("Airdraft E2E Menu", id: "e2e-menu") {
            if LocalE2E.isActive {
                VStack(alignment: .leading, spacing: 12) {
                    MenuView().environment(container)
                }
                .padding(20)
                .frame(width: 420)
            }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .commandsRemoved()
        #endif

        Window("Airdraft", id: "main") {
            MainWindowView()
                .environment(container)
                // With keyboard navigation on, macOS outlines the focused control in blue
                // around the soft surfaces. Sheets and popovers inherit this from the root.
                .focusEffectDisabled()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: Theme.windowWidth, height: 660)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Set Up Airdraft…")) { container.showOnboarding() }
                    .disabled(container.pipeline.isBusy)
                Button(String(localized: "License…")) { container.showLicense() }
                Button(String(localized: "Check for Updates…")) { container.updates.checkForUpdates() }
                    .disabled(!container.updates.canCheckForUpdates)
            }
            // ⌘, opens Settings.
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "Settings…")) { show(.configuration) }
                    .keyboardShortcut(",")
            }
            CommandMenu(String(localized: "Go")) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.title) { show(page) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
    }

    private func show(_ page: Page) {
        container.navigation.page = page
        container.showMainWindow()
    }
}

/// The menu-bar icon. Always rendered at launch, so it is where AppKit code gets
/// SwiftUI's `openWindow` action from.
private struct MenuBarLabel: View {
    let container: AppContainer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: container.menuIcon)
            .onAppear {
                container.openWindowAction = openWindow
                if !RenderMode.isActive, !RenderMode.excludesCredentials,
                   container.settings.onboarding.shouldPresentOnLaunch {
                    container.showOnboarding()
                }
            }
    }
}
