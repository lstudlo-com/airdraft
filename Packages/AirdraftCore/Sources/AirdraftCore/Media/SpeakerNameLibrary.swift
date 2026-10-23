import Foundation
import GRDB

/// Names typed for meeting speakers, suggested again in later transcripts.
///
/// The library stores display names and their last use only. It never stores
/// transcript text, document or recording IDs, speaker IDs or voice embeddings,
/// so a suggestion is a convenience, not a claim about who spoke. Text cleanup
/// (`deleteHistoryKeepingAudio`, `deleteAll`) and Reset remove it.
public enum SpeakerNameLibrary {
    /// Longer values are passages, not names, and are never remembered.
    public static let maximumNameLength = 60
    /// Oldest names beyond this bound are forgotten when new names are saved.
    public static let capacity = 100
    public static let suggestionLimit = 12

    /// The trimmed single-line name, or nil for empty, multi-line, over-long
    /// and default labels such as "Speaker 2".
    public static func rememberableName(_ raw: String) -> String? {
        guard !raw.contains(where: \.isNewline) else { return nil }
        let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty, name.count <= maximumNameLength, !isPlaceholder(name) else { return nil }
        return name
    }

    /// Default labels in English and in the current interface language.
    public static func isPlaceholder(_ name: String) -> Bool {
        if name == TranscriptDocument.unknownSpeakerName { return true }
        let digits = String(name.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        guard !digits.isEmpty else { return false }
        return name == "Speaker \(digits)" || name == TranscriptDocument.defaultSpeakerName(digits)
    }

    /// One entry per name regardless of case, width or diacritics.
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

extension HistoryStore {
    /// Records the rememberable names with one timestamp, keeping the newest
    /// spelling of each and pruning the oldest names beyond the capacity.
    public func rememberSpeakerNames(_ names: [String], at date: Date = Date()) throws {
        let accepted = names.compactMap(SpeakerNameLibrary.rememberableName)
        guard !accepted.isEmpty else { return }
        try dbQueue.write { db in
            for name in accepted {
                try db.execute(sql: """
                    INSERT INTO speakerName (key, name, lastUsedAt) VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET name = excluded.name, lastUsedAt = excluded.lastUsedAt
                    """, arguments: [SpeakerNameLibrary.key(name), name, date])
            }
            try db.execute(sql: """
                DELETE FROM speakerName WHERE key NOT IN
                (SELECT key FROM speakerName ORDER BY lastUsedAt DESC, key ASC LIMIT ?)
                """, arguments: [SpeakerNameLibrary.capacity])
        }
    }

    /// Most recently used first.
    public func recentSpeakerNames(limit: Int = SpeakerNameLibrary.suggestionLimit) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM speakerName ORDER BY lastUsedAt DESC, key ASC LIMIT ?",
                                arguments: [max(0, limit)])
        }
    }

    public func speakerNameCount() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM speakerName") ?? 0 }
    }

    /// Forgets suggestions only; names already saved in transcripts stay.
    public func forgetSpeakerNames() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM speakerName") }
    }
}
