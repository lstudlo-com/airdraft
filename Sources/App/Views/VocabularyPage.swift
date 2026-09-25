import AirdraftCore
import SwiftUI

/// One input row: a word (or a mis-hearing) and, optionally, what to replace
/// it with. The list reads like "super whisper → Superwhisper".
struct VocabularyPage: View {
    @Environment(AppContainer.self) private var container
    @State private var removedEntry: DictionaryEntry?
    @State private var word = ""
    @State private var replacement = ""
    @State private var query = ""
    @FocusState private var focusWord: Bool

    var body: some View {
        PageScaffold(.vocabulary) {
            if let error = container.dictionary.persistenceError {
                StorageNotice(message: error) { container.dictionary.retrySave() }
            }
            if let entry = removedEntry {
                HStack {
                    Text("Vocabulary removed").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo") { container.dictionary.restore(entry); removedEntry = nil }.buttonStyle(SoftButtonStyle())
                }
            }
            Card {
            HStack(spacing: 10) {
                TextField("New word or mis-hearing", text: $word)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focusWord)
                    .onSubmit(add)
                Divider().frame(height: 18).opacity(0.5)
                TextField("Replace with…", text: $replacement)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .frame(width: 220)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(SoftButtonStyle())
                    .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Add (Return)")
            }
            }

            if container.dictionary.entries.isEmpty {
                EmptyNote("Words you add are always spelled this way. A replacement turns a mis-hearing into the right word.")
            } else if rows.isEmpty {
                EmptyNote("No matches.")
            } else {
                Card(padding: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        VocabularyLine(row: row) {
                            removedEntry = container.dictionary.entries.first { $0.id == row.entryID }
                            if let alias = row.alias { container.dictionary.removeAlias(alias, from: row.entryID) }
                            else { container.dictionary.remove(id: row.entryID) }
                        }
                    }
                }
            }
        } accessory: {
            SearchField(text: $query, placeholder: "Search vocabulary")
        }
        .onAppear { focusWord = true }
    }

    struct Row: Identifiable {
        let id: String
        let entryID: UUID
        let alias: String?
        let term: String
        let caseSensitive: Bool
    }

    private var rows: [Row] {
        var out: [Row] = []
        for e in container.dictionary.entries {
            if e.aliases.isEmpty {
                out.append(Row(id: e.id.uuidString, entryID: e.id, alias: nil, term: e.term, caseSensitive: e.caseSensitive))
            } else {
                for a in e.aliases {
                    out.append(Row(id: e.id.uuidString + "|" + a, entryID: e.id, alias: a, term: e.term, caseSensitive: e.caseSensitive))
                }
            }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return out }
        return out.filter { $0.term.lowercased().contains(q) || ($0.alias?.lowercased().contains(q) ?? false) }
    }

    private func add() {
        let w = word.trimmingCharacters(in: .whitespaces)
        let r = replacement.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return }
        if r.isEmpty {
            container.dictionary.add(DictionaryEntry(term: w))
        } else if let existing = container.dictionary.entries.first(where: { $0.term == r }) {
            var e = existing
            if !e.aliases.contains(w) { e.aliases.append(w) }
            container.dictionary.update(e)
        } else {
            container.dictionary.add(DictionaryEntry(term: r, aliases: [w]))
        }
        word = ""
        replacement = ""
        focusWord = true
    }
}

private struct VocabularyLine: View {
    let row: VocabularyPage.Row
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            if let alias = row.alias {
                Text(alias).font(.system(size: 14)).frame(width: 220, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                Text(row.term).font(.system(size: 14, weight: .medium))
            } else {
                Text(row.term).font(.system(size: 14, weight: .medium))
            }
            Spacer()
            Button(action: onDelete) { Image(systemName: "trash").font(.system(size: 13)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove")
                .accessibilityLabel("Remove \(row.alias.map { "\($0) → " } ?? "")\(row.term)")
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 10)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
        .contextMenu { Button("Remove", role: .destructive, action: onDelete) }
    }
}
