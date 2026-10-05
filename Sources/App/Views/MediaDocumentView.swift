import AirdraftCore
import SwiftUI
import UniformTypeIdentifiers

struct MediaDocumentCard<RecordingControls: View>: View {
    @Environment(AppContainer.self) private var container
    let document: TranscriptDocument
    let preview: String
    let recordingControls: RecordingControls
    let open: () -> Void
    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            HStack {
                Text(document.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                MediaDocumentStatus(document: document)
            }
            if !preview.isEmpty { Text(String(preview.prefix(500))).font(.system(size: 13)).lineLimit(4) }
            MediaDocumentActions(document: document, open: open)
            recordingControls
        }
    }
}

/// Shared by the visual card and History's lightweight accessibility representation.
struct MediaDocumentStatus: View {
    @Environment(AppContainer.self) private var container
    let document: TranscriptDocument
    var body: some View {
        Text(container.media?.isBusy == true && container.media?.document?.id == document.id
             ? container.media?.activity ?? "Processing"
             : document.stage == .completed ? "Completed" : "Ready to Resume").supportingText()
    }
}
struct MediaDocumentActions: View {
    @Environment(AppContainer.self) private var container
    let document: TranscriptDocument
    let open: () -> Void
    @State private var actionIssue: String?
    private var active: Bool { container.media?.isBusy == true && container.media?.document?.id == document.id }
    var body: some View {
        if active {
            HStack {
                ProgressView(value: container.media?.progress).controlSize(.small)
                Button(container.media?.activity == "Summarizing" ? "Cancel" : "Pause") { container.media?.cancel() }.buttonStyle(SoftButtonStyle())
            }
        }
        if let actionIssue { Text(actionIssue).supportingText().textSelection(.enabled) }
        if let issue = document.issue { Text(issue).supportingText().lineLimit(3) }
        HStack {
            Text(document.configuration.engine == .local ? "On This Mac" : "Soniox").supportingText()
            Spacer()
            if document.stage != .completed && !active && document.recordingID != nil {
                Button("Resume") { container.media?.resume(id: document.id) }
                    .buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
            }
            if document.transcriptionComplete && document.stage != .completed && !active && document.remoteFileID == nil {
                Button("Keep Transcript") {
                    do { try container.media?.keepTranscript(id: document.id) }
                    catch { actionIssue = error.localizedDescription }
                }.buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
            }
            Button("Open Transcript", action: open).buttonStyle(SoftButtonStyle())
        }
    }
}

struct MediaDocumentEditor: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var document: TranscriptDocument
    @State private var playback = makeHistoryPlayback()
    @State private var audioURL: URL?
    @State private var page = 0
    @State private var dirty = false
    @State private var issue: String?
    @State private var confirmDelete = false
    @State private var showOriginal = false
    @State private var confirmClose = false
    @State private var confirmSummary = false
    init(initial: TranscriptDocument) { _document = State(initialValue: initial) }
    private var speakerIDs: [String] { Array(Set(document.turns.compactMap(\.speaker) + Array(document.speakerNames.keys))).sorted() }
    private var editable: Bool { !container.pipeline.isBusy && document.stage == .completed }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            HStack {
                TextField("Title", text: $document.title).font(.system(size: 18, weight: .semibold)).textFieldStyle(.plain).disabled(!editable)
                Spacer()
                Button("Close") { if dirty { confirmClose = true } else { dismiss() } }
                    .buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
            }
            HStack {
                SoftSegmentedPicker("Transcript version", selection: $showOriginal, options: [(false, "Edited"), (true, "Original")])
                Spacer()
                Button("Copy") { copy() }.buttonStyle(SoftButtonStyle())
                Menu("Export") {
                    ForEach(TranscriptExport.Format.allCases, id: \.self) { format in Button(format.rawValue.uppercased() + "…") { export(format) } }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if let issue { Text(issue).supportingText().textSelection(.enabled) }
            if container.media?.isBusy == true { Text("Editing is available after processing finishes. Close and reopen to load the latest result.").supportingText() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.controlSpacing) {
                    if document.transcriptionComplete {
                        SettingsCard {
                            ForEach(speakerIDs, id: \.self) { id in
                                if id != speakerIDs.first { RowDivider() }
                                HStack {
                                    Text("Speaker \(id)").font(.system(size: 13))
                                    TextField("Name", text: Binding(get: { document.speakerNames[id] ?? "" }, set: { document.speakerNames[id] = $0; dirty = true }))
                                        .softField().disabled(!editable)
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Speaker labels are estimates; you can correct them.").supportingText()
                        Spacer()
                        Button("Add Speaker") {
                            let id = String((speakerIDs.compactMap(Int.init).max() ?? 0) + 1)
                            document.speakerNames[id] = "Speaker " + id; dirty = true
                        }.buttonStyle(SoftButtonStyle()).disabled(!editable)
                    }
                    ForEach(Array(document.turns.indices.dropFirst(page * 100).prefix(100)), id: \.self) { index in
                        Card(spacing: Theme.controlSpacing) {
                            HStack {
                                Button(HistoryRecordingControls.time(document.turns[index].start)) { seek(document.turns[index].start) }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(audioURL == nil || !editable)
                                    .help("Play from this timestamp")
                                if showOriginal {
                                    Text(document.speakerName(document.turns[index].originalSpeaker)).font(.system(size: 11))
                                } else {
                                    Menu(document.speakerName(document.turns[index].speaker)) {
                                        Button("Unknown Speaker") { document.turns[index].speaker = nil; dirty = true }
                                        ForEach(speakerIDs, id: \.self) { id in
                                            Button(document.speakerName(id)) { document.turns[index].speaker = id; dirty = true }
                                        }
                                    }.menuStyle(.borderlessButton).fixedSize().disabled(!editable)
                                }
                                Spacer()
                                if document.turns[index].overlapping { Text("Overlapping speech").supportingText() }
                            }
                            if showOriginal {
                                Text(document.turns[index].originalText).font(.system(size: 13)).textSelection(.enabled)
                            } else {
                                TextField("Transcript", text: Binding(get: { document.turns[index].text }, set: { document.turns[index].editedText = $0; dirty = true }), axis: .vertical)
                                    .font(.system(size: 13)).textFieldStyle(.plain).disabled(!editable)
                            }
                        }
                    }
                    if document.turns.isEmpty { EmptyNote(document.transcriptionComplete ? "No speech was detected." : "Transcription has not finished yet.") }
                    if document.turns.count > 100 {
                        HStack {
                            Button("Previous") { page -= 1 }.disabled(page == 0)
                            Spacer()
                            Text("Page \(page + 1) of \((document.turns.count + 99) / 100)").supportingText()
                            Spacer()
                            Button("Next") { page += 1 }.disabled((page + 1) * 100 >= document.turns.count)
                        }.buttonStyle(SoftButtonStyle())
                    }
                    if let summary = document.summary {
                        Card { Text("Summary").font(.system(size: 13, weight: .medium)); Text(summary).font(.system(size: 13)).textSelection(.enabled) }
                    }
                }.padding(Theme.cardPadding)
            }.padding(.horizontal, -Theme.cardPadding)
            HStack {
                Button("Delete Transcript…", role: .destructive) { confirmDelete = true }.buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
                if playback.recordingID != nil {
                    Button(playback.isPlaying ? "Pause" : "Play") {
                        guard let audioURL, let id = document.recordingID else { return }
                        do { try playback.toggle(id: id, url: audioURL) } catch { issue = error.localizedDescription }
                    }.buttonStyle(SoftButtonStyle())
                }
                Spacer()
                if container.settings.llm.kind != .none {
                    Button("Summarize…") { confirmSummary = true }.buttonStyle(SoftButtonStyle()).disabled(!editable || dirty)
                }
                Button("Save Changes") { save() }.buttonStyle(.borderedProminent).disabled(!dirty || !editable)
            }
        }
        .padding(Theme.pagePadding).frame(width: 650, height: 530).background(Theme.islandBackground)
        .interactiveDismissDisabled(dirty)
        .onChange(of: document.title) { _, _ in dirty = true }
        .onChange(of: container.pipeline.isBusy) { _, busy in if busy { playback.stop() } }
        .onAppear {
            NotificationCenter.default.post(name: .mediaEditorOpened, object: nil)
            if let saved = try? container.history?.document(id: document.id) { document = saved }
            if let id = document.recordingID, let asset = try? container.history?.recording(id: id) { audioURL = container.history?.audioURL(for: asset) }
        }
        .onDisappear { playback.stop() }
        .confirmationDialog("Delete this transcript?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Transcript", role: .destructive) {
                Task {
                    do {
                        guard !container.pipeline.isBusy else { throw MediaError.busy }
                        try await container.media?.cleanRemote(documentID: document.id)
                        try container.history?.deleteDocument(id: document.id)
                        NotificationCenter.default.post(name: .historyEntriesChanged, object: nil); dismiss()
                    } catch { issue = error.localizedDescription }
                }
            }
        } message: { Text("The recording stays in Recordings.") }
        .confirmationDialog("Summarize this transcript?", isPresented: $confirmSummary, titleVisibility: .visible) {
            Button("Create Summary") {
                container.media?.summarize(id: document.id, configuration: container.settings.llm)
                dismiss()
            }
        } message: { Text("Uses your selected refinement provider and may send transcript text to that service. Provider charges may apply. The original transcript is kept.") }
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
        }
    }
    private func save() {
        do {
            guard let history = container.history else { throw MediaError.unavailable }
            document = try history.updateDocument(document); dirty = false
            NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
        } catch { issue = error.localizedDescription }
    }
    private func seek(_ time: Double) {
        guard let audioURL, let id = document.recordingID else { return }
        do {
            if playback.recordingID != id || !playback.isPlaying { try playback.toggle(id: id, url: audioURL) }
            playback.seek(to: time)
        } catch { issue = error.localizedDescription }
    }
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(showOriginal ? document.originalText : document.turns.map { "\(document.speakerName($0.speaker)): \($0.text)" }.joined(separator: "\n\n"), forType: .string)
    }
    private func export(_ format: TranscriptExport.Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .plainText]
        panel.nameFieldStringValue = document.title.replacingOccurrences(of: "/", with: "-") + "." + format.rawValue
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let managed = container.dataDirectory.standardizedFileURL.resolvingSymlinksInPath().path
                let target = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard target != managed, !target.hasPrefix(managed + "/") else { throw CocoaError(.fileWriteNoPermission) }
                try TranscriptExport.data(document, format: format, original: showOriginal).write(to: url, options: .atomic)
            } catch { issue = error.localizedDescription }
        }
    }
}
extension Notification.Name { static let mediaEditorOpened = Notification.Name("Airdraft.mediaEditorOpened") }
