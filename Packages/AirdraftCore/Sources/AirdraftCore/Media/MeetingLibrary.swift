import Foundation
import GRDB

/// One durable recording with every transcript version, or a transcript whose
/// audio was removed. Audio-only meetings remain visible after relaunch.
public struct MeetingLibraryEntry: Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let asset: RecordingAsset?
    public let audioAvailable: Bool
    public let documents: [TranscriptDocument]
    public var title: String {
        documents.first?.title ?? (asset?.source == .imported ? "Imported Recording" : "Meeting")
    }
}

extension HistoryStore {
    /// Filtering occurs before pagination; all versions of each matched recording stay reachable.
    public func meetings(limit: Int = 100, offset: Int = 0, query: String = "") throws -> [MeetingLibraryEntry] {
        try audioLock.withLock {
            try dbQueue.read { db in
                let pattern = "%\(query.trimmingCharacters(in: .whitespacesAndNewlines))%"
                let rows = try Row.fetchAll(db, sql: """
                    SELECT a.id, a.createdAt, 0 AS orphan FROM recordingAsset a
                    WHERE a.source != 'dictation' AND (a.id LIKE ? OR a.source LIKE ? OR EXISTS
                        (SELECT 1 FROM mediaDocument m WHERE m.recordingID = a.id AND (m.title LIKE ? OR m.text LIKE ?)))
                    UNION ALL
                    SELECT m.id, m.createdAt, 1 AS orphan FROM mediaDocument m
                    WHERE m.recordingID IS NULL AND (m.title LIKE ? OR m.text LIKE ?)
                    ORDER BY createdAt DESC, id DESC LIMIT ? OFFSET ?
                    """, arguments: [pattern, pattern, pattern, pattern, pattern, pattern, max(1, min(limit, 500)), max(0, offset)])
                return try rows.map { row in
                    let id: String = row["id"]
                    let orphan: Bool = row["orphan"]
                    let asset = orphan ? nil : try RecordingAsset.fetchOne(db, key: id)
                    let documents = try Row.fetchAll(db, sql: orphan
                        ? "SELECT payload, recordingID FROM mediaDocument WHERE id = ?"
                        : "SELECT payload, recordingID FROM mediaDocument WHERE recordingID = ? ORDER BY createdAt DESC, id DESC",
                        arguments: [id]).map(Self.decodeDocument)
                    return MeetingLibraryEntry(id: (orphan ? "document:" : "recording:") + id, createdAt: row["createdAt"],
                        asset: asset, audioAvailable: try asset.map { try existingAudioURL(named: $0.filename) != nil } ?? false,
                        documents: documents)
                }
            }
        }
    }
}
