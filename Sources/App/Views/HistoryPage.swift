import AirdraftCore
import SwiftUI

/// Dictation cards grouped by day, with search and a compact timeline navigator.
/// Each card shows the final text, can flip to the raw transcript, and has
/// copy / details / delete actions.
struct HistoryPage: View {
    @Environment(AppContainer.self) private var container
    @State private var records: [DictationRecord] = []
    @State private var loadID = UUID()
    @State private var loading = false
    @State private var hasMore = false
    @State private var errorMessage: String?
    private let pageSize = 200
    @State private var query = ""
    @State private var confirmClear = false
    @State private var currentRecordID: Int64?
    @State private var entryScrollPosition = ScrollPosition(idType: Int64.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PageScaffold(.history, scrollsContent: false) {
            if let errorMessage {
                StorageNotice(message: errorMessage) { Task { await reload() } }
            }
            if let error = container.pipeline.historyStorageError {
                StorageNotice(message: error) { Task { await container.pipeline.retryHistorySave(); await reload() } }
            }
            if records.isEmpty {
                EmptyNote(query.isEmpty ? "No dictations yet." : "No matches.")
            } else {
                HStack(alignment: .top, spacing: Theme.controlSpacing) {
                    timeline
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.controlSpacing) {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                                    if let heading = entry.heading {
                                        SectionTitle(heading)
                                            .padding(.top, entry.id == records.first?.id ? 0 : Theme.sectionSpacing - Theme.controlSpacing)
                                    }
                                    HistoryCard(record: entry.record) {
                                        do {
                                            try container.history?.delete(id: entry.id)
                                            Task { await reload() }
                                        } catch { errorMessage = "History could not be deleted. " + error.localizedDescription }
                                    }
                                    .accessibilityIdentifier("history.entry.\(entry.id)")
                                }
                                .id(entry.id)
                            }
                        }
                        .scrollTargetLayout()
                        if hasMore {
                            Button(loading ? "Loading…" : "Load Older Dictations") { Task { await reload(append: true) } }
                                .buttonStyle(SoftButtonStyle()).disabled(loading)
                                .padding(.vertical, Theme.controlSpacing)
                        }
                    }
                    .scrollPosition($entryScrollPosition)
                    .onScrollTargetVisibilityChange(idType: Int64.self, threshold: 0.01) { visibleIDs in
                        let visible = Set(visibleIDs)
                        if let first = records.first(where: { $0.id.map(visible.contains) ?? false }) {
                            currentRecordID = first.id
                        }
                    }
                    .accessibilityIdentifier("history.entries")
                }
                .frame(maxHeight: .infinity)
            }
        } accessory: {
            SearchField(text: $query, placeholder: "Search history")
            Button {
                confirmClear = true
            } label: { Image(systemName: "trash") }
            .buttonStyle(SoftButtonStyle())
            .help("Delete all history")
            .accessibilityLabel("Delete all history")
            .disabled(records.isEmpty && query.isEmpty)
        }
        .task(id: query) { await reload() }
        .onChange(of: container.pipeline.lastOutcome) { _, _ in Task { await reload() } }
        .confirmationDialog("Delete every history entry?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                do {
                    try container.history?.deleteAll()
                    Task { await reload() }
                } catch { errorMessage = "History could not be cleared. " + error.localizedDescription }
            }
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.controlSpacing) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.timelineTitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: Theme.sectionTitleMinHeight, alignment: .leading)
                                .padding(.bottom, Theme.sectionTitleSpacing)
                                .help(group.title)
                            ForEach(group.records) { record in
                                if let id = record.id {
                                    HistoryTimelineButton(record: record, selected: id == currentRecordID) {
                                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                            currentRecordID = id
                                            entryScrollPosition.scrollTo(id: id, anchor: .top)
                                        }
                                    }
                                    .id(id)
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentRecordID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(width: HistoryTimelineButton.columnWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History timeline")
        .accessibilityIdentifier("history.timeline")
    }

    private struct Group {
        let title: String
        let records: [DictationRecord]

        var timelineTitle: String {
            if title == "Today" || title == "Yesterday" { return title }
            return records.first?.createdAt.formatted(.dateTime.month(.abbreviated).day()) ?? title
        }
    }

    private struct Entry: Identifiable {
        let id: Int64
        let record: DictationRecord
        let heading: String?
    }

    // Direct, stable row targets let scrolling track individual entries across day groups.
    private var entries: [Entry] {
        groups.flatMap { group in
            group.records.enumerated().compactMap { index, record in
                guard let id = record.id else { return nil }
                return Entry(id: id, record: record, heading: index == 0 ? group.title : nil)
            }
        }
    }

    private var groups: [Group] {
        let cal = Calendar.current
        var order: [String] = []
        var map: [String: [DictationRecord]] = [:]
        for r in records {
            let title: String
            if cal.isDateInToday(r.createdAt) { title = "Today" }
            else if cal.isDateInYesterday(r.createdAt) { title = "Yesterday" }
            else { title = r.createdAt.formatted(date: .abbreviated, time: .omitted) }
            if map[title] == nil { order.append(title) }
            map[title, default: []].append(r)
        }
        return order.map { Group(title: $0, records: map[$0] ?? []) }
    }

    private func reload(append: Bool = false) async {
        guard let history = container.history else { return }
        if append && loading { return }
        let token = UUID()
        loadID = token
        loading = true
        defer { if loadID == token { loading = false } }
        let query = query
        let offset = append ? records.count : 0
        let limit = pageSize + 1
        do {
            let found: [DictationRecord]
            if RenderMode.isActive { found = try history.recent(limit: limit, query: query, offset: offset) }
            else { found = try await Task.detached { try history.recent(limit: limit, query: query, offset: offset) }.value }
            guard !Task.isCancelled, loadID == token else { return }
            hasMore = found.count > pageSize
            if append { records += found.prefix(pageSize) } else { records = Array(found.prefix(pageSize)) }
            errorMessage = nil
            resetTimelineIfNeeded()
        } catch {
            guard loadID == token else { return }
            errorMessage = "History could not be loaded. " + error.localizedDescription
        }
    }

    private func resetTimelineIfNeeded() {
        if !records.contains(where: { $0.id == currentRecordID }) {
            currentRecordID = records.first?.id
            entryScrollPosition.scrollTo(edge: .top)
        }
    }
}

/// A short ruler tick per saved transcription; the entire row is the jump target.
private struct HistoryTimelineButton: View {
    static let columnWidth: CGFloat = 52
    private static let rowHeight: CGFloat = 24
    private static let tickWidth: CGFloat = 10

    let record: DictationRecord
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(record.createdAt.formatted(date: .omitted, time: .shortened))
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
        .help("Jump to \(record.createdAt.formatted(date: .abbreviated, time: .standard))")
        .accessibilityLabel("Jump to dictation, \(record.createdAt.formatted(date: .abbreviated, time: .standard))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("history.timeline.\(record.id.map(String.init) ?? "unsaved")")
    }
}

struct HistoryCard: View {
    let record: DictationRecord
    let onDelete: () -> Void
    @State private var showRaw = false
    @State private var showInfo = false
    @State private var copied = false
    @State private var expanded = false
    @State private var confirmDelete = false

    private var shownText: String {
        (showRaw ? record.rawTranscript : record.finalText).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var wasRefined: Bool { record.rawTranscript != record.finalText }
    @State private var fullTextHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0
    private var isLong: Bool { expanded || fullTextHeight > collapsedHeight + 1 }

    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            Text(shownText)
                .font(.system(size: 14))
                .lineSpacing(3)
                .lineLimit(expanded ? nil : 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !expanded { collapsedHeight = $0 } }
                .background(alignment: .topLeading) {
                    Text(shownText).font(.system(size: 14)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullTextHeight = $0 }
                        .accessibilityHidden(true)
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLong {
                Button(expanded ? "Show Less" : "Show More") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            HStack(spacing: 10) {
                if wasRefined {
                    Picker("Version", selection: $showRaw) {
                        Text("Refined").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 14) {
                    Button(action: copy) { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                        .help("Copy")
                        .accessibilityLabel("Copy")
                    Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                        .help("Details")
                        .accessibilityLabel("Details")
                        .popover(isPresented: $showInfo, arrowEdge: .bottom) { details.padding(Theme.cardPadding).frame(width: 360) }
                    Button { confirmDelete = true } label: { Image(systemName: "trash") }
                        .help("Delete")
                        .accessibilityLabel("Delete")
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Copy", action: copy)
            Button("Delete…", role: .destructive) { confirmDelete = true }
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

    private var meta: String {
        var parts = [record.createdAt.formatted(date: .omitted, time: .shortened)]
        if let app = record.appName { parts.append(app) }
        parts.append(record.mode)
        parts.append("\(String(format: "%.0f", record.audioSeconds)) s")
        return parts.joined(separator: " · ")
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
            row("Inserted", record.inserted ? "yes" : "no")
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
