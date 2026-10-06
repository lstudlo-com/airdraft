import AirdraftCore
import SwiftUI

struct MediaImportSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let source: URL?
    var recording: RecordingAsset? = nil
    @State private var configuration = MediaConfiguration()
    @State private var installing = false
    @State private var installTask: Task<Void, Never>?
    @State private var progress: Double?
    @State private var issue: String?
    @State private var speakerInstalled = LocalSpeakerDiarizer.isInstalled

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            Text("Import Media").font(.system(size: 18, weight: .semibold))
            Text(source?.lastPathComponent ?? recording.map { "Recording · " + $0.createdAt.formatted(date: .abbreviated, time: .shortened) } ?? "No file selected").font(.system(size: 13)).lineLimit(2)
            SettingsCard {
                SettingRow(title: "Transcription") {
                    SoftPicker("Transcription", selection: $configuration.engine, width: 180) {
                        Text("On This Mac").tag(MediaConfiguration.Engine.local)
                        Text("Soniox · Cloud").tag(MediaConfiguration.Engine.soniox)
                    }
                }
                RowDivider()
                SettingRow(title: "Language") {
                    SoftPicker("Language", selection: $configuration.language, width: 180) {
                        Text("Detect Automatically").tag("")
                        ForEach(SpeechLanguagePolicy.capabilities(for: configuration.asr).supportedLanguages ?? ["en", "zh", "yue"], id: \.self) { code in
                            Text(SpeechLanguagePolicy.languageName(code)).tag(code)
                        }
                    }
                }
                RowDivider()
                SettingRow(title: "Identify speakers") {
                    Toggle("Identify Speakers", isOn: $configuration.identifySpeakers)
                        .labelsHidden().toggleStyle(.softSwitch)
                }
                if configuration.engine == .local {
                    Text("Whisper Large v3 Turbo · On-device transcription").supportingText()
                    if !LocalModels.isInstalled(configuration.asr) {
                        HStack {
                            Text("Install this Whisper model in Models first.").supportingText()
                            Spacer()
                            Button("Open Models") { container.navigation.page = .models; dismiss() }.buttonStyle(SoftButtonStyle())
                        }
                    }
                    if configuration.identifySpeakers && !speakerInstalled {
                        RowDivider()
                        HStack {
                            Text("Speaker model required").supportingText()
                            Spacer()
                            if installing { ProgressView(value: progress).frame(width: 70) }
                            Button(installing ? "Cancel" : "Download") {
                                if installing { installTask?.cancel() } else { installSpeakerModel() }
                            }.buttonStyle(SoftButtonStyle())
                        }
                    }
                }
            }
            Text(configuration.engine == .local
                 ? "Audio stays on this Mac. A managed WAV copy is kept until you delete it."
                 : "Audio is uploaded to Soniox using your API key. Provider charges apply. A local WAV copy is kept until you delete it.")
                .supportingText().fixedSize(horizontal: false, vertical: true)
            Text("Up to two hours. Results appear in History; nothing is inserted into other apps.").supportingText()
            if let issue { Text(issue).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(SoftButtonStyle()).disabled(installing)
                Button(configuration.engine == .soniox ? "Upload and Transcribe" : "Transcribe") {
                    guard !container.pipeline.isBusy else { return }
                    if let recording { container.media?.transcribeRecording(recording, configuration: configuration) }
                    else if let source { container.media?.importFile(source, configuration: configuration) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled((source == nil && recording == nil) || container.pipeline.isBusy || installing || (configuration.engine == .local && (!LocalModels.isInstalled(configuration.asr) || (configuration.identifySpeakers && !speakerInstalled))))
            }
        }
        .padding(Theme.pagePadding).frame(width: 480).background(Theme.islandBackground)
        .interactiveDismissDisabled(installing)
        .onAppear {
            configuration.language = (try? SpeechLanguagePolicy.canonicalLanguage(container.settings.asr.language)) ?? ""
        }
    }
    private func installSpeakerModel() {
        guard !container.pipeline.isBusy else { return }
        installing = true; issue = nil; container.pipeline.isProcessingMedia = true
        installTask = Task {
            defer { installing = false; container.pipeline.isProcessingMedia = false }
            do {
                try await ModelDownloader.shared.downloadSpeakerModel { value in Task { @MainActor in progress = value.fraction } }
                speakerInstalled = LocalSpeakerDiarizer.isInstalled
            } catch { issue = error is CancellationError ? "Download paused. Retry to finish." : error.localizedDescription }
        }
    }
}
