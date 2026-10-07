import AirdraftCore
import SwiftUI

/// The presentation and its source are one value; a sheet cannot open before its file arrives.
struct MediaImportRequest: Identifiable {
    enum Source { case file(URL), recording(RecordingAsset) }
    let id = UUID()
    let source: Source
    static func file(_ url: URL) -> Self { Self(source: .file(url)) }
    static func recording(_ asset: RecordingAsset) -> Self { Self(source: .recording(asset)) }
    var title: String {
        switch source {
        case .file(let url): return url.lastPathComponent
        case .recording(let asset): return asset.createdAt.formatted(date: .abbreviated, time: .shortened) + " · " + HistoryRecordingControls.time(asset.duration)
        }
    }
}

struct MediaImportSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let request: MediaImportRequest
    @State private var configuration = MediaConfiguration()
    @State private var installing = false
    @State private var installTask: Task<Void, Never>?
    @State private var progress: Double?
    @State private var issue: String?
    @State private var speechInstalled = false
    @State private var checking = true
    @State private var readinessID = UUID()
    @State private var speakerInstalled = LocalSpeakerDiarizer.isInstalled
    @State private var appleLocales: [String] = []
    private var capabilities: SpeechLanguageCapabilities { SpeechLanguagePolicy.capabilities(for: configuration.asr) }
    private var validationIssue: String? {
        do { try configuration.validate(); return nil } catch { return error.localizedDescription }
    }
    private var needsModels: Bool {
        configuration.engine == .local && (!speechInstalled || (configuration.identifySpeakers && !speakerInstalled))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            Text("Transcribe Recording").font(.system(size: 18, weight: .semibold))
            Text(request.title).font(.system(size: 13)).lineLimit(2)
                .accessibilityIdentifier("media.source")
            SettingsCard {
                SettingRow(title: "Process audio") {
                    SoftPicker("Process audio", selection: $configuration.engine, width: 220) {
                        Text("On This Mac").tag(MediaConfiguration.Engine.local)
                        if !container.isolatedData { Text("Soniox · Cloud").tag(MediaConfiguration.Engine.soniox) }
                    }
                }
                if configuration.engine == .local {
                    RowDivider()
                    SettingRow(title: "Model") {
                        SoftPicker("Transcription model", selection: Binding(get: { configuration.selectedLocalModel }, set: { configuration.selectLocalModel($0) }), width: 220) {
                            ForEach(MediaConfiguration.LocalModel.allCases, id: \.self) { model in Text(model.title).tag(model) }
                        }.accessibilityIdentifier("media.model")
                    }
                }
                RowDivider()
                languageRow
                RowDivider()
                SettingRow(title: "Identify speakers") {
                    Toggle("Identify Speakers", isOn: $configuration.identifySpeakers).labelsHidden().toggleStyle(.softSwitch)
                }
            }.disabled(installing)
            if configuration.engine == .local {
                if checking { ProgressView("Checking models…").controlSize(.small) }
                else if needsModels {
                    HStack {
                        Text(!speechInstalled ? "Download the selected speech model to continue." : "Download speaker detection to continue.").supportingText()
                        Spacer()
                        if installing { ProgressView(value: progress).frame(width: 60) }
                        Button(installing ? "Cancel Download" : "Download") {
                            if installing { installTask?.cancel() } else { installModels() }
                        }.buttonStyle(SoftButtonStyle()).disabled(validationIssue != nil || container.pipeline.isBusy && !installing)
                    }
                }
                Text(configuration.usesSegmentTiming ? "Audio stays on this Mac. Timestamps mark speech segments." : "Audio stays on this Mac. Word timestamps are included.").supportingText()
            } else {
                Text("Uploads audio to Soniox using your saved API key. Provider charges apply.").supportingText()
            }
            if let issue = issue ?? validationIssue { Text(issue).supportingText().foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Text("Saved in Meetings · Up to 2 hours").supportingText()
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(SoftButtonStyle()).disabled(installing)
                Button(configuration.engine == .soniox ? "Upload and Transcribe" : "Transcribe") {
                    guard !container.pipeline.isBusy else { return }
                    switch request.source {
                    case .recording(let asset): container.media?.transcribeRecording(asset, configuration: configuration)
                    case .file(let url): container.media?.importFile(url, configuration: configuration)
                    }
                    container.navigation.page = .meetings
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("media.transcribe")
                .disabled(container.media == nil || container.pipeline.isBusy || installing || checking || needsModels || validationIssue != nil)
            }
        }
        .padding(Theme.pagePadding).frame(width: 520).background(Theme.islandBackground)
        .interactiveDismissDisabled(installing)
        .task(id: configuration.asr.engineID) { await checkModels() }
    }

    @ViewBuilder private var languageRow: some View {
        if configuration.engine == .local && configuration.selectedLocalModel == .apple {
            SettingRow(title: "Language") {
                SoftPicker("Speech language", selection: Binding(get: { configuration.appleLocale ?? "zh-TW" }, set: { configuration.appleLocale = $0; configuration.language = "" }), width: 220) {
                    ForEach(Array(Set(appleLocales + [configuration.appleLocale ?? "zh-TW"])).sorted(), id: \.self) { locale in
                        Text(Locale(identifier: "en").localizedString(forIdentifier: locale) ?? locale).tag(locale)
                    }
                }
            }
        } else {
            SettingRow(title: "Language") {
                SoftPicker("Speech language", selection: $configuration.language, width: 220) {
                    Text(capabilities.supportsAutomatic == false ? "Choose a Language" : "Detect Automatically").tag("")
                    ForEach(capabilities.supportedLanguages ?? ["en", "zh", "yue"], id: \.self) { code in
                        Text(SpeechLanguagePolicy.languageName(code)).tag(code)
                    }
                }
            }
        }
    }
    private func checkModels() async {
        let token = UUID(); readinessID = token
        checking = true
        defer { if readinessID == token { checking = false } }
        let config = configuration.asr
        let ready: Bool
        if config.kind == .apple {
            appleLocales = await AppleSpeechTranscriber.supportedLocaleIdentifiers()
            ready = await AppleSpeechTranscriber(locale: config.effectiveAppleLocale).isReady()
        } else { ready = LocalModels.isInstalled(config) }
        guard !Task.isCancelled, readinessID == token, config.engineID == configuration.asr.engineID else { return }
        speechInstalled = ready
        speakerInstalled = LocalSpeakerDiarizer.isInstalled
    }
    private func installModels() {
        guard !container.pipeline.isBusy else { return }
        installing = true; issue = nil; progress = nil; container.pipeline.isProcessingMedia = true
        let config = configuration.asr
        installTask = Task {
            defer { installing = false; container.pipeline.isProcessingMedia = false }
            do {
                if !speechInstalled {
                    if config.kind == .apple { try await AppleSpeechTranscriber(locale: config.effectiveAppleLocale).prepare() }
                    else { try await ModelDownloader.shared.download(config) { value in Task { @MainActor in progress = value.fraction } } }
                }
                try Task.checkCancellation()
                if configuration.identifySpeakers && !LocalSpeakerDiarizer.isInstalled {
                    progress = nil
                    try await ModelDownloader.shared.downloadSpeakerModel { value in Task { @MainActor in progress = value.fraction } }
                }
                await checkModels()
            } catch {
                issue = error is CancellationError ? "Download paused. Retry to finish." : error.localizedDescription
                // A cancelled download must not cancel its readiness refresh or strand the sheet.
                await Task { await checkModels() }.value
            }
        }
    }
}
