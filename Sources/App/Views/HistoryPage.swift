import AirdraftCore
import SwiftUI
import Observation
import UniformTypeIdentifiers

extension Notification.Name {
    static let historyEntriesChanged = Notification.Name("Airdraft.historyEntriesChanged")
}

/// Database preparation and page actions stay independent of scroll position.
struct HistoryPage: View {
    @Environment(AppContainer.self) private var container
    @State private var playback = makeHistoryPlayback()
    @State private var showReview = false
    @State private var snapshot = HistorySnapshot.empty
    @State private var rowStates: [String: HistoryCardState] = [:]
    @State private var scroll = HistoryScrollState()
    @State private var loadID = UUID()
    @State private var loading = false
    @State private var hasMore = false
    @State private var errorMessage: String?
    private let pageSize = min(10_000, max(1, Int(RenderMode.value("HISTORY_COUNT") ?? "") ?? 200))
    @State private var query = ""
    @State private var confirmClear = false
    @State private var recordingsOnly = RenderMode.value("RECORDINGS_ONLY") == "1"
    @State private var nextOffset: Int?
    @State private var importURL: URL?
    @State private var showImport = false

    var body: some View {
        PageScaffold(.history, scrollsContent: false, contentTopInset: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SoftSegmentedPicker("History filter", selection: $recordingsOnly,
                                        options: [(false, "All"), (true, "Recordings")])
                        .accessibilityIdentifier("history.filter")
                    Spacer()
                    Button("Keep Recordings: \(container.settings.audioRetention.title)") {
                        container.navigation.page = .configuration
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Change recording retention in Configuration")
                }
                .padding(.top, Theme.controlSpacing)
                if let meeting = container.meeting, meeting.isBusy || !meeting.drafts.isEmpty || meeting.recoveryIssue != nil {
                    HStack {
                        Text(meeting.isBusy ? "Meeting recording in progress" : "Interrupted meeting recording available").supportingText()
                        Spacer()
                        Button(meeting.isBusy ? "Show Meeting" : "Recover Meeting") { meeting.isPresented = true }.buttonStyle(SoftButtonStyle())
                    }.padding(.top, Theme.controlSpacing)
                }
                if let media = container.media, media.isBusy && media.document == nil {
                    HStack { ProgressView().controlSize(.small); Text("Preparing Media…").supportingText(); Spacer(); Button("Cancel") { media.cancel() }.buttonStyle(SoftButtonStyle()) }
                        .padding(.top, Theme.controlSpacing)
                }
                if let issue = container.media?.issue {
                    HStack { Text(issue).supportingText(); Spacer(); Button("Dismiss") { container.media?.clearIssue() }.buttonStyle(SoftButtonStyle()) }
                        .padding(.top, Theme.controlSpacing)
                }
                if let errorMessage {
                    StorageNotice(message: errorMessage) { Task { await reload() } }
                        .padding(.top, Theme.controlSpacing)
                }
                if let error = container.pipeline.historyStorageError {
                    StorageNotice(message: error) { Task { await container.pipeline.retryHistorySave(); await reload() } }
                        .padding(.top, Theme.controlSpacing)
                }
                if snapshot.entries.isEmpty {
                    if loading {
                        ProgressView("Loading History…").controlSize(.small).padding(.top, Theme.pagePadding)
                    } else {
                    EmptyNote(query.isEmpty ? (recordingsOnly ? "No saved recordings." : "No history yet.") : "No matches.")
                        .padding(.top, Theme.pagePadding)
                    if recordingsOnly && query.isEmpty && container.settings.audioRetention == .off {
                        Text("Turn on Keep Recordings to save future dictations.").supportingText()
                    }
                    }
                } else {
                    HStack(alignment: .top, spacing: Theme.controlSpacing) {
                        HistoryTimeline(snapshot: snapshot, scroll: scroll)
                        HistoryEntries(snapshot: snapshot, rowStates: rowStates, scroll: scroll, playback: playback,
                                       showReview: $showReview, errorMessage: $errorMessage,
                                       hasMore: hasMore, loading: loading,
                                       reload: { Task { await reload() } },
                                       loadMore: { Task { await reload(append: true) } })
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        } accessory: {
            Menu {
                Button("Import Media…") { chooseMedia() }.disabled(container.media == nil)
                Button("Record Meeting…") { container.meeting?.isPresented = true }.disabled(container.meeting == nil)
            } label: { Image(systemName: "plus").accessibilityLabel("Add Recording") }
                .menuStyle(.borderlessButton).fixedSize().help("Import Media or Record Meeting")
                .disabled(container.pipeline.isBusy)
            SearchField(text: $query, placeholder: "Search history")
            Button { confirmClear = true } label: { Image(systemName: "trash") }
                .buttonStyle(SoftButtonStyle())
                .help("Delete all history and recordings")
                .accessibilityLabel("Delete All History and Recordings")
                .disabled((snapshot.entries.isEmpty && query.isEmpty) || container.pipeline.isBusy || container.pipeline.isSavingHistory)
        }
        .task(id: query) {
            // Invalidate an older append/reload immediately, before the debounce.
            loadID = UUID()
            playback.stop()
            if !query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            await reload()
        }
        .onChange(of: recordingsOnly) { _, _ in
            playback.stop()
            scroll = HistoryScrollState()
            snapshot = .empty
            Task { await reload() }
        }
        .sheet(isPresented: $showImport) { MediaImportSheet(source: importURL).environment(container) }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard !container.pipeline.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in if let url { importURL = url; showImport = true } }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaEditorOpened)) { _ in playback.stop() }
        .onDisappear { playback.stop() }
        .onChange(of: container.pipeline.isBusy) { _, busy in if busy { playback.stop() } }
        .onChange(of: container.pipeline.audioRevision) { _, _ in playback.stop(); Task { await reload() } }
        .onChange(of: container.settings.audioRetention) { _, _ in playback.stop(); Task { await reload() } }
        .sheet(isPresented: $showReview, onDismiss: { container.pipeline.dismissReview() }) {
            HistoryTranscriptionReview().environment(container)
        }
        .onChange(of: container.pipeline.lastOutcome) { _, _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .historyEntriesChanged)) { _ in
            playback.stop(); Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in Task { await reload() } }
        .confirmationDialog("Delete all history and recordings?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete History and Recordings", role: .destructive) {
                guard !container.pipeline.isBusy, !container.pipeline.isSavingHistory else { return }
                playback.stop()
                Task { await container.performCleanup(.historyAndAudio) }
            }
        }
    }

    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importURL = url; showImport = true
        }
    }

    private func reload(append: Bool = false) async {
        guard let history = container.history else {
            errorMessage = "History storage is unavailable. Restart Airdraft after checking available disk space."
            return
        }
        if append && loading { return }
        let token = UUID()
        loadID = token
        loading = true
        defer { if loadID == token { loading = false } }
        let query = query
        let previous = append ? snapshot : .empty
        let pageSize = pageSize
        let recordingsOnly = recordingsOnly
        let offset = append ? (nextOffset ?? previous.entries.count) : 0
        let prepare: @Sendable () throws -> (HistorySnapshot, Int?) = {
            if recordingsOnly {
                let page = try history.recordings(limit: pageSize, query: query, offset: offset)
                return (HistorySnapshot.prepareRecordings(page.entries, appendingTo: previous), page.nextOffset)
            }
            let found = try history.historyItems(limit: pageSize + 1, offset: offset, query: query)
            return (HistorySnapshot.prepareItems(Array(found.prefix(pageSize)), appendingTo: previous),
                    found.count > pageSize ? offset + pageSize : nil)
        }
        do {
            let result: (HistorySnapshot, Int?)
            if RenderMode.isActive { result = try prepare() }
            else { result = try await Task.detached(priority: .userInitiated, operation: prepare).value }
            guard !Task.isCancelled, loadID == token else { return }
            #if DEBUG
            HistoryRenderMetrics.groupingPasses += 1
            HistoryRenderMetrics.groupedRecords += result.0.entries.count
            #endif
            rowStates = Dictionary(uniqueKeysWithValues: result.0.entries.map { ($0.id, rowStates[$0.id] ?? HistoryCardState()) })
            snapshot = result.0
            if let playingID = playback.recordingID, !snapshot.entries.contains(where: { $0.asset?.id == playingID }) {
                playback.stop()
            }
            hasMore = result.1 != nil
            nextOffset = result.1
            errorMessage = nil
            if scroll.currentRecordID.flatMap({ snapshot.indexByID[$0] }) == nil {
                scroll.currentRecordID = snapshot.entries.first?.id
                scroll.entryPosition.scrollTo(edge: .top)
            }
        } catch {
            guard loadID == token else { return }
            errorMessage = "History could not be loaded. " + error.localizedDescription
        }
    }
}

@MainActor @Observable
private final class HistoryScrollState {
    var currentRecordID: String?
    var entriesAtTop = true
    var entryPosition = ScrollPosition(idType: String.self)
}

/// Survives lazy row eviction without keeping the row's view hierarchy alive.
@MainActor @Observable
final class HistoryCardState {
    enum Presentation { case details, deletion, audioDeletion, media }
    var showMedia = false
    var showMediaImport = false
    var showRaw = false
    var expanded = false
    var showInfo = false
    var copied = false
    var confirmDelete = false
    var confirmAudioDelete = false
    var exporting = false
    var mounted = false
    var pendingPresentation: Presentation?

    func dismissPresentation() {
        pendingPresentation = nil
        showInfo = false
        showMedia = false
        showMediaImport = false
        confirmDelete = false
        confirmAudioDelete = false
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
    }
}

/// The visual stacks never observe viewport IDs. Only the replacement AX
/// child reads them, keeping normal scrolling independent of row view updates.
@MainActor @Observable
private final class HistoryVisibleRows {
    var ids: [String] = []
    @ObservationIgnored var viewport = HistoryViewport()

    func update(_ visible: [String], snapshot: HistorySnapshot) {
        let ordered = visible.compactMap { snapshot.indexByID[$0] }.sorted().map { snapshot.entries[$0].id }
        if ids != ordered { ids = ordered }
    }

    func setVisible(_ id: String, _ visible: Bool, snapshot: HistorySnapshot) {
        var next = Set(ids)
        if visible { next.insert(id) } else { next.remove(id) }
        update(Array(next), snapshot: snapshot)
    }

    func paging(_ edge: Edge, from position: ScrollPosition) -> ScrollPosition {
        guard viewport.height > 0 else { return position }
        // macOS exposes Next/Previous Page as leading/trailing swipes.
        let forward = edge == .bottom || edge == .leading
        let target = viewport.offset + (forward ? viewport.height : -viewport.height)
        var next = position
        if target <= 0 { next.scrollTo(edge: .top) }
        else if target >= viewport.maximumOffset { next.scrollTo(edge: .bottom) }
        else { next.scrollTo(y: target) }
        return next
    }
}

private struct HistoryViewport: Equatable {
    var offset: CGFloat = 0
    var height: CGFloat = 0
    var maximumOffset: CGFloat = 0

    init() {}

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y + geometry.contentInsets.top
        height = geometry.containerSize.height
        maximumOffset = max(0, geometry.contentSize.height + geometry.contentInsets.top
                            + geometry.contentInsets.bottom - height)
    }
}

private struct HistoryVisibleAccessibility<Content: View>: View {
    let snapshot: HistorySnapshot
    let visibility: HistoryVisibleRows
    let content: ([HistoryEntry]) -> Content

    var body: some View {
        let indices = visibility.ids.compactMap { snapshot.indexByID[$0] }.sorted()
        let entries = indices.isEmpty ? Array(snapshot.entries.prefix(1)) : indices.map { snapshot.entries[$0] }
        content(entries)
    }
}

private struct HistoryEntries: View {
    let snapshot: HistorySnapshot
    let rowStates: [String: HistoryCardState]
    @Bindable var scroll: HistoryScrollState
    let playback: RecordingPlayback
    @Binding var showReview: Bool
    @Binding var errorMessage: String?
    let hasMore: Bool
    let loading: Bool
    let reload: () -> Void
    let loadMore: () -> Void
    @State private var visibility = HistoryVisibleRows()
    @Namespace private var rotorNamespace

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.controlSpacing) {
                rows(snapshot.entries, accessibilityOnly: false)
            }
            .scrollTargetLayout()
            if hasMore {
                Button(loading ? "Loading…" : "Load Older Entries", action: loadMore)
                    .buttonStyle(SoftButtonStyle()).disabled(loading)
                    .padding(.vertical, Theme.controlSpacing)
            }
        }
        .pageScrollEdge()
        .contentMargins(.top, Theme.pagePadding, for: .scrollContent)
        // Extend the scroll view into the gap beside the timeline and the page's trailing and
        // bottom margins, then pad the cards back, so their light and shade are never clipped.
        .contentMargins(.leading, Theme.controlSpacing, for: .scrollContent)
        .contentMargins([.trailing, .bottom], Theme.pagePadding, for: .scrollContent)
        .padding(.leading, -Theme.controlSpacing)
        .padding([.trailing, .bottom], -Theme.pagePadding)
        .scrollPosition($scroll.entryPosition)
        .onScrollGeometryChange(for: HistoryViewport.self) { HistoryViewport($0) } action: { _, value in
            visibility.viewport = value
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= -geometry.contentInsets.top + 1
        } action: { _, atTop in
            scroll.entriesAtTop = atTop
            if atTop { scroll.currentRecordID = snapshot.entries.first?.id }
        }
        // Zero includes fully offscreen prefetched rows. A small positive
        // fraction excludes those while retaining tall expanded transcripts.
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.0001) { visibleIDs in
            visibility.update(visibleIDs, snapshot: snapshot)
            if let id = snapshot.firstVisibleID(in: visibleIDs) { scroll.currentRecordID = id }
        }
        .accessibilityRepresentation {
            HistoryVisibleAccessibility(snapshot: snapshot, visibility: visibility) { entries in
                VStack(alignment: .leading, spacing: Theme.controlSpacing) {
                    rows(entries, accessibilityOnly: true)
                    if hasMore {
                        Button(loading ? "Loading…" : "Load Older Entries", action: loadMore).disabled(loading)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dictation entries")
            .accessibilityScrollAction { edge in
                scroll.entryPosition = visibility.paging(edge, from: scroll.entryPosition)
            }
            .accessibilityAction(named: "Scroll to First Dictation") { scroll.entryPosition.scrollTo(edge: .top) }
            .accessibilityAction(named: "Scroll to Last Dictation") { scroll.entryPosition.scrollTo(edge: .bottom) }
            .accessibilityAction(named: "Next Dictation") { move(by: 1) }
            .accessibilityAction(named: "Previous Dictation") { move(by: -1) }
            .accessibilityRotor("Dictations") {
                ForEach(snapshot.entries) { entry in
                    AccessibilityRotorEntry(Text(entry.timestamp), id: entry.id, in: rotorNamespace) {
                        scroll.entryPosition.scrollTo(id: entry.id, anchor: .top)
                    }
                }
            }
        }
        .accessibilityIdentifier("history.entries")
        .onDisappear { for state in rowStates.values { state.dismissPresentation() } }
    }

    private func move(by offset: Int) {
        guard !snapshot.entries.isEmpty else { return }
        let current = scroll.currentRecordID.flatMap { snapshot.indexByID[$0] } ?? 0
        let next = min(snapshot.entries.count - 1, max(0, current + offset))
        scroll.entryPosition.scrollTo(id: snapshot.entries[next].id, anchor: .top)
    }

    private func rows(_ entries: [HistoryEntry], accessibilityOnly: Bool) -> some View {
        ForEach(entries) { entry in
            HistoryRecordRow(entry: entry, state: rowStates[entry.id]!, rotorNamespace: rotorNamespace, playback: playback,
                             isFirst: entry.id == snapshot.entries.first?.id,
                             showReview: $showReview, errorMessage: $errorMessage, reload: reload,
                             accessibilityOnly: accessibilityOnly,
                             reveal: { scroll.entryPosition.scrollTo(id: entry.id, anchor: .top) },
                             clearPresentations: {
                                 for state in rowStates.values { state.dismissPresentation() }
                             })
                .id(entry.id)
        }
    }
}

private struct HistoryRecordRow: View {
    @Environment(AppContainer.self) private var container
    let entry: HistoryEntry
    let state: HistoryCardState
    let rotorNamespace: Namespace.ID
    let playback: RecordingPlayback
    let isFirst: Bool
    @Binding var showReview: Bool
    @Binding var errorMessage: String?
    let reload: () -> Void
    var accessibilityOnly = false
    var reveal: () -> Void = {}
    var clearPresentations: () -> Void = {}

    @ViewBuilder
    var body: some View {
        if accessibilityOnly {
            accessibleCard.accessibilityRotorEntry(id: entry.id, in: rotorNamespace)
        } else {
            VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                if let heading = entry.heading {
                    SectionTitle(heading)
                        .padding(.top, isFirst ? 0 : Theme.sectionSpacing - Theme.controlSpacing)
                }
                if let document = entry.document {
                    MediaDocumentCard(document: document, preview: entry.finalText.preview, recordingControls: recordingControls(), open: { revealAndPresent(.media) })
                        .accessibilityIdentifier("history.entry.\(entry.id)")
                } else if let record = entry.record {
                    HistoryCard(entry: entry, state: state, record: record,
                                canDelete: !container.pipeline.isBusy && !container.pipeline.isSavingHistory,
                                recordingControls: recordingControls(),
                                onDelete: delete)
                        .accessibilityIdentifier("history.entry.\(entry.id)")
                } else {
                    Card(spacing: Theme.controlSpacing) {
                        HStack {
                            Text("Recording").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(entry.time).supportingText()
                        }
                        Text("No saved transcript").supportingText()
                        recordingControls()
                    }
                    .accessibilityIdentifier("history.entry.\(entry.id)")
                }
            }
            .sheet(isPresented: Binding(get: { state.showMediaImport }, set: { state.showMediaImport = $0 })) {
                MediaImportSheet(source: nil, recording: entry.asset).environment(container)
            }
            .sheet(isPresented: Binding(get: { state.showMedia }, set: { state.showMedia = $0 })) {
                if let document = entry.document { MediaDocumentEditor(initial: document).environment(container) }
            }
            .confirmationDialog("Delete this recording?", isPresented: Binding(get: { state.confirmAudioDelete }, set: { state.confirmAudioDelete = $0 }), titleVisibility: .visible) {
                Button("Delete Recording", role: .destructive, action: deleteAudio)
            } message: {
                Text(entry.record == nil ? "This cannot be undone." : "The transcript stays in History. This cannot be undone.")
            }
            .onAppear {
                state.mounted = true
                if let pending = state.pendingPresentation {
                    state.pendingPresentation = nil
                    present(pending)
                }
            }
            .onDisappear {
                state.mounted = false
                state.dismissPresentation()
            }
        }
    }

    /// Keep the visual stack lazy without exposing SwiftUI's crashing native
    /// lazy-list edge actions. This lightweight tree only represents visible
    /// rows; the real card remains the owner of native layout and presenters.
    private var accessibleCard: some View {
        @Bindable var state = state
        let content = state.showRaw ? entry.rawText : entry.finalText
        return VStack(alignment: .leading) {
            if let heading = entry.heading { Text(heading).accessibilityAddTraits(.isHeader) }
            if let document = entry.document {
                Text(document.title).font(.system(size: 13, weight: .medium))
                Text(entry.finalText.preview.isEmpty && document.transcriptionComplete ? "No speech detected." : entry.finalText.preview).lineLimit(4)
                MediaDocumentStatus(document: document)
                MediaDocumentActions(document: document) { revealAndPresent(.media) }
            }
            if let record = entry.record {
            Text(state.expanded ? content.full : content.preview)
                .lineLimit(state.expanded ? nil : 6)
                .textSelection(.enabled)
                .accessibilityLabel(content.full)
                .accessibilityAction(named: state.expanded ? "Collapse Transcript" : "Expand Transcript") {
                    reveal()
                    state.expanded.toggle()
                }
            if record.rawTranscript != record.finalText {
                SoftSegmentedPicker("Version", selection: $state.showRaw, options: [(false, "Refined"), (true, "Original")])
            }
            }
            Text(entry.metadata)
            if entry.audioAvailable { recordingControls(accessibilityOnly: true) }
            if entry.record != nil {
            Button("Copy") { state.copy(content.full) }
                .accessibilityLabel("Copy")
                .accessibilityIdentifier("history.copy.\(entry.id)")
            Button("Details") { revealAndPresent(.details) }
                .accessibilityLabel("Details")
                .accessibilityIdentifier("history.details.\(entry.id)")
            if !container.pipeline.isBusy, !container.pipeline.isSavingHistory {
                Button("Delete") { revealAndPresent(.deletion) }
                    .accessibilityLabel("Delete")
                    .accessibilityIdentifier("history.delete.\(entry.id)")
            }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.entry.\(entry.id)")
    }

    private func revealAndPresent(_ presentation: HistoryCardState.Presentation) {
        clearPresentations()
        if state.mounted { reveal(); present(presentation) }
        else { state.pendingPresentation = presentation; reveal() }
    }

    private func present(_ presentation: HistoryCardState.Presentation) {
        switch presentation {
        case .details: state.showInfo = true
        case .deletion: state.confirmDelete = true
        case .media: state.showMedia = true
        case .audioDeletion: state.confirmAudioDelete = true
        }
    }

    private func play() {
        guard !container.pipeline.isBusy, let history = container.history else { return }
        do {
            guard let asset = entry.asset, let url = history.audioURL(for: asset) else { throw CocoaError(.fileNoSuchFile) }
            try playback.toggle(id: asset.id, url: url)
        }
        catch { errorMessage = "Recording could not be played. " + error.localizedDescription }
    }

    @ViewBuilder private func recordingControls(accessibilityOnly: Bool = false) -> some View {
        if let asset = entry.asset {
            HistoryRecordingControls(asset: asset, playback: playback, busy: container.pipeline.isBusy,
                                     exporting: state.exporting, play: play, save: saveAudio,
                                     reveal: revealAudio,
                                     retranscribe: !container.pipeline.isBusy && !container.pipeline.hasRecoverableRecording ? retranscribe : nil,
                                     delete: !container.pipeline.isBusy && !container.pipeline.isSavingHistory ? { revealAndPresent(.audioDeletion) } : nil,
                                     accessibilityOnly: accessibilityOnly)
        }
    }

    private func saveAudio() {
        guard !state.exporting, let asset = entry.asset, let history = container.history else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        panel.nameFieldStringValue = "Airdraft_\(formatter.string(from: asset.createdAt))_\(asset.id.prefix(8)).wav"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            state.exporting = true
            Task {
                defer { state.exporting = false }
                do {
                    // NSSavePanel obtains explicit replacement confirmation.
                    try await Task.detached { try history.exportRecording(id: asset.id, to: destination, replacing: true) }.value
                } catch { errorMessage = "Audio could not be saved. " + error.localizedDescription }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private func revealAudio() {
        guard let asset = entry.asset, let url = container.history?.audioURL(for: asset) else {
            errorMessage = "This recording is no longer available. Refresh History to update the list."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteAudio() {
        guard !container.pipeline.isBusy, !container.pipeline.isSavingHistory,
              let asset = entry.asset, let history = container.history else { return }
        playback.stop()
        Task {
            do {
                try await Task.detached { try history.deleteRecording(id: asset.id) }.value
                NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
            } catch { errorMessage = "Recording could not be deleted. " + error.localizedDescription }
        }
    }

    private func retranscribe() {
        if let asset = entry.asset, asset.source != .dictation {
            guard !container.pipeline.isBusy else { return }
            playback.stop(); state.showMediaImport = true
            return
        }
        guard !container.pipeline.isBusy, !container.pipeline.hasRecoverableRecording else { return }
        playback.stop()
        guard let asset = entry.asset else { return }
        container.pipeline.retranscribe(asset)
        showReview = true
    }

    private func delete() {
        guard !container.pipeline.isBusy, !container.pipeline.isSavingHistory else { return }
        playback.stop()
        guard let id = entry.record?.id, let history = container.history else { return }
        Task {
            do {
                try await Task.detached { try history.delete(id: id) }.value
                NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
            } catch { errorMessage = "History could not be deleted. " + error.localizedDescription }
        }
    }
}

private struct HistoryTimeline: View {
    let snapshot: HistorySnapshot
    let scroll: HistoryScrollState
    @State private var position = ScrollPosition(idType: String.self)
    @State private var visibility = HistoryVisibleRows()
    @State private var marks = HistoryTimelineMarks()
    @Namespace private var rotorNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.entries) { entry in
                    VStack(alignment: .leading, spacing: 0) {
                        if let heading = entry.timelineHeading {
                            Text(heading)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: Theme.sectionTitleMinHeight, alignment: .leading)
                                .padding(.top, entry.id == snapshot.entries.first?.id ? 0 : Theme.controlSpacing)
                                .padding(.bottom, Theme.sectionTitleSpacing)
                                .help(entry.heading ?? heading)
                        }
                        HistoryTimelineButton(entry: entry, mark: marks.mark(for: entry.id)) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                scroll.currentRecordID = entry.id
                                scroll.entryPosition.scrollTo(id: entry.id, anchor: .top)
                            }
                        }
                    }
                    .id(entry.id)
                    // The timeline's compact lazy targets can report an empty
                    // aggregate after a programmatic jump on macOS. Track each
                    // rendered row so VoiceOver still sees the visible times.
                    .onScrollVisibilityChange(threshold: 0.0001) { visible in
                        setVisible(entry.id, visible)
                    }
                    .onDisappear {
                        setVisible(entry.id, false)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .pageScrollEdge()
        .contentMargins(.top, Theme.pagePadding, for: .scrollContent)
        .scrollPosition($position)
        .onScrollGeometryChange(for: HistoryViewport.self) { HistoryViewport($0) } action: { old, value in
            #if DEBUG
            if old.offset != value.offset { HistoryRenderMetrics.timelineScrolls += 1 }
            #endif
            visibility.viewport = value
        }
        .accessibilityRepresentation {
            HistoryVisibleAccessibility(snapshot: snapshot, visibility: visibility) { entries in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        if let heading = entry.timelineHeading { Text(heading).accessibilityAddTraits(.isHeader) }
                        HistoryTimelineButton(entry: entry, mark: marks.mark(for: entry.id)) {
                            scroll.currentRecordID = entry.id
                            scroll.entryPosition.scrollTo(id: entry.id, anchor: .top)
                        }
                        .accessibilityRotorEntry(id: entry.id, in: rotorNamespace)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dictation times")
            .accessibilityScrollAction { edge in position = visibility.paging(edge, from: position) }
            .accessibilityAction(named: "Scroll to First Dictation") { position.scrollTo(edge: .top) }
            .accessibilityAction(named: "Scroll to Last Dictation") { position.scrollTo(edge: .bottom) }
            .accessibilityRotor("Dictation Times") {
                ForEach(snapshot.entries) { entry in
                    AccessibilityRotorEntry(Text(entry.timestamp), id: entry.id, in: rotorNamespace) {
                        position.scrollTo(id: entry.id, anchor: .top)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // Only this empty child observes the current record, so a change
        // updates two row marks instead of re-evaluating the whole timeline.
        .background {
            HistoryTimelineFollower(scroll: scroll) { id in
                #if DEBUG
                HistoryRenderMetrics.currentRecordID = id
                HistoryRenderMetrics.recordChanges += 1
                #endif
                marks.select(id)
                if id == snapshot.entries.first?.id { position.scrollTo(edge: .top) }
                else if let id { reveal(id) }
            }
        }
        .onChange(of: scroll.entriesAtTop) { _, atTop in
            if atTop { position.scrollTo(edge: .top) }
        }
        .frame(width: HistoryTimelineButton.columnWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History timeline")
        .accessibilityIdentifier("history.timeline")
    }

    /// Scrolls only when the selected row reaches the viewport's edge, then
    /// leaves room ahead so the following selections need no scroll. Moving
    /// the lazy timeline for every record hitched the card column.
    private func reveal(_ id: String) {
        guard let index = snapshot.indexByID[id] else { return }
        // Sorted row indices; the first and last may be partly clipped.
        let visible = visibility.ids.compactMap { snapshot.indexByID[$0] }
        if let first = visible.first, let last = visible.last, first < index, index < last { return }
        let downward = visible.last.map { index >= $0 } ?? true
        position.scrollTo(id: id, anchor: UnitPoint(x: 0, y: downward ? 0.25 : 0.75))
    }

    private func setVisible(_ id: String, _ visible: Bool) {
        visibility.setVisible(id, visible, snapshot: snapshot)
        #if DEBUG
        HistoryRenderMetrics.timelineVisibleIDs = Set(visibility.ids)
        #endif
    }
}

/// Per-row selection, so moving the current record invalidates only the old and new rows.
@MainActor @Observable
private final class HistoryTimelineMark {
    var selected = false
}

@MainActor
private final class HistoryTimelineMarks {
    private var marks: [String: HistoryTimelineMark] = [:]
    private var selectedID: String?

    func mark(for id: String) -> HistoryTimelineMark {
        if let mark = marks[id] { return mark }
        let mark = HistoryTimelineMark()
        mark.selected = id == selectedID
        marks[id] = mark
        return mark
    }

    func select(_ id: String?) {
        guard id != selectedID else { return }
        if let selectedID { marks[selectedID]?.selected = false }
        selectedID = id
        if let id { marks[id]?.selected = true }
    }
}

private struct HistoryTimelineFollower: View {
    let scroll: HistoryScrollState
    let follow: (String?) -> Void

    var body: some View {
        Color.clear
            .onChange(of: scroll.currentRecordID, initial: true) { _, id in follow(id) }
            .accessibilityHidden(true)
    }
}

private struct HistoryTimelineButton: View {
    static let columnWidth: CGFloat = 52
    private static let rowHeight: CGFloat = 24
    private static let tickWidth: CGFloat = 10
    let entry: HistoryEntry
    let mark: HistoryTimelineMark
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let selected = mark.selected
        Button(action: action) {
            HStack(spacing: 4) {
                Text(entry.time)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Color.primary.opacity(selected ? 0.85 : hovering ? 0.55 : 0.25))
                    .frame(width: selected || hovering ? Self.tickWidth : Self.tickWidth * 0.65, height: selected ? 2 : 1)
                    .frame(width: Self.tickWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(selected || hovering ? .primary : .secondary)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Jump to \(entry.timestamp)")
        .accessibilityLabel("Jump to dictation, \(entry.timestamp)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("history.timeline.\(entry.id)")
    }
}

struct HistoryCard<RecordingControls: View>: View {
    let entry: HistoryEntry
    @Bindable var state: HistoryCardState
    let record: DictationRecord
    var canDelete = true
    let recordingControls: RecordingControls
    let onDelete: () -> Void

    private var content: HistoryTextContent { state.showRaw ? entry.rawText : entry.finalText }
    private var shownText: String { content.full }
    private var wasRefined: Bool { record.rawTranscript != record.finalText }

    var body: some View {
        #if DEBUG
        let _ = { HistoryRenderMetrics.cardBodies += 1 }()
        #endif
        Card(spacing: Theme.controlSpacing) {
            HistoryTranscript(content: content, expanded: $state.expanded)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                if wasRefined {
                    SoftSegmentedPicker("Version", selection: $state.showRaw,
                                        options: [(false, "Refined"), (true, "Original")], small: true)
                }
                Text(entry.metadata)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 14) {
                    Button(action: copy) { Image(systemName: state.copied ? "checkmark" : "doc.on.doc") }
                        .help("Copy")
                        .accessibilityLabel("Copy")
                    Button { state.showInfo.toggle() } label: { Image(systemName: "info.circle") }
                        .help("Details")
                        .accessibilityLabel("Details")
                        .popover(isPresented: $state.showInfo, arrowEdge: .bottom) { details.padding(Theme.cardPadding).frame(width: 360) }
                    if canDelete {
                        Button { state.confirmDelete = true } label: { Image(systemName: "trash") }
                            .help("Delete")
                            .accessibilityLabel("Delete")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            if entry.audioAvailable {
                RowDivider()
                recordingControls
            }
        }
        .contextMenu {
            Button("Copy", action: copy)
            if canDelete { Button("Delete…", role: .destructive) { state.confirmDelete = true } }
        }
        .confirmationDialog("Delete this dictation and its recording?", isPresented: $state.confirmDelete, titleVisibility: .visible) {
            Button("Delete Dictation", role: .destructive, action: onDelete)
        }
    }

    private func copy() {
        state.copy(shownText)
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("When", record.createdAt.formatted(date: .abbreviated, time: .standard))
            row("Audio", entry.audioAvailable ? "Saved locally" : "Unavailable")
            row("App", [record.appName, record.windowTitle].compactMap { $0 }.joined(separator: " — "))
            if let url = record.url { row("URL", url) }
            row("Profile", "\(record.mode) · \(record.family)")
            row("Speech", "\(record.asrEngine) · \(record.asrMs) ms")
            row("Refinement", record.llmEngine.map { "\($0) · \(record.llmMs) ms" } ?? "skipped")
            if let e = record.error { row("Error", e) }
            if record.outputDestination == TextOutputDestination.script.rawValue {
                row("Script delivery", record.outputSucceeded == true ? "completed" : "failed or interrupted")
            } else {
                row("Inserted", record.inserted ? "yes" : "no")
            }
        }
        .font(.system(size: 12))
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).lineLimit(3)
        }
    }
}
