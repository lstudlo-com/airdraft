import AirdraftCore
import SwiftUI
import UniformTypeIdentifiers

/// Long audio: import a file or record a conversation, then read, copy or
/// share its transcript with speaker turns.
struct TranscribeView: View {
    @Environment(TranscribeController.self) private var transcribe
    @Environment(DictationController.self) private var dictation
    @State private var importing = false

    var body: some View {
        NavigationStack {
            SoftPage {
                SoftCard {
                    Text("Transcribe recordings, meetings and voice memos. Long audio is processed in parts and can resume if interrupted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let started = transcribe.recordingStartedAt {
                        HStack {
                            Label("Recording", systemImage: "record.circle")
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text(started, style: .timer).monospacedDigit()
                        }
                        .font(.headline)
                        Button("Stop and Transcribe") { transcribe.stopRecording() }
                            .buttonStyle(.softProminent)
                    } else {
                        HStack(spacing: 12) {
                            Button { importing = true } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.soft)
                            Button { transcribe.startRecording() } label: {
                                Label("Record", systemImage: "mic")
                            }
                            .buttonStyle(.soft)
                        }
                        .disabled(transcribe.runner?.isBusy == true)
                    }
                    if let runner = transcribe.runner, runner.isBusy {
                        RowDivider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text(runner.activity).font(.subheadline)
                            if let progress = runner.progress {
                                ProgressView(value: progress)
                            } else {
                                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button("Cancel") { runner.cancel() }
                                .buttonStyle(.softCompact)
                        }
                    }
                    if let issue = transcribe.issue ?? transcribe.runner?.issue {
                        Text(issue)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                TranscribeOptions()
                if !transcribe.documents.isEmpty {
                    SoftSection(title: "Transcripts") {
                        ForEach(Array(transcribe.documents.enumerated()), id: \.element.id) { index, document in
                            if index > 0 { RowDivider() }
                            NavigationLink(value: document.id) {
                                DocumentRow(document: document)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Transcribe")
            .navigationDestination(for: String.self) { id in
                TranscriptDetailView(documentID: id)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie]) { result in
                if case .success(let url) = result { transcribe.importFile(url) }
            }
            .task { await transcribe.reload() }
        }
    }
}

private struct TranscribeOptions: View {
    @Environment(TranscribeController.self) private var transcribe

    var body: some View {
        @Bindable var transcribe = transcribe
        SoftSection(title: "Options") {
            SettingPickerRow(title: "Speech model", detail: nil) {
                Picker("Speech model", selection: Binding(
                    get: { transcribe.configuration.engine == .soniox ? "soniox" : transcribe.configuration.selectedModelID },
                    set: { id in
                        if id == "soniox" {
                            transcribe.configuration.engine = .soniox
                        } else {
                            transcribe.configuration.engine = .local
                            transcribe.configuration.selectModelChoice(id)
                        }
                    })) {
                    ForEach(Self.choices, id: \.id) { choice in
                        Text(verbatim: choice.title).tag(choice.id)
                    }
                }
            }
            RowDivider()
            Toggle(isOn: $transcribe.configuration.identifySpeakers) {
                SettingLabel(title: "Identify speakers", detail: "Labels who spoke when, on this iPhone.")
            }
            .frame(minHeight: MobileTheme.touchTarget)
            .disabled(!transcribe.speakerModelInstalled)
            if !transcribe.speakerModelInstalled {
                if let progress = transcribe.speakerDownload {
                    ProgressView(value: progress)
                } else {
                    Button("Download Speaker Model") { transcribe.downloadSpeakerModel() }
                        .buttonStyle(.softCompact)
                }
            }
        }
    }

    /// Media models that suit an iPhone, plus Soniox with your own key.
    static var choices: [(id: String, title: String)] {
        var choices: [(String, String)] = [(MediaConfiguration.LocalModel.apple.rawValue, "Apple Speech")]
        for id in ["parakeet-v3-int4", "parakeet-v3", "parakeet-v2", "parakeet-ja"] {
            if let model = CoreMLSpeechModelCatalog.model(id) { choices.append(("coreml:\(id)", model.title)) }
        }
        choices.append((MediaConfiguration.LocalModel.whisperTurboCompressed.rawValue,
                        MediaConfiguration.LocalModel.whisperTurboCompressed.title))
        for id in ["sensevoice-small", "whisper-small", "whisper-base"] {
            if let model = GGUFModelCatalog.model(id) { choices.append(("gguf:\(id)", model.title)) }
        }
        choices.append(("soniox", "Soniox"))
        return choices.map { (id: $0.0, title: $0.1) }
    }
}

private struct DocumentRow: View {
    let document: TranscriptDocument

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Text(document.createdAt, format: .dateTime.month().day().hour().minute())
                    Text(verbatim: " · \(document.stage.title)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if let preview = document.turns.first?.text {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: MobileTheme.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TranscriptDetailView: View {
    let documentID: String

    @Environment(TranscribeController.self) private var transcribe
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmsDelete = false

    private var document: TranscriptDocument? {
        transcribe.documents.first { $0.id == documentID }
    }

    var body: some View {
        SoftPage {
            if let document {
                SoftCard {
                    Text(document.stage.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = plainText(document)
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.soft)
                        ShareLink(item: plainText(document)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.soft)
                    }
                    if document.stage == .paused || document.stage == .failed {
                        Button("Resume") { transcribe.runner?.resume(id: document.id) }
                            .buttonStyle(.softProminent)
                            .disabled(transcribe.runner?.isBusy == true)
                    }
                }
                if !document.turns.isEmpty {
                    SoftSection(title: "Transcript") {
                        ForEach(Array(document.turns.enumerated()), id: \.element.id) { index, turn in
                            if index > 0 { RowDivider() }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(document.speakerName(turn.speaker))
                                        .font(.footnote.weight(.semibold))
                                    Spacer()
                                    Text(Duration.seconds(turn.start), format: .time(pattern: .minuteSecond))
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(turn.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Button("Delete Transcript", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(.soft)
            }
        }
        .navigationTitle(Text(verbatim: document?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this transcript?", isPresented: $confirmsDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let document { transcribe.delete(document) }
                dismiss()
            }
        }
    }

    private func plainText(_ document: TranscriptDocument) -> String {
        (try? TranscriptExport.data(document, format: .txt)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
