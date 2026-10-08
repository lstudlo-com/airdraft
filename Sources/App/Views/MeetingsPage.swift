import AirdraftCore
import SwiftUI
import UniformTypeIdentifiers

/// Meetings and imported media share a durable library; dictation remains in History.
struct MeetingsPage: View {
    @Environment(AppContainer.self) private var container
    @State private var entries: [MeetingLibraryEntry] = []
    @State private var query = ""
    @State private var loading = false
    @State private var hasMore = false
    @State private var issue: String?
    @State private var loadID = UUID()
    @State private var presentation: Presentation?
    @State private var playback = makeHistoryPlayback()
    private let pageSize = 100

    enum Presentation: Identifiable {
        case transcription(MediaImportRequest), document(TranscriptDocument)
        var id: String {
            switch self {
            case .transcription(let request): return request.id.uuidString
            case .document(let document): return document.id
            }
        }
    }
    var body: some View {
        PageScaffold(.meetings) {
            if let meeting = container.meeting {
                if meeting.isBusy { MeetingRecordingStatus(meeting: meeting) }
                recovery(meeting)
            }
            if let media = container.media, media.isBusy {
                Card(spacing: Theme.controlSpacing) {
                    Text(media.document?.title ?? "Preparing Recording…").font(.system(size: 13, weight: .medium)).lineLimit(1)
                    HStack {
                        ProgressView(value: media.progress).controlSize(.small)
                        Text(media.activity).supportingText()
                        Spacer()
                        Button(media.document == nil ? "Cancel" : "Pause") { media.cancel() }.buttonStyle(SoftButtonStyle())
                    }
                }.accessibilityIdentifier("meetings.active-job")
            }
            if let message = issue ?? container.media?.issue {
                HStack(alignment: .top) {
                    Text(message).supportingText().textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { issue = nil; container.media?.clearIssue() }.buttonStyle(SoftButtonStyle())
                }
            }
            VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                HStack {
                    SectionTitle("Recordings")
                    Spacer()
                    SearchField(text: $query, placeholder: "Search meetings")
                }
                if entries.isEmpty {
                    if loading { ProgressView("Loading Recordings…").controlSize(.small) }
                    else {
                        EmptyNote(query.isEmpty ? "Record a meeting or import audio. Recordings and transcripts stay here." : "No matches.")
                    }
                }
                LazyVStack(spacing: Theme.sectionTitleSpacing) {
                    ForEach(entries) { entry in
                        MeetingLibraryCard(entry: entry, playback: playback,
                            transcribe: { asset in playback.stop(); presentation = .transcription(.recording(asset)) },
                            open: { document in playback.stop(); presentation = .document(document) },
                            report: { issue = $0 })
                    }
                }
                if hasMore {
                    Button(loading ? "Loading…" : "Load More") { Task { await reload(append: true) } }
                        .buttonStyle(SoftButtonStyle()).disabled(loading)
                }
            }
        } accessory: {
            Button("Import…", action: chooseMedia).buttonStyle(SoftButtonStyle())
                .disabled(container.pipeline.isBusy || container.media == nil)
                .accessibilityIdentifier("meetings.import")
            Button("Record Meeting") { container.meeting?.isPresented = true }
                .buttonStyle(SoftButtonStyle(prominent: true)).disabled(container.pipeline.isBusy || container.meeting == nil)
                .accessibilityIdentifier("meetings.record")
        }
        .task(id: query) {
            loadID = UUID()
            playback.stop()
            if !query.isEmpty { do { try await Task.sleep(for: .milliseconds(200)) } catch { return } }
            await reload()
        }
        .sheet(item: $presentation) { item in
            switch item {
            case .transcription(let request): MediaImportSheet(request: request).environment(container)
            case .document(let document): MediaDocumentEditor(initial: document).environment(container)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard !container.pipeline.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    guard !container.pipeline.isBusy, presentation == nil, let url else { return }
                    presentation = .transcription(.file(url))
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyEntriesChanged)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            container.meeting?.refreshDrafts(); Task { await reload() }
        }
        .onChange(of: container.meeting?.saved?.id) { _, saved in
            if saved != nil { query = ""; Task { await reload() } }
        }
        .onChange(of: container.pipeline.audioRevision) { _, _ in playback.stop(); Task { await reload() } }
        .onChange(of: container.pipeline.isBusy) { _, busy in if busy { playback.stop() } }
        .onDisappear { playback.stop() }
    }

    @ViewBuilder private func recovery(_ meeting: MeetingController) -> some View {
        if let message = meeting.issue ?? meeting.recoveryIssue {
            HStack(alignment: .top) {
                Text(message).supportingText().textSelection(.enabled)
                Spacer()
                Button("Retry") { meeting.issue = nil; meeting.refreshDrafts() }.buttonStyle(SoftButtonStyle())
            }
        }
        if !meeting.drafts.isEmpty {
            PageSection("Interrupted recordings") {
                SettingsCard {
                    ForEach(meeting.drafts) { draft in
                        if draft.id != meeting.drafts.first?.id { RowDivider() }
                        HStack {
                            Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13))
                            Spacer()
                            Button("Recover Recording") { meeting.recover(draft) }.buttonStyle(SoftButtonStyle())
                                .disabled(container.pipeline.isBusy)
                        }
                    }
                }
            }
        }
    }
    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, !container.pipeline.isBusy, let url = panel.url else { return }
            presentation = .transcription(.file(url))
        }
    }
    private func reload(append: Bool = false) async {
        guard let history = container.history else { return }
        let token = UUID(); loadID = token; loading = true
        defer { if loadID == token { loading = false } }
        let offset = append ? entries.count : 0
        let query = query, count = pageSize + 1
        do {
            let found: [MeetingLibraryEntry]
            if RenderMode.isActive { found = try history.meetings(limit: count, offset: offset, query: query) }
            else { found = try await Task.detached { try history.meetings(limit: count, offset: offset, query: query) }.value }
            guard !Task.isCancelled, token == loadID else { return }
            entries = (append ? entries : []) + Array(found.prefix(pageSize))
            hasMore = found.count > pageSize
            if let id = playback.recordingID, !entries.contains(where: { $0.asset?.id == id }) { playback.stop() }
        } catch { if token == loadID { issue = "Recordings could not be loaded. " + error.localizedDescription } }
    }
}

private struct MeetingLibraryCard: View {
    @Environment(AppContainer.self) private var container
    let entry: MeetingLibraryEntry
    let playback: RecordingPlayback
    let transcribe: (RecordingAsset) -> Void
    let open: (TranscriptDocument) -> Void
    let report: (String) -> Void
    @State private var exporting = false
    @State private var confirmDelete = false

    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).supportingText()
                }
                Spacer()
                if let asset = entry.asset { Text(HistoryRecordingControls.time(asset.duration)).supportingText().monospacedDigit() }
            }
            if let document = entry.documents.first {
                MediaDocumentStatus(document: document)
                if !document.text.isEmpty { Text(String(document.text.prefix(500))).font(.system(size: 13)).lineLimit(3) }
                MediaDocumentActions(document: document) { open(document) }
            } else { Text(entry.audioAvailable ? "Ready to transcribe" : "Audio file unavailable").supportingText() }
            if entry.documents.count > 1 {
                Menu("Transcript Versions (\(entry.documents.count))") {
                    ForEach(Array(entry.documents.enumerated()), id: \.element.id) { index, document in
                        Button("\(entry.documents.count - index) · \(document.createdAt.formatted(date: .abbreviated, time: .standard)) · \(document.configuration.engine == .local ? document.configuration.selectedLocalModel.title : "Soniox")") { open(document) }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if let asset = entry.asset, entry.audioAvailable {
                HStack {
                    Button(entry.documents.isEmpty ? "Transcribe…" : "New Transcription…") { transcribe(asset) }
                        .buttonStyle(SoftButtonStyle()).disabled(container.pipeline.isBusy)
                        .accessibilityIdentifier("meeting.transcribe.\(asset.id)")
                    Spacer()
                    Button("Show in Finder") { reveal(asset) }.buttonStyle(SoftButtonStyle())
                        .accessibilityIdentifier("meeting.reveal.\(asset.id)")
                }
                RowDivider()
                HistoryRecordingControls(asset: asset, playback: playback, busy: container.pipeline.isBusy,
                    exporting: exporting, play: { play(asset) }, save: { save(asset) }, reveal: { reveal(asset) }, retranscribe: nil,
                    delete: container.pipeline.isBusy ? nil : { confirmDelete = true })
            } else if !entry.documents.isEmpty { Text("Transcript retained · Audio unavailable").supportingText() }
        }
        .accessibilityIdentifier("meeting.entry.\(entry.id)")
        .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Recording", role: .destructive) {
                guard !container.pipeline.isBusy, let asset = entry.asset, let history = container.history else { return }
                playback.stop()
                Task {
                    do {
                        try await Task.detached { try history.deleteRecording(id: asset.id) }.value
                        NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
                    } catch { report(error.localizedDescription) }
                }
            }
        } message: { Text("All transcript versions are kept. Deleting the audio cannot be undone.") }
    }
    private func reveal(_ asset: RecordingAsset) {
        guard let url = container.history?.audioURL(for: asset) else { report("This audio file is no longer available."); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func play(_ asset: RecordingAsset) {
        guard !container.pipeline.isBusy, let url = container.history?.audioURL(for: asset) else { return }
        do { try playback.toggle(id: asset.id, url: url) } catch { report(error.localizedDescription) }
    }
    private func save(_ asset: RecordingAsset) {
        guard !exporting, let history = container.history else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "Airdraft_\(asset.createdAt.formatted(.iso8601.year().month().day()))_\(asset.id.prefix(8)).wav"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            exporting = true
            Task {
                defer { exporting = false }
                do { try await Task.detached { try history.exportRecording(id: asset.id, to: destination, replacing: true) }.value }
                catch { report(error.localizedDescription) }
            }
        }
    }
}
