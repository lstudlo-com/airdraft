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
                Text(document.title).appFont(.body, weight: .medium).lineLimit(1)
                Spacer()
                MediaDocumentStatus(document: document)
            }
            if !preview.isEmpty { Text(String(preview.prefix(500))).appFont(.body).lineLimit(4) }
            else if document.transcriptionComplete { Text("No speech detected.").supportingText() }
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
             ? container.media?.activity ?? String(localized: "Processing")
             : document.stage == .completed ? String(localized: "Completed") : String(localized: "Ready to Resume")).supportingText()
    }
}
struct MediaDocumentActions: View {
    @Environment(AppContainer.self) private var container
    let document: TranscriptDocument
    let open: () -> Void
    var showsOpen = true
    @State private var actionIssue: String?
    private var active: Bool { container.media?.isBusy == true && container.media?.document?.id == document.id }
    var body: some View {
        if active {
            HStack {
                ProgressView(value: container.media?.progress).controlSize(.small)
                Button(container.media?.isSummarizing == true ? "Cancel" : "Pause") { container.media?.cancel() }.buttonStyle(SoftButtonStyle())
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
            if document.stage != .completed && !active && document.recordingID != nil && document.configuration.identifySpeakers && document.configuration.engine == .local {
                Button("Without Speakers") { container.media?.resume(id: document.id, withoutSpeakers: true) }
                    .buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
                    .help("Continue transcription without speaker detection")
            }
            if document.transcriptionComplete && document.stage != .completed && !active && document.remoteFileID == nil {
                Button("Keep Transcript") {
                    do { try container.media?.keepTranscript(id: document.id) }
                    catch { actionIssue = error.localizedDescription }
                }.buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
            }
            if showsOpen { Button("Open Transcript", action: open).buttonStyle(SoftButtonStyle()) }
        }
    }
}

struct MediaDocumentEditor: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var document: TranscriptDocument
    @State private var playback = makeHistoryPlayback()
    @State private var audioURL: URL?
    @State private var duration: Double?
    @State private var page = 0
    @State private var dirty = false
    @State private var issue: String?
    @State private var confirmDelete = false
    @State private var showOriginal = false
    @State private var confirmClose = false
    @State private var confirmSummary = false
    @FocusState private var titleFocused: Bool
    init(initial: TranscriptDocument) { _document = State(initialValue: initial) }
    private static let pageSize = 100
    private var speakerIDs: [String] { Array(Set(document.turns.compactMap(\.speaker) + Array(document.speakerNames.keys))).sorted() }
    private var editable: Bool { !container.pipeline.isBusy && document.stage == .completed }
    private var processing: Bool { container.media?.document?.id == document.id && container.media?.isBusy == true }
    private var pageCount: Int { (document.turns.count + Self.pageSize - 1) / Self.pageSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding([.top, .horizontal], Theme.pagePadding)
                .padding(.bottom, Theme.controlSpacing)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if let issue {
                        InlineNotice(issue) { Button("Dismiss") { self.issue = nil } }
                    }
                    if document.stage != .completed || processing {
                        Card(spacing: Theme.controlSpacing) { MediaDocumentActions(document: document, open: {}, showsOpen: false) }
                    }
                    if let summary = document.summary {
                        PageSection("Summary") {
                            Card { Text(summary).appFont(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }
                    if document.transcriptionComplete { speakers }
                    transcript
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, Theme.cardPadding)
            }
            footer
                .padding([.bottom, .horizontal], Theme.pagePadding)
                .padding(.top, Theme.controlSpacing)
        }
        .frame(width: 680, height: 580).background(Theme.islandBackground)
        .interactiveDismissDisabled(dirty)
        .onChange(of: document.title) { _, _ in dirty = true }
        .onChange(of: container.pipeline.isBusy) { _, busy in if busy { playback.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: .historyEntriesChanged)) { _ in
            guard !dirty, let saved = try? container.history?.document(id: document.id) else { return }
            document = saved
        }
        .onAppear {
            NotificationCenter.default.post(name: .mediaEditorOpened, object: nil)
            if let saved = try? container.history?.document(id: document.id) { document = saved }
            if let id = document.recordingID, let asset = try? container.history?.recording(id: id) {
                audioURL = container.history?.audioURL(for: asset); duration = asset.duration
            }
        }
        // A sheet otherwise opens with the title as first responder and a blinking caret.
        .task { titleFocused = false }
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
        } message: { Text("The recording stays in Meetings.") }
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
    private var metadata: String {
        var parts = [document.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let duration { parts.append(HistoryRecordingControls.time(duration)) }
        parts.append(document.configuration.engine == .local ? document.configuration.selectedModelTitle : "Soniox")
        if document.configuration.usesSegmentTiming { parts.append(String(localized: "Segment timestamps")) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Title", text: $document.title)
                        .appFont(.title).textFieldStyle(.plain)
                        .focused($titleFocused).onSubmit { titleFocused = false }
                        .disabled(!editable).help("Rename transcript")
                        .accessibilityLabel("Transcript title")
                    Text(metadata).supportingText().lineLimit(1)
                }
                Button("Close") { if dirty { confirmClose = true } else { dismiss() } }
                    .buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                if audioURL != nil, document.recordingID != nil {
                    Button { togglePlayback() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11)).frame(width: SoftControl.height, height: SoftControl.height)
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help(playback.isPlaying ? "Pause recording" : "Play recording")
                    .accessibilityLabel(playback.isPlaying ? "Pause Recording" : "Play Recording")
                    if playback.recordingID != nil { MediaEditorClock(playback: playback) }
                }
                SoftSegmentedPicker("Transcript version", selection: $showOriginal, options: [(false, String(localized: "Edited")), (true, String(localized: "Original"))])
                Spacer(minLength: 0)
                Button("Copy") { copy() }.buttonStyle(SoftButtonStyle())
                SoftMenuButton(title: "Export") {
                    ForEach(TranscriptExport.Format.allCases, id: \.self) { format in Button(format.rawValue.uppercased() + "…") { export(format) } }
                } label: {
                    Text("Export  \(Image(systemName: "chevron.down"))")
                }
            }
        }
    }

    private var speakers: some View {
        PageSection("Speakers") {
            Button("Add Speaker") {
                let id = String((speakerIDs.compactMap(Int.init).max() ?? 0) + 1)
                document.speakerNames[id] = String(localized: "Speaker \(id)"); dirty = true
            }.buttonStyle(SoftButtonStyle()).disabled(!editable)
        } content: {
            if !speakerIDs.isEmpty {
                SettingsCard {
                    ForEach(speakerIDs, id: \.self) { id in
                        if id != speakerIDs.first { RowDivider() }
                        SettingRow(title: "Speaker \(id)") {
                            TextField("Name", text: Binding(get: { document.speakerNames[id] ?? "" }, set: { document.speakerNames[id] = $0; dirty = true }))
                                .softField().frame(width: Theme.fieldWidth).disabled(!editable)
                                .accessibilityLabel("Speaker \(id) name")
                        }
                    }
                }
            }
            Text("Speaker labels are estimates. Assign each passage below to correct them.")
                .supportingText().padding(.leading, Theme.sectionTitleLeadingInset)
        }
    }

    private var transcript: some View {
        PageSection("Transcript") {
            if pageCount > 1 {
                HStack(spacing: 8) {
                    Text("Page \(page + 1) of \(pageCount)").supportingText().monospacedDigit()
                    Button { page -= 1 } label: { Image(systemName: "chevron.left").frame(width: 12) }
                        .disabled(page == 0).accessibilityLabel("Previous Page")
                    Button { page += 1 } label: { Image(systemName: "chevron.right").frame(width: 12) }
                        .disabled(page + 1 >= pageCount).accessibilityLabel("Next Page")
                }.buttonStyle(SoftButtonStyle())
            }
        } content: {
            if document.turns.isEmpty {
                Card { EmptyNote(document.transcriptionComplete ? "No speech was detected." : "Transcription has not finished yet.") }
            } else {
                Card(spacing: Theme.controlSpacing) {
                    let indices = Array(document.turns.indices.dropFirst(page * Self.pageSize).prefix(Self.pageSize))
                    ForEach(indices, id: \.self) { index in
                        if index != indices.first { RowDivider() }
                        turn(index)
                    }
                }
            }
        }
    }

    private func turn(_ index: Int) -> some View {
        let turn = document.turns[index]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if showOriginal {
                    Text(document.speakerName(turn.originalSpeaker)).appFont(.detail, weight: .semibold)
                } else {
                    Menu {
                        Button("Unknown Speaker") { document.turns[index].speaker = nil; dirty = true }
                        ForEach(speakerIDs, id: \.self) { id in
                            Button(document.speakerName(id)) { document.turns[index].speaker = id; dirty = true }
                        }
                    } label: {
                        Text("\(document.speakerName(turn.speaker)) \(Image(systemName: "chevron.down"))")
                            .appFont(.detail, weight: .semibold).contentShape(Rectangle())
                            .accessibilityLabel(Text(verbatim: document.speakerName(turn.speaker)))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().disabled(!editable)
                    .help("Assign speaker")
                }
                Button(HistoryRecordingControls.time(turn.start)) { seek(turn.start) }
                    .buttonStyle(.plain).appFont(.supporting).monospacedDigit().foregroundStyle(.secondary)
                    .disabled(audioURL == nil || !editable)
                    .help("Play from this timestamp")
                Spacer(minLength: 0)
                if turn.overlapping { Text("Overlapping speech").supportingText() }
            }
            if showOriginal {
                Text(turn.originalText).appFont(.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Transcript", text: Binding(get: { document.turns[index].text }, set: { document.turns[index].editedText = $0; dirty = true }), axis: .vertical)
                    .appFont(.body).textFieldStyle(.plain).disabled(!editable)
                    .accessibilityLabel(Text("Transcript at \(HistoryRecordingControls.time(turn.start))"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.controlSpacing) {
            Button("Delete Transcript…", role: .destructive) { confirmDelete = true }
                .buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
            Spacer(minLength: 0)
            if dirty { Text("Unsaved changes").supportingText() }
            if container.settings.llm.kind != .none {
                Button("Summarize…") { confirmSummary = true }.buttonStyle(SoftButtonStyle()).disabled(!editable || dirty)
                    .help(dirty ? "Save changes before summarizing" : "Create a summary with your refinement provider")
            }
            Button("Save Changes") { save() }.primaryButtonStyle().disabled(!dirty || !editable)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    private func togglePlayback() {
        guard let audioURL, let id = document.recordingID else { return }
        do { try playback.toggle(id: id, url: audioURL) } catch { issue = error.localizedDescription }
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

/// Only the clock observes playback time, so editing rows do not refresh while audio plays.
private struct MediaEditorClock: View {
    let playback: RecordingPlayback
    var body: some View {
        Text("\(HistoryRecordingControls.time(playback.currentTime)) / \(HistoryRecordingControls.time(playback.duration))")
            .appFont(.supporting).monospacedDigit().foregroundStyle(.secondary).fixedSize()
    }
}
