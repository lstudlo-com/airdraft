import AirdraftCore
import SwiftUI

/// Speech models that suit an iPhone: the recognizer built into iOS, Core ML
/// and small GGUF models that fit the app's memory, and online services with
/// your own key. Sizes and languages come from the same pinned catalogues as
/// the Mac. None of these has been measured on an iPhone yet, so the list
/// makes no accuracy or speed claims.
enum MobileSpeechCatalogue {
    struct Choice: Identifiable {
        let id: String
        let title: String
        let bytes: Int64?
        let languages: [String]
        let config: (ASRConfig) -> ASRConfig
    }

    static func local() -> [Choice] {
        var choices: [Choice] = [
            Choice(id: "apple", title: "Apple Speech", bytes: nil, languages: []) { base in
                var config = base
                config.select(.apple)
                return config
            },
        ]
        for id in ["parakeet-v3-int4", "parakeet-v3", "parakeet-v2", "parakeet-ja"] {
            guard let model = CoreMLSpeechModelCatalog.model(id) else { continue }
            choices.append(Choice(id: "coreml:\(id)", title: model.title, bytes: model.bytes, languages: model.languages) { base in
                var config = base
                config.select(.fluidAudio)
                config.model = id
                return config
            })
        }
        let whisper = "large-v3-v20240930_626MB"
        if let variant = WhisperModelVariant(rawValue: whisper), let artifact = PinnedHubModelCatalog.whisper(variant) {
            choices.append(Choice(id: "whisper:\(whisper)", title: "Whisper Large v3 Turbo",
                                  bytes: artifact.bytes, languages: []) { base in
                var config = base
                config.select(.whisperKit)
                config.whisperModel = whisper
                return config
            })
        }
        for id in ["sensevoice-small", "whisper-small", "whisper-base"] {
            guard let model = GGUFModelCatalog.model(id) else { continue }
            choices.append(Choice(id: "gguf:\(id)", title: model.title, bytes: model.bytes, languages: model.languages) { base in
                var config = base
                config.select(.transcribeCpp)
                config.model = id
                return config
            })
        }
        return choices
    }

    static func languageSummary(_ codes: [String]) -> String? {
        switch codes.count {
        case 0: return nil
        case 1: return SpeechLanguagePolicy.languageLabel(codes[0])
        default: return String(localized: "\(codes.count) languages")
        }
    }
}

struct SpeechModelsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ModelDownloadStore.self) private var downloads
    @State private var installed: Set<String> = []
    @State private var refresh = 0

    var body: some View {
        SoftPage {
            SoftSection(title: "On this iPhone") {
                let choices = MobileSpeechCatalogue.local()
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                    if index > 0 { RowDivider() }
                    LocalModelRow(choice: choice, isSelected: isSelected(choice),
                                  isInstalled: installed.contains(choice.id),
                                  job: downloads.jobs[choice.config(settings.asr).engineID]) { action in
                        perform(action, on: choice)
                    }
                }
            }
            Text("Models download only when you tap Download, and stay on this iPhone. Speed and accuracy have not been measured on iPhone yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            SoftSection(title: "Online with your key") {
                ForEach(Array(EndpointPreset.asr.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 { RowDivider() }
                    CloudSpeechRow(preset: preset, isSelected: settings.asr.kind == preset.kind) {
                        settings.asr.select(preset.kind)
                    }
                }
            }
            Text("Online services receive the audio of each dictation and bill your account.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .navigationTitle("Speech Model")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: TaskKey(refresh: refresh, jobs: downloads.jobs.count)) { await measureInstalled() }
    }

    private struct TaskKey: Equatable {
        let refresh: Int
        let jobs: Int
    }

    private func isSelected(_ choice: MobileSpeechCatalogue.Choice) -> Bool {
        choice.config(settings.asr).engineID == settings.asr.engineID
    }

    /// Installation checks touch the file system; never in a view body.
    private func measureInstalled() async {
        let configs = MobileSpeechCatalogue.local().map { ($0.id, $0.config(settings.asr)) }
        installed = await Task.detached(priority: .utility) {
            Set(configs.filter { LocalModels.isInstalled($0.1) }.map(\.0))
        }.value
    }

    private func perform(_ action: LocalModelRow.Action, on choice: MobileSpeechCatalogue.Choice) {
        let config = choice.config(settings.asr)
        switch action {
        case .use:
            settings.asr = config
        case .download:
            downloads.start(config) { refresh += 1 }
        case .cancel:
            downloads.cancel(config)
        case .delete:
            try? LocalModels.remove(config)
            refresh += 1
        }
    }
}

private struct LocalModelRow: View {
    enum Action { case use, download, cancel, delete }

    let choice: MobileSpeechCatalogue.Choice
    let isSelected: Bool
    let isInstalled: Bool
    let job: ModelDownloadStore.Job?
    let perform: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.body.weight(.semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                action
            }
            if let job {
                if let fraction = job.progress?.fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel(Text("Download progress"))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = job.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if isInstalled, choice.bytes != nil, !isSelected {
                Button("Delete Model", systemImage: "trash", role: .destructive) { perform(.delete) }
            }
        }
    }

    @ViewBuilder private var action: some View {
        if job != nil {
            Button("Cancel") { perform(.cancel) }
                .buttonStyle(.softCompact)
        } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title2)
                .accessibilityLabel(Text("In use"))
        } else if isInstalled || choice.bytes == nil {
            Button("Use") { perform(.use) }
                .buttonStyle(.softCompactProminent)
        } else {
            Button("Download") { perform(.download) }
                .buttonStyle(.softCompact)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let bytes = choice.bytes {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        } else {
            parts.append(String(localized: "Built into iOS"))
        }
        if let languages = MobileSpeechCatalogue.languageSummary(choice.languages) { parts.append(languages) }
        return parts.joined(separator: " · ")
    }
}

private struct CloudSpeechRow: View {
    let preset: EndpointPreset.Speech
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body.weight(.semibold))
                    Text(verbatim: "\(preset.modelTitle) · \(preset.price)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title2)
                        .accessibilityLabel(Text("In use"))
                } else {
                    Button("Use", action: select)
                        .buttonStyle(.softCompact)
                }
            }
            APIKeyField(account: preset.keyRef, consoleURL: preset.consoleURL)
        }
        .padding(.vertical, 4)
    }
}

/// One provider key: saved in the iPhone's Keychain, shown only as saved or missing.
struct APIKeyField: View {
    let account: String
    var consoleURL: URL? = nil

    @State private var draft = ""
    @State private var presence: Keychain.Presence = .missing
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                SecureField("API key", text: $draft)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .frame(minHeight: MobileTheme.touchTarget)
                    .background { NeumorphicSurface(shape: MobileTheme.controlShape, inset: true, depth: 1.5) }
                HStack(spacing: 12) {
                    Button("Save") {
                        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty, Keychain.set(value, for: account) { presence = .saved }
                        draft = ""
                        editing = false
                    }
                    .buttonStyle(.softProminent)
                    Button("Cancel") {
                        draft = ""
                        editing = false
                    }
                    .buttonStyle(.soft)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: presence == .saved ? "key.fill" : "key")
                        .foregroundStyle(presence == .saved ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                    Text(presence == .saved ? "Key saved" : "No key")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if presence == .saved {
                        Button("Remove", role: .destructive) {
                            if Keychain.delete(account) { presence = .missing }
                        }
                        .font(.subheadline)
                    }
                    Button(presence == .saved ? "Replace" : "Add Key") { editing = true }
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minHeight: MobileTheme.touchTarget)
                if presence != .saved, let consoleURL {
                    Link("Get a key", destination: consoleURL)
                        .font(.footnote)
                }
            }
        }
        .task(id: account) { presence = Keychain.presence(account) }
    }
}

struct SpeechLanguageView: View {
    @Environment(AppSettings.self) private var settings

    static func label(for code: String) -> String {
        code.isEmpty ? String(localized: "Automatic") : SpeechLanguagePolicy.languageLabel(code)
    }

    var body: some View {
        let capabilities = SpeechLanguagePolicy.capabilities(for: settings.asr)
        let preferred = SystemLanguages.preferred.compactMap { Locale.Language(identifier: $0).languageCode?.identifier }
        let supported = capabilities.supportedLanguages ?? preferred
        let codes = (preferred.filter(supported.contains) + supported.sorted {
            SpeechLanguagePolicy.languageLabel($0).localizedStandardCompare(SpeechLanguagePolicy.languageLabel($1)) == .orderedAscending
        }).reduce(into: [String]()) { list, code in if !list.contains(code) { list.append(code) } }
        List {
            Section {
                if capabilities.supportsAutomatic != false {
                    row(code: "")
                }
                ForEach(codes, id: \.self) { row(code: $0) }
            } footer: {
                Text(capabilities.summary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(code: String) -> some View {
        Button {
            settings.asr.language = code
        } label: {
            HStack {
                Text(Self.label(for: code)).foregroundStyle(.primary)
                Spacer()
                if settings.asr.language == code {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(settings.asr.language == code ? .isSelected : [])
    }
}
