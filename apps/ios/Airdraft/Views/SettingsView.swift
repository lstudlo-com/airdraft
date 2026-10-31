import AirdraftCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MobileSettings.self) private var mobile
    @Environment(ProfileStore.self) private var profiles
    @Environment(DictionaryStore.self) private var dictionary

    @State private var path: [Destination] = []

    enum Destination: Hashable { case speech, refinement, keyboardSetup }

    var body: some View {
        @Bindable var settings = settings
        @Bindable var mobile = mobile
        NavigationStack(path: $path) {
            SoftPage {
                SoftSection(title: "Speech") {
                    NavigationLink(value: Destination.speech) {
                        SettingLink(title: "Speech model", value: settings.asr.displayName)
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    NavigationLink { SpeechLanguageView() } label: {
                        SettingLink(title: "Language", value: SpeechLanguageView.label(for: settings.asr.language))
                    }
                    .buttonStyle(.plain)
                }
                SoftSection(title: "Refinement") {
                    NavigationLink(value: Destination.refinement) {
                        SettingLink(title: "Refinement", value: settings.llm.kind == .none ? String(localized: "Off") : settings.llm.displayName)
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    NavigationLink { ProfilesView() } label: {
                        SettingLink(title: "Profile", value: profiles.activeProfile.displayName)
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    NavigationLink { VocabularyView() } label: {
                        SettingLink(title: "Vocabulary", value: String(localized: "\(dictionary.entries.count) terms"))
                    }
                    .buttonStyle(.plain)
                }
                SoftSection(title: "Keyboard") {
                    NavigationLink(value: Destination.keyboardSetup) {
                        SettingLink(title: "Set up the Airdraft keyboard", value: "")
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    SettingPickerRow(title: "Session length", detail: "How long the microphone stays ready for the keyboard.") {
                        Picker("Session length", selection: $mobile.sessionMinutes) {
                            ForEach(MobileSettings.sessionChoices, id: \.self) { minutes in
                                Text(Duration.seconds(minutes * 60), format: .units(allowed: [.hours, .minutes], width: .wide)).tag(minutes)
                            }
                        }
                    }
                }
                SoftSection(title: "Recording") {
                    Toggle(isOn: $mobile.copiesResult) {
                        SettingLabel(title: "Copy each dictation", detail: "Dictations made in Airdraft go to the clipboard.")
                    }
                    .frame(minHeight: MobileTheme.touchTarget)
                    RowDivider()
                    SettingPickerRow(title: "Recording limit", detail: nil) {
                        Picker("Recording limit", selection: $settings.maxRecordingSeconds) {
                            ForEach([60, 120, 300, 600], id: \.self) { seconds in
                                Text(Duration.seconds(seconds), format: .units(allowed: [.minutes], width: .wide)).tag(seconds)
                            }
                        }
                    }
                    RowDivider()
                    SettingPickerRow(title: "Keep recordings", detail: "Saved audio stays on this iPhone.") {
                        Picker("Keep recordings", selection: $settings.audioRetention) {
                            ForEach(AudioRetention.allCases) { retention in
                                Text(retention.title).tag(retention)
                            }
                        }
                    }
                }
                SoftSection(title: "About") {
                    NavigationLink { AboutView() } label: {
                        SettingLink(title: "About Airdraft", value: Bundle.main.shortVersion)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .speech: SpeechModelsView()
                case .refinement: RefinementSettingsView()
                case .keyboardSetup: KeyboardSetupView()
                }
            }
        }
        #if DEBUG
        .onAppear {
            switch DebugLaunch.screen {
            case "speech": path = [.speech]
            case "refinement": path = [.refinement]
            case "keyboard-setup": path = [.keyboardSetup]
            default: break
            }
        }
        #endif
    }
}

/// A navigation row: title on the leading edge, current value and chevron trailing.
struct SettingLink: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: MobileTheme.touchTarget)
        .contentShape(Rectangle())
    }
}

/// A setting with its menu picker at the trailing edge.
struct SettingPickerRow<Picker: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @ViewBuilder var picker: Picker

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingLabel(title: title, detail: detail)
            Spacer(minLength: 8)
            picker
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
        }
        .frame(minHeight: MobileTheme.touchTarget)
    }
}

/// A setting's title with an optional one-phrase description below it.
struct SettingLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

struct AboutView: View {
    var body: some View {
        SoftPage {
            SoftCard {
                Text("Airdraft turns your voice into text. Recordings and transcripts stay on this iPhone unless you choose an online speech or refinement service, which receives the audio or text it processes.")
                    .fixedSize(horizontal: false, vertical: true)
                RowDivider()
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.shortVersion).foregroundStyle(.secondary)
                }
            }
            if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                NavigationLink { AcknowledgementsView(url: url) } label: {
                    SettingLink(title: "Acknowledgements", value: "")
                }
                .padding(.horizontal, MobileTheme.cardPadding)
                .background { MobileRaisedSurface(shape: MobileTheme.cardShape, elevation: .card) }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AcknowledgementsView: View {
    let url: URL
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding()
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let url = self.url
            text = await Task.detached { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }.value
        }
    }
}
