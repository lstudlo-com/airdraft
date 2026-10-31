import AirdraftCore
import AppIntents
import SwiftUI

@main
struct AirdraftMobileApp: App {
    @State private var container = MobileContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(container.controller)
                .environment(container.settings)
                .environment(container.mobile)
                .environment(container.profiles)
                .environment(container.dictionary)
                .environment(container.downloads)
                .environment(container.dictation)
                .environment(container.transcribe)
                .onOpenURL { url in handle(url) }
                .task {
                    connectIntents()
                    #if DEBUG
                    DebugLaunch.loadSampleData(into: container)
                    #endif
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { container.controller.refresh() }
        }
    }

    /// `airdraft://dictate` records now; `airdraft://session` opens a keyboard session.
    private func handle(_ url: URL) {
        switch url.host() {
        case "dictate": container.controller.start(origin: .app)
        case "session": container.controller.startSession()
        default: break
        }
    }

    private func connectIntents() {
        let controller = container.controller
        DictationIntentRouter.shared.handler = { action in
            switch action {
            case .dictate: controller.start(origin: .app)
            case .startKeyboardSession: controller.startSession()
            }
        }
    }
}

struct AirdraftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDictationIntent(),
                    phrases: ["Dictate with \(.applicationName)", "Start \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Dictate", table: "Shared"),
                    systemImageName: "mic.fill")
        AppShortcut(intent: StartKeyboardSessionIntent(),
                    phrases: ["Start a keyboard session in \(.applicationName)"],
                    shortTitle: LocalizedStringResource("Keyboard Session", table: "Shared"),
                    systemImageName: "keyboard")
    }
}
