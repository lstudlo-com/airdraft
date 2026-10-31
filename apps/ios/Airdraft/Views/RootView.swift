import AirdraftCore
import SwiftUI

/// Three tabs in the system's Liquid Glass tab bar; the neumorphic material
/// stays in the pages' content.
struct RootView: View {
    enum Tab: Hashable { case home, history, transcribe, settings }

    @Environment(MobileSettings.self) private var mobile
    @State private var tab: Tab = .home
    @State private var showsOnboarding = false

    var body: some View {
        #if DEBUG
        if DebugLaunch.screen == "keyboard" {
            KeyboardPreviewScreen()
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab("Home", systemImage: "waveform", value: Tab.home) {
                HomeView(openSettings: { tab = .settings })
            }
            SwiftUI.Tab("History", systemImage: "clock", value: Tab.history) {
                HistoryView()
            }
            SwiftUI.Tab("Transcribe", systemImage: "text.quote", value: Tab.transcribe) {
                TranscribeView()
            }
            SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) {
                SettingsView()
            }
        }
        .onAppear {
            showsOnboarding = !mobile.hasCompletedOnboarding
            #if DEBUG
            if let screen = DebugLaunch.screen {
                showsOnboarding = screen == "onboarding"
                tab = switch screen {
                case "history": .history
                case "transcribe": .transcribe
                case "settings", "speech", "refinement", "keyboard-setup": .settings
                default: .home
                }
            }
            #endif
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingView { showsOnboarding = false }
        }
    }
}
