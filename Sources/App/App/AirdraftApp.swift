import AppKit
import AirdraftCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shutdownStarted = false
    private var shutdownFinished = false

    /// `.terminateLater` spins a nested run loop that cannot run main-actor work
    /// queued behind the caller, so quitting deadlocked. Instead: cancel, free the
    /// models, then terminate again.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shutdownFinished { return .terminateNow }
        if !shutdownStarted {
            let app = AppContainer.shared
            if app.pipeline.hasRecoverableRecording || app.pipeline.historyStorageError != nil ||
               app.dictionary.persistenceError != nil || app.profiles.persistenceError != nil ||
               app.pipeline.isBusy || app.downloads.isBusy {
                let alert = NSAlert()
                alert.messageText = "Quit with unfinished work?"
                alert.informativeText = "Unsaved changes and captured audio kept for retry will be lost. Active dictation and downloads will stop. Keep Airdraft open to finish or save your work."
                alert.addButton(withTitle: "Keep Open")
                alert.addButton(withTitle: "Quit and Discard")
                guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
                app.pipeline.cancel()
                app.downloads.cancelAll()
            }
            shutdownStarted = true
            Task { @MainActor [weak self] in
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

        Window("Airdraft", id: "main") {
            MainWindowView()
                .environment(container)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: Theme.windowWidth, height: 660)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { container.updates.checkForUpdates() }
                    .disabled(!container.updates.canCheckForUpdates)
            }
            // Configuration is the app's settings, so ⌘, opens it.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { show(.configuration) }
                    .keyboardShortcut(",")
            }
            CommandMenu("Go") {
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
            .onAppear { container.openWindowAction = openWindow }
    }
}
