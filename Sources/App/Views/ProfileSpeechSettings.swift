import AirdraftCore
import SwiftUI

struct ProfileSpeechSettings: View {
    @Environment(AppContainer.self) private var container
    @Binding var selection: ProfileSpeechModel?

    private struct Choice: Identifiable {
        let title: String
        let selection: ProfileSpeechModel
        var id: ProfileSpeechModel { selection }
    }

    private var config: ASRConfig { selection?.applying(to: container.settings.asr) ?? container.settings.asr }

    private var localChoices: [Choice] {
        // A retired model stays choosable only where it is already in use.
        let asr = container.settings.asr
        return ModelCatalogue.entries.filter {
            !$0.retired || $0.isSelected(asr) || selection == ProfileSpeechModel(config: $0.config(from: asr))
        }.map {
            Choice(title: "\($0.title) · \($0.vendor)", selection: ProfileSpeechModel(config: $0.config(from: container.settings.asr)))
        }
    }

    private var cloudChoices: [Choice] {
        EndpointPreset.asr.flatMap { preset in
            SpeechModelInfo.models(for: preset.kind).map { model in
                var config = container.settings.asr
                config.select(preset.kind)
                config.selectModel(model.id)
                return Choice(title: "\(model.title) · \(preset.name)", selection: ProfileSpeechModel(config: config))
            }
        }
    }

    /// Keep a custom endpoint or a saved OpenRouter model selectable even when
    /// it is not in the built-in catalogue. No model discovery or key reads here.
    private var savedChoices: [Choice] {
        var choices = localChoices + cloudChoices
        var saved: [Choice] = []
        for candidate in [selection, ProfileSpeechModel(config: container.settings.asr)].compactMap({ $0 }) {
            guard !choices.contains(where: { $0.selection == candidate }) else { continue }
            let choice = Choice(title: candidate.applying(to: container.settings.asr).displayName, selection: candidate)
            saved.append(choice)
            choices.append(choice)
        }
        return saved
    }

    private var needsDownload: Bool { config.kind.isLocal && !LocalModels.isInstalled(config) }

    var body: some View {
        PageSection("Speech model") {
            SettingsCard {
                SettingRow(title: "Model", detail: selection == nil ? String(localized: "Follows the selection in Models") : String(localized: "Used when this profile is active")) {
                    SoftPicker("Profile speech model", selection: $selection, width: 240) {
                        Text("Use App Default").tag(ProfileSpeechModel?.none)
                        Section("On This Mac") {
                            ForEach(localChoices) { choice in
                                Text(choice.title).tag(Optional(choice.selection))
                            }
                        }
                        Section("Cloud") {
                            ForEach(cloudChoices) { choice in
                                Text(choice.title).tag(Optional(choice.selection))
                            }
                        }
                        if !savedChoices.isEmpty {
                            Section("Saved Selection") {
                                ForEach(savedChoices) { choice in
                                    Text(choice.title).tag(Optional(choice.selection))
                                }
                            }
                        }
                    }
                    .help(config.engineLabel)
                    .accessibilityIdentifier("profiles.speechModel")
                }
                RowDivider()
                SettingRow(title: .verbatim(config.displayName), detail: detail) {
                    Button("Models") { container.navigation.page = .models }
                        .buttonStyle(SoftButtonStyle())
                        .accessibilityLabel("Manage speech models")
                }
            }
        }
    }

    private var detail: String {
        if let reason = selection?.unavailableReason { return reason }
        do { _ = try SpeechLanguagePolicy.resolve(config) }
        catch { return error.localizedDescription }
        if needsDownload { return String(localized: "Not installed. Download it in Models before dictating.") }
        if config.kind.isLocal { return String(localized: "Runs on this Mac. Language follows Speech options.") }
        let destination = config.kind.preset?.name ?? URL(string: config.baseURL)?.host ?? "your server"
        return String(localized: "Audio is sent to \(destination). Configure access in Models.")
    }
}
