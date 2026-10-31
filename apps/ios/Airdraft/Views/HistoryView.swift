import AirdraftCore
import SwiftUI

/// Dictations by day, newest first, in one column. History reads happen off
/// the main actor and only when the page appears, the search changes or a
/// dictation finishes.
struct HistoryView: View {
    @Environment(MobileContainer.self) private var container
    @Environment(DictationController.self) private var controller
    @State private var records: [DictationRecord] = []
    @State private var query = ""
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let error = loadError ?? container.historyError {
                    ContentUnavailableView {
                        Label("History Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Reload History") { Task { await reload() } }
                            .buttonStyle(.soft)
                            .fixedSize()
                    }
                } else if records.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No Dictations Yet" : "No Matches", systemImage: "waveform")
                    } description: {
                        Text(query.isEmpty ? "Dictations you make appear here." : "Try another search.")
                    }
                } else {
                    list
                }
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle("History")
            .searchable(text: $query, prompt: Text("Search dictations"))
            .task(id: ReloadKey(query: query, result: controller.lastResult?.id)) { await reload() }
        }
    }

    private var list: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.records) { record in
                        NavigationLink(value: record) {
                            HistoryRow(record: record)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in delete(offsets.map { group.records[$0] }) }
                } header: {
                    Text(group.day, format: .dateTime.weekday(.abbreviated).month().day())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: DictationRecord.self) { record in
            HistoryDetailView(record: record) {
                delete([record])
            }
        }
    }

    private var days: [(day: Date, records: [DictationRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private struct ReloadKey: Equatable {
        let query: String
        let result: UUID?
    }

    private func reload() async {
        guard let store = container.history else { return }
        let search = query
        do {
            records = try await Task.detached(priority: .userInitiated) {
                try store.recent(limit: 300, query: search)
            }.value
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ doomed: [DictationRecord]) {
        guard let store = container.history else { return }
        for record in doomed {
            guard let id = record.id else { continue }
            try? store.delete(id: id)
        }
        let removed = Set(doomed.compactMap(\.id))
        records.removeAll { $0.id.map(removed.contains) ?? false }
    }
}

private struct HistoryRow: View {
    let record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.finalText)
                .font(.body)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text(record.createdAt, style: .time)
                Text(verbatim: "·")
                Text(Duration.seconds(record.audioSeconds), format: .units(allowed: [.minutes, .seconds], width: .narrow))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct HistoryDetailView: View {
    let record: DictationRecord
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmsDelete = false

    var body: some View {
        SoftPage {
            SoftCard {
                Text(record.finalText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = record.finalText
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.soft)
                    ShareLink(item: record.finalText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.soft)
                }
            }
            if record.rawTranscript != record.finalText {
                SoftSection(title: "Original transcript") {
                    Text(record.rawTranscript)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            SoftSection(title: "Details") {
                DetailRow(title: "Date", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                RowDivider()
                DetailRow(title: "Speech", value: record.asrEngine)
                if let llm = record.llmEngine {
                    RowDivider()
                    DetailRow(title: "Refinement", value: llm)
                }
                RowDivider()
                DetailRow(title: "Profile", value: RefinementProfile.displayName(forSavedName: record.mode))
                RowDivider()
                DetailRow(title: "Delivery", value: deliveryLabel)
                if let error = record.error {
                    RowDivider()
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Delete Dictation", role: .destructive) { confirmsDelete = true }
                .buttonStyle(.soft)
        }
        .navigationTitle(Text(record.createdAt, style: .date))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this dictation?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        }
    }

    private var deliveryLabel: String {
        switch record.outputDestination {
        case DictationRecord.copyDestination: String(localized: "Copied")
        case nil: String(localized: "Shown in Airdraft")
        default: record.inserted ? String(localized: "Inserted by the keyboard") : String(localized: "Sent to the keyboard")
        }
    }
}

private struct DetailRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
