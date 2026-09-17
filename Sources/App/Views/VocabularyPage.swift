import AirdraftCore
import SwiftUI

/// One input row: a word (or a mis-hearing) and, optionally, what to replace
/// it with. The list reads like "super whisper → Superwhisper".
struct VocabularyPage: View {
    @Environment(AppContainer.self) private var container
    @State private var word = ""
    @State private var replacement = ""
    @State private var query = ""
    @FocusState private var focusWord: Bool

    var body: some View {
        PageScaffold {
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
                Button(action: add) {
                    HStack(spacing: 6) {
                        Text("Add").font(.system(size: 12.5, weight: .medium))
                        KeyCap(text: "↩")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(word.trimmingCharacters(in: .whitespaces).isEmpty ? .tertiary : .secondary)
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))

            if container.dictionary.entries.isEmpty {
                Text("Words you add are always spelled this way. A replacement turns a mis-hearing into the right word.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.id) { row in
                        VocabularyLine(row: row) { container.dictionary.remove(id: row.entryID) }
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
            if hovering {
                Button(action: onDelete) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.primary.opacity(0.05) : .clear))
        .onHover { hovering = $0 }
    }
}
