import AirdraftCore
import SwiftUI
import Observation

/// Database preparation and page actions stay independent of scroll position.
struct HistoryPage: View {
    @Environment(AppContainer.self) private var container
    @State private var playback = HistoryPlayback()
    @State private var showReview = false
    @State private var snapshot = HistorySnapshot.empty
    @State private var rowStates: [Int64: HistoryCardState] = [:]
    @State private var scroll = HistoryScrollState()
    @State private var loadID = UUID()
    @State private var loading = false
    @State private var hasMore = false
    @State private var errorMessage: String?
    private let pageSize = min(10_000, max(1, Int(RenderMode.value("HISTORY_COUNT") ?? "") ?? 200))
    @State private var query = ""
    @State private var confirmClear = false

    var body: some View {
        PageScaffold(.history, scrollsContent: false, contentTopInset: 0) {
            if let errorMessage {
                StorageNotice(message: errorMessage) { Task { await reload() } }
            }
            if let error = container.pipeline.historyStorageError {
                StorageNotice(message: error) { Task { await container.pipeline.retryHistorySave(); await reload() } }
            }
            if snapshot.entries.isEmpty {
                EmptyNote(query.isEmpty ? "No dictations yet." : "No matches.")
                    .padding(.top, Theme.pagePadding)
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
        } accessory: {
            SearchField(text: $query, placeholder: "Search history")
            Button { confirmClear = true } label: { Image(systemName: "trash") }
                .buttonStyle(SoftButtonStyle())
                .help("Delete all history")
                .accessibilityLabel("Delete all history")
                .disabled((snapshot.entries.isEmpty && query.isEmpty) || container.pipeline.isBusy || container.pipeline.isSavingHistory)
        }
        .task(id: query) {
            // Invalidate an older append/reload immediately, before the debounce.
            loadID = UUID()
            if !query.isEmpty {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            await reload()
        }
        .onDisappear { playback.stop() }
        .onChange(of: container.pipeline.isBusy) { _, busy in if busy { playback.stop() } }
        .onChange(of: container.pipeline.audioRevision) { _, _ in playback.stop(); Task { await reload() } }
        .onChange(of: container.settings.audioRetention) { _, _ in playback.stop(); Task { await reload() } }
        .sheet(isPresented: $showReview, onDismiss: { container.pipeline.dismissReview() }) {
            HistoryTranscriptionReview().environment(container)
        }
        .onChange(of: container.pipeline.lastOutcome) { _, _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in Task { await reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in Task { await reload() } }
        .confirmationDialog("Delete every history entry?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                guard !container.pipeline.isBusy, !container.pipeline.isSavingHistory else { return }
                do {
                    playback.stop()
                    try container.history?.deleteAll()
                    Task { await reload() }
                } catch { errorMessage = "History could not be cleared. " + error.localizedDescription }
            }
        }
    }

    private func reload(append: Bool = false) async {
        guard let history = container.history else { return }
        if append && loading { return }
        let token = UUID()
        loadID = token
        loading = true
        defer { if loadID == token { loading = false } }
        let query = query
        let previous = append ? snapshot : .empty
        let pageSize = pageSize
        let prepare: @Sendable () throws -> (HistorySnapshot, Bool) = {
            let found = try history.recent(limit: pageSize + 1, query: query, offset: previous.entries.count)
            return (HistorySnapshot.prepare(Array(found.prefix(pageSize)), history: history, appendingTo: previous), found.count > pageSize)
        }
        do {
            let result: (HistorySnapshot, Bool)
            if RenderMode.isActive { result = try prepare() }
            else { result = try await Task.detached(priority: .userInitiated, operation: prepare).value }
            guard !Task.isCancelled, loadID == token else { return }
            #if DEBUG
            HistoryRenderMetrics.groupingPasses += 1
            HistoryRenderMetrics.groupedRecords += result.0.entries.count
            #endif
            rowStates = Dictionary(uniqueKeysWithValues: result.0.entries.map { ($0.id, rowStates[$0.id] ?? HistoryCardState()) })
            snapshot = result.0
            hasMore = result.1
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
    var currentRecordID: Int64?
    var entriesAtTop = true
    var entryPosition = ScrollPosition(idType: Int64.self)
}

/// Survives lazy row eviction without keeping the row's view hierarchy alive.
@MainActor @Observable
final class HistoryCardState {
    var showRaw = false
    var expanded = false
}

private struct HistoryEntries: View {
    let snapshot: HistorySnapshot
    let rowStates: [Int64: HistoryCardState]
    @Bindable var scroll: HistoryScrollState
    let playback: HistoryPlayback
    @Binding var showReview: Bool
    @Binding var errorMessage: String?
    let hasMore: Bool
    let loading: Bool
    let reload: () -> Void
    let loadMore: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.controlSpacing) {
                ForEach(snapshot.entries) { entry in
                    HistoryRecordRow(entry: entry, state: rowStates[entry.id]!, playback: playback,
                                     isFirst: entry.id == snapshot.entries.first?.id,
                                     showReview: $showReview, errorMessage: $errorMessage, reload: reload)
                        .id(entry.id)
                }
            }
            .scrollTargetLayout()
            if hasMore {
                Button(loading ? "Loading…" : "Load Older Dictations", action: loadMore)
                    .buttonStyle(SoftButtonStyle()).disabled(loading)
                    .padding(.vertical, Theme.controlSpacing)
            }
        }
        .pageScrollEdge()
        .contentMargins(.top, Theme.pagePadding, for: .scrollContent)
        .scrollPosition($scroll.entryPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= -geometry.contentInsets.top + 1
        } action: { _, atTop in
            scroll.entriesAtTop = atTop
            if atTop { scroll.currentRecordID = snapshot.entries.first?.id }
        }
        .onScrollTargetVisibilityChange(idType: Int64.self, threshold: 0.01) { visibleIDs in
            if let id = snapshot.firstVisibleID(in: visibleIDs) { scroll.currentRecordID = id }
        }
        .accessibilityIdentifier("history.entries")
    }
}

private struct HistoryRecordRow: View {
    @Environment(AppContainer.self) private var container
    let entry: HistoryEntry
    let state: HistoryCardState
    let playback: HistoryPlayback
    let isFirst: Bool
    @Binding var showReview: Bool
    @Binding var errorMessage: String?
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            if let heading = entry.heading {
                SectionTitle(heading)
                    .padding(.top, isFirst ? 0 : Theme.sectionSpacing - Theme.controlSpacing)
            }
            HistoryCard(entry: entry, state: state,
                        canDelete: !container.pipeline.isBusy && !container.pipeline.isSavingHistory,
                        playing: playback.recordID == entry.id,
                        onPlay: entry.audioAvailable ? play : nil,
                        onRetranscribe: entry.audioAvailable && !container.pipeline.isBusy && !container.pipeline.hasRecoverableRecording ? retranscribe : nil,
                        onDelete: delete)
                .accessibilityIdentifier("history.entry.\(entry.id)")
        }
    }

    private func play() {
        guard !container.pipeline.isBusy, let history = container.history else { return }
        do { try playback.toggle(entry.record, store: history) }
        catch { errorMessage = "Recording could not be played. " + error.localizedDescription }
    }

    private func retranscribe() {
        guard !container.pipeline.isBusy, !container.pipeline.hasRecoverableRecording else { return }
        playback.stop()
        container.pipeline.retranscribe(entry.record)
        showReview = true
    }

    private func delete() {
        guard !container.pipeline.isBusy, !container.pipeline.isSavingHistory else { return }
        do {
            playback.stop()
            try container.history?.delete(id: entry.id)
            reload()
        } catch { errorMessage = "History could not be deleted. " + error.localizedDescription }
    }
}

private struct HistoryTimeline: View {
    let snapshot: HistorySnapshot
    let scroll: HistoryScrollState
    @State private var position = ScrollPosition(idType: Int64.self)
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
                        HistoryTimelineButton(entry: entry, selected: entry.id == scroll.currentRecordID) {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                scroll.currentRecordID = entry.id
                                scroll.entryPosition.scrollTo(id: entry.id, anchor: .top)
                            }
                        }
                    }
                    .id(entry.id)
                }
            }
            .scrollTargetLayout()
        }
        .pageScrollEdge()
        .contentMargins(.top, Theme.pagePadding, for: .scrollContent)
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onChange(of: scroll.currentRecordID) { _, id in
            if id == snapshot.entries.first?.id { position.scrollTo(edge: .top) }
            else if let id { position.scrollTo(id: id) }
        }
        .onChange(of: scroll.entriesAtTop) { _, atTop in
            if atTop { position.scrollTo(edge: .top) }
        }
        .frame(width: HistoryTimelineButton.columnWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History timeline")
        .accessibilityIdentifier("history.timeline")
    }
}

private struct HistoryTimelineButton: View {
    static let columnWidth: CGFloat = 52
    private static let rowHeight: CGFloat = 24
    private static let tickWidth: CGFloat = 10
    let entry: HistoryEntry
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
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

struct HistoryCard: View {
    let entry: HistoryEntry
    @Bindable var state: HistoryCardState
    private var record: DictationRecord { entry.record }
    var canDelete = true
    var playing = false
    var onPlay: (() -> Void)? = nil
    var onRetranscribe: (() -> Void)? = nil
    let onDelete: () -> Void
    @State private var showInfo = false
    @State private var copied = false
    @State private var confirmDelete = false

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
                    Picker("Version", selection: $state.showRaw) {
                        Text("Refined").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Text(entry.metadata)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 14) {
                    if let onPlay {
                        Button(action: onPlay) { Image(systemName: playing ? "stop.fill" : "play.fill") }
                            .help(playing ? "Stop playback" : "Play recording")
                            .accessibilityLabel(playing ? "Stop Playback" : "Play Recording")
                    }
                    if let onRetranscribe {
                        Button(action: onRetranscribe) { Image(systemName: "arrow.clockwise") }
                            .help("Retranscribe with the current model and profile")
                            .accessibilityLabel("Retranscribe")
                    }
                    Button(action: copy) { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                        .help("Copy")
                        .accessibilityLabel("Copy")
                    Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                        .help("Details")
                        .accessibilityLabel("Details")
                        .popover(isPresented: $showInfo, arrowEdge: .bottom) { details.padding(Theme.cardPadding).frame(width: 360) }
                    if canDelete {
                        Button { confirmDelete = true } label: { Image(systemName: "trash") }
                            .help("Delete")
                            .accessibilityLabel("Delete")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Copy", action: copy)
            if let onPlay { Button(playing ? "Stop Playback" : "Play Recording", action: onPlay) }
            if let onRetranscribe { Button("Retranscribe", action: onRetranscribe) }
            if canDelete { Button("Delete…", role: .destructive) { confirmDelete = true } }
        }
        .confirmationDialog("Delete this dictation?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shownText, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("When", record.createdAt.formatted(date: .abbreviated, time: .standard))
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
