import AirdraftCore
import SwiftUI

/// Single column of dictation cards grouped by day, with a toolbar search.
/// Each card shows the final text, can flip to the raw transcript, and has
/// copy / details / delete actions.
struct HistoryPage: View {
    @Environment(AppContainer.self) private var container
    @State private var records: [DictationRecord] = []
    @State private var query = ""
    @State private var confirmClear = false

    var body: some View {
        PageScaffold {
            if records.isEmpty {
                Text(query.isEmpty ? "No dictations yet." : "No matches.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(group.title)
                        ForEach(group.records) { record in
                            HistoryCard(record: record) {
                                if let id = record.id { try? container.history?.delete(id: id) }
                                reload()
                            }
                        }
                    }
                }
            }
        } accessory: {
            SearchField(text: $query, placeholder: "Search history")
            Button {
                confirmClear = true
            } label: { Image(systemName: "trash").font(.system(size: 13)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete all history")
        }
        .onAppear(perform: reload)
        .onChange(of: query) { _, _ in reload() }
        .onChange(of: container.pipeline.lastOutcome) { _, _ in reload() }
        .confirmationDialog("Delete every history entry?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                try? container.history?.deleteAll()
                reload()
            }
        }
    }

    private struct Group { let title: String; let records: [DictationRecord] }

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

    private func reload() {
        records = (try? container.history?.recent(limit: 300, query: query)) ?? []
    }
}

struct HistoryCard: View {
    let record: DictationRecord
    let onDelete: () -> Void
    @State private var showRaw = false
    @State private var showInfo = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(showRaw ? record.rawTranscript : record.finalText)
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Picker("", selection: $showRaw) {
                    Text("Refined").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
                Text(meta)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(showRaw ? record.rawTranscript : record.finalText, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                    } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help("Copy")
                    Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                        .help("Details")
                        .popover(isPresented: $showInfo, arrowEdge: .bottom) { details.padding(14).frame(width: 360) }
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help("Delete")
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
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
            row("LLM", record.llmEngine.map { "\($0) · \(record.llmMs) ms" } ?? "skipped")
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
