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
            if let media = container.media, media.isBusy { MeetingJobStatus(media: media) }
            if let message = issue ?? container.media?.issue {
                InlineNotice(message) {
                    Button("Dismiss") { issue = nil; container.media?.clearIssue() }
                }
            }
            PageSection("Recordings") {
                SearchField(text: $query, placeholder: "Search recordings")
            } content: {
                if entries.isEmpty {
                    Card {
                        if loading { ProgressView("Loading Recordings…").controlSize(.small) }
                        else {
                            EmptyNote(query.isEmpty ? "Record audio or import a file. Recordings and transcripts stay on this Mac." : "No recordings match “\(query)”.")
                        }
                    }
                }
                LazyVStack(spacing: Theme.controlSpacing) {
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
                        .frame(maxWidth: .infinity)
                }
            }
        } accessory: {
            Button("Import…", action: chooseMedia).buttonStyle(SoftButtonStyle())
                .disabled(container.pipeline.isBusy || container.media == nil)
                .help("Transcribe an audio or video file")
                .accessibilityIdentifier("meetings.import")
            Button("Record Audio") { container.meeting?.isPresented = true }
                .primaryButtonStyle().disabled(container.pipeline.isBusy || container.meeting == nil)
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
            InlineNotice(message) {
                Button("Retry") { meeting.issue = nil; meeting.refreshDrafts() }
            }
        }
        if !meeting.drafts.isEmpty {
            PageSection("Interrupted recordings") {
                SettingsCard {
                    ForEach(meeting.drafts) { draft in
                        if draft.id != meeting.drafts.first?.id { RowDivider() }
                        SettingRow(title: .verbatim(draft.createdAt.formatted(date: .abbreviated, time: .shortened))) {
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
        } catch { if token == loadID { issue = String(localized: "Recordings could not be loaded.") + " " + error.localizedDescription } }
    }
}

/// The import or transcription in progress, with its own pause or cancel action.
private struct MeetingJobStatus: View {
    let media: MediaJobRunner
    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            HStack(spacing: Theme.controlSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.document?.title ?? "Preparing Recording…").appFont(.body, weight: .semibold).lineLimit(1)
                    Text(media.activity).supportingText().lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(media.document == nil || media.isSummarizing ? "Cancel" : "Pause") { media.cancel() }
                    .buttonStyle(SoftButtonStyle())
            }
            ProgressView(value: media.progress).controlSize(.small)
        }.accessibilityIdentifier("meetings.active-job")
    }
}

/// One recording: what it is, where its transcript stands, and its audio.
/// The primary next step sits beside the player; everything else is in the actions menu.
private struct MeetingLibraryCard: View {
    @Environment(AppContainer.self) private var container
    let entry: MeetingLibraryEntry
    let playback: RecordingPlayback
    let transcribe: (RecordingAsset) -> Void
    let open: (TranscriptDocument) -> Void
    let report: (String) -> Void
    @State private var exporting = false
    @State private var confirmDelete = false

    private var document: TranscriptDocument? { entry.documents.first }
    private var busy: Bool { container.pipeline.isBusy }
    private var playableAsset: RecordingAsset? { entry.audioAvailable ? entry.asset : nil }
    private var processing: Bool {
        guard let document, let media = container.media else { return false }
        return media.isBusy && media.document?.id == document.id
    }
    private var resumable: Bool {
        guard let document else { return false }
        return document.stage != .completed && !processing && document.recordingID != nil && playableAsset != nil
    }

    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            header
            if let document { transcript(document) }
            if let issue = entry.asset?.captureIssue {
                DisclosureGroup("Recording Details") { Text(issue).supportingText().textSelection(.enabled) }.settingsDisclosure()
            }
            RowDivider()
            footer
        }
        .accessibilityElement(children: .contain)
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

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.controlSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).appFont(.body, weight: .semibold).lineLimit(1)
                Text(metadata).supportingText().lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                StatusDot(status.tone)
                Text(status.text).supportingText().lineLimit(1)
            }
            .frame(height: SoftControl.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.text)
            .accessibilityAddTraits(.isStaticText)
            actions
        }
    }

    private var metadata: String {
        var parts = [entry.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if let asset = entry.asset { parts.append(HistoryRecordingControls.time(asset.duration)) }
        if let document { parts.append(document.configuration.engine == .local ? String(localized: "On This Mac") : "Soniox") }
        if entry.documents.count > 1 { parts.append(String(localized: "\(entry.documents.count) transcripts")) }
        return parts.joined(separator: " · ")
    }

    private var status: (text: String, tone: StatusDot.Tone) {
        if processing { return (container.media?.activity ?? String(localized: "Processing"), .busy) }
        if let document {
            return document.stage == .completed ? (String(localized: "Transcribed"), .ok) : (String(localized: "Paused"), .attention)
        }
        return entry.audioAvailable ? (String(localized: "Not transcribed"), .inactive) : (String(localized: "Audio unavailable"), .attention)
    }

    @ViewBuilder private func transcript(_ document: TranscriptDocument) -> some View {
        if !document.text.isEmpty {
            Text(String(document.text.prefix(400)))
                .appFont(.body).mutedForeground(0.85)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                .naturalAlignment(for: document.text)
        } else if document.transcriptionComplete {
            Text("No speech detected.").supportingText()
        }
        if let issue = document.issue, !processing { Text(issue).supportingText().lineLimit(2).textSelection(.enabled) }
    }

    /// The player and the single next step for this recording.
    private var footer: some View {
        HStack(spacing: 10) {
            if let asset = playableAsset {
                MeetingPlaybackRow(asset: asset, playback: playback, busy: busy, play: { play(asset) })
            } else {
                Text(entry.asset == nil ? "Transcript kept · Audio deleted" : "Audio file unavailable").supportingText()
                Spacer(minLength: 0)
            }
            primaryAction.fixedSize()
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if let document {
            if resumable {
                Button("Resume") { container.media?.resume(id: document.id) }
                    .buttonStyle(SoftButtonStyle()).disabled(busy)
            } else {
                Button("Open Transcript") { open(document) }.buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("meeting.open.\(document.id)")
            }
        } else if let asset = playableAsset {
            Button("Transcribe…") { transcribe(asset) }
                .buttonStyle(SoftButtonStyle()).disabled(busy)
                .accessibilityIdentifier("meeting.transcribe.\(asset.id)")
        }
    }

    private var actions: some View {
        SoftMenuButton(title: "Recording Actions") {
            if let document, resumable {
                Button("Open Transcript") { open(document) }
                if document.configuration.identifySpeakers && document.configuration.engine == .local {
                    Button("Resume Without Speakers") { container.media?.resume(id: document.id, withoutSpeakers: true) }.disabled(busy)
                }
                if document.transcriptionComplete && document.remoteFileID == nil {
                    Button("Keep Transcript as Is") {
                        do { try container.media?.keepTranscript(id: document.id) } catch { report(error.localizedDescription) }
                    }.disabled(busy)
                }
                Divider()
            }
            if let asset = playableAsset, document != nil {
                Button("New Transcription…") { transcribe(asset) }.disabled(busy)
                    .accessibilityIdentifier("meeting.transcribe.\(asset.id)")
            }
            if entry.documents.count > 1 {
                Menu("Transcript Versions") {
                    ForEach(Array(entry.documents.enumerated()), id: \.element.id) { index, version in
                        Button("\(entry.documents.count - index) · \(version.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(version.configuration.engine == .local ? version.configuration.selectedModelTitle : "Soniox")") { open(version) }
                    }
                }
            }
            if let asset = playableAsset {
                if document != nil || entry.documents.count > 1 { Divider() }
                Button(exporting ? "Saving Audio…" : "Save Audio…") { save(asset) }.disabled(exporting)
                    .accessibilityIdentifier("recording.save.\(asset.id)")
                Button("Show in Finder") { reveal(asset) }
                    .accessibilityIdentifier("meeting.reveal.\(asset.id)")
            }
            if entry.asset != nil {
                Divider()
                Button("Delete Recording…", role: .destructive) { confirmDelete = true }.disabled(busy)
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 14)
        }
        .help("Recording actions")
    }
    private func reveal(_ asset: RecordingAsset) {
        guard let url = container.history?.audioURL(for: asset) else { report(String(localized: "This audio file is no longer available.")); return }
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

/// Play/pause, position and time. Only the playing card observes the playback clock.
private struct MeetingPlaybackRow: View {
    let asset: RecordingAsset
    let playback: RecordingPlayback
    let busy: Bool
    let play: () -> Void

    var body: some View {
        let active = playback.recordingID == asset.id
        let playing = active && playback.isPlaying
        // Media transport: play, position and time run left to right in every language.
        HStack(spacing: 10) {
            Button(action: play) {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 11)).frame(width: SoftControl.height, height: SoftControl.height)
            }
            .buttonStyle(SoftIconButtonStyle())
            .help(playing ? "Pause recording" : "Play recording")
            .accessibilityLabel(playing ? "Pause Recording" : "Play Recording")
            .accessibilityIdentifier("recording.play.\(asset.id)")
            .disabled(busy)
            if active {
                HistoryPlaybackProgress(playback: playback)
            } else {
                SoftSlider(title: "Playback position", value: .constant(0), range: 0...max(0.01, asset.duration), step: 0.1,
                           valueDescription: { HistoryRecordingControls.position($0, of: asset.duration) }, timeline: true)
                    .disabled(true)
                    .help("Play the recording to seek")
                Text(verbatim: WritingDirection.leftToRight(String(localized: "0:00 / \(HistoryRecordingControls.time(asset.duration))")))
                    .appFont(.caption2).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}
