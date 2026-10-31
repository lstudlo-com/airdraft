import AirdraftCore
import SwiftUI

struct HomeView: View {
    let openSettings: () -> Void

    @Environment(DictationController.self) private var controller
    @Environment(MobileDictation.self) private var dictation
    @Environment(AppSettings.self) private var settings
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.scenePhase) private var scenePhase
    /// Measured off the view body: it reads the Keychain and model files.
    @State private var setupIssue: String?

    var body: some View {
        NavigationStack {
            SoftPage {
                hero
                if let result = controller.lastResult {
                    ResultCard(result: result)
                }
                KeyboardSessionCard()
            }
            .navigationTitle(Text(verbatim: "Airdraft"))
        }
        .task(id: ReadinessKey(asr: settings.asr, llm: settings.llm, profile: profiles.activeProfileID,
                               phase: dictation.phase, scene: scenePhase)) {
            setupIssue = dictation.phase == .idle ? dictation.readinessIssue() : nil
        }
    }

    private struct ReadinessKey: Equatable {
        let asr: ASRConfig
        let llm: LLMConfig
        let profile: UUID
        let phase: MobileDictation.Phase
        let scene: ScenePhase
    }

    private var hero: some View {
        SoftCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if dictation.phase == .recording, let started = dictation.recordingStartedAt {
                    Text(started, style: .timer)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Recording time"))
                }
            }
            LevelWell(levels: dictation.levels)
            RecordKey(mode: keyMode) { controller.toggleRecording() }
            if let issue = setupIssue {
                Divider().opacity(0)
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(issue)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Settings", action: openSettings)
                        .buttonStyle(.soft)
                        .fixedSize()
                }
            } else if let notice = controller.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var keyMode: RecordKey.Mode {
        switch dictation.phase {
        case .idle: .idle
        case .recording: .recording
        case .transcribing, .refining: .busy
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch dictation.phase {
        case .idle: "Ready to dictate"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .refining: "Refining…"
        }
    }

    private var statusDetail: String {
        let profile = profiles.activeProfile
        let speech = profile.speechConfig(default: settings.asr).displayName
        return "\(profile.displayName) · \(speech)"
    }
}

/// The last dictation, selectable, with Copy and Share.
private struct ResultCard: View {
    let result: MobileDictationResult
    @State private var copied = false

    var body: some View {
        SoftSection(title: "Last dictation") {
            Text(result.final)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error = result.refinementError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = result.final
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.soft)
                ShareLink(item: result.final) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.soft)
            }
        }
        .onChange(of: result.id) { _, _ in copied = false }
    }
}

/// Starts and shows the keyboard session that lets the Airdraft keyboard record from any app.
private struct KeyboardSessionCard: View {
    @Environment(DictationController.self) private var controller
    @Environment(MobileSettings.self) private var mobile

    var body: some View {
        SoftSection(title: "Dictate in any app") {
            if let ends = controller.sessionEndsAt {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard session on")
                            .font(.headline)
                        Text("Ends at \(ends, style: .time). Switch to the Airdraft keyboard and tap the microphone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("End Session") { controller.endSession() }
                    .buttonStyle(.soft)
            } else {
                Text("Start a session, then use the Airdraft keyboard in any app. The microphone stays ready for \(mobile.sessionMinutes) minutes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start Keyboard Session") { controller.startSession() }
                    .buttonStyle(.softProminent)
                NavigationLink {
                    KeyboardSetupView()
                } label: {
                    Text("Set Up the Keyboard")
                }
                .buttonStyle(.soft)
            }
        }
    }
}
