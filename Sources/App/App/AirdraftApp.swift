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
        // Debug aid: `airdraft --render-hud /path/out.png` writes the HUD as an
        // image and exits, so the design can be checked without screen recording.
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--render-hud"), idx + 1 < args.count {
            DebugRender.renderHUD(to: URL(fileURLWithPath: args[idx + 1]))
            NSApp.terminate(nil)
            return
        }
        // `airdraft --render-window <page> <dir> [height]` writes <dir>/<page>-{dark,light}.png and exits.
        if let idx = args.firstIndex(of: "--render-window"), idx + 2 < args.count {
            let height = args.count > idx + 3 ? Double(args[idx + 3]) ?? 660 : 660
            DebugRender.renderWindow(pageName: args[idx + 1], toDirectory: URL(fileURLWithPath: args[idx + 2]), height: height)
            NSApp.terminate(nil)
            return
        }
        AppContainer.shared.start()

        // Self-test: AIRDRAFT_SELFTEST=mic records 3 s from the microphone;
        // AIRDRAFT_SELFTEST=<path.wav> feeds that file. Either way the HUD, the
        // engines, the dictionary and history run for real; insertion is skipped.
        if let mode = ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST"] {
            SelfTest.run(mode: mode)
        }
    }
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
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 660)
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
