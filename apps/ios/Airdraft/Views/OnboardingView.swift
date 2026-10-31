import AirdraftCore
import AVFoundation
import SwiftUI

/// First-run setup in four short steps: what Airdraft does, microphone access,
/// the speech model, and the keyboard. Every step can be skipped and changed
/// later in Settings.
struct OnboardingView: View {
    let finish: () -> Void

    @Environment(MobileSettings.self) private var mobile
    @Environment(AppSettings.self) private var settings
    @State private var step = 0
    @State private var microphone = AVAudioApplication.shared.recordPermission

    private let steps = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $step) {
                    welcome.tag(0)
                    microphoneStep.tag(1)
                    speechStep.tag(2)
                    keyboardStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                Button(step == steps - 1 ? "Start Dictating" : "Continue") {
                    if step == steps - 1 { complete() } else { withAnimation { step += 1 } }
                }
                .buttonStyle(.softProminent)
                .padding(.horizontal, MobileTheme.pagePadding)
                .padding(.bottom, 12)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Set Up Later") { complete() }
                }
            }
        }
    }

    private func complete() {
        mobile.hasCompletedOnboarding = true
        finish()
    }

    private var welcome: some View {
        OnboardingPage(symbol: "waveform", title: "Speak, and Airdraft writes it down",
                       message: "Record in Airdraft or with the Airdraft keyboard in any app. Airdraft turns your voice into clean text you can paste anywhere.")
    }

    private var microphoneStep: some View {
        OnboardingPage(symbol: "mic", title: "Allow the microphone",
                       message: "Airdraft listens only while you record or while a keyboard session is on.") {
            switch microphone {
            case .granted:
                Label("Microphone allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            case .denied:
                VStack(spacing: 12) {
                    Text("Microphone access is off. Turn it on for Airdraft in Settings.")
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.soft)
                }
            default:
                Button("Allow Microphone") {
                    Task {
                        _ = await AudioRecorder.requestMicrophoneAccess()
                        microphone = AVAudioApplication.shared.recordPermission
                    }
                }
                .buttonStyle(.soft)
            }
        }
    }

    private var speechStep: some View {
        OnboardingPage(symbol: "text.bubble", title: "Speech recognition",
                       message: "Airdraft starts with the speech recognition built into iOS. You can download a model or add an online service with your own key in Settings.") {
            Text(settings.asr.displayName)
                .font(.headline)
        }
    }

    private var keyboardStep: some View {
        OnboardingPage(symbol: "keyboard", title: "Dictate in any app",
                       message: "Turn on the Airdraft keyboard in Settings, start a keyboard session, then tap its microphone in any app.") {
            NavigationLink("Keyboard Setup") { KeyboardSetupView() }
                .buttonStyle(.soft)
        }
    }
}

private struct OnboardingPage<Accessory: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 28, style: .continuous), depth: 4)
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 112, height: 112)
                .padding(.top, 40)
                .accessibilityHidden(true)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

extension OnboardingPage where Accessory == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
