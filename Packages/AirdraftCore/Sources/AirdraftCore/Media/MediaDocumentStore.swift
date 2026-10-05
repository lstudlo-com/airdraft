import Foundation
import GRDB
import AVFoundation

extension HistoryStore {
    public func createDocument(asset: RecordingAsset, title: String, configuration: MediaConfiguration) throws -> TranscriptDocument {
        try dbQueue.write { db in
            guard try RecordingAsset.fetchOne(db, key: asset.id) != nil else { throw MediaError.unavailable }
            let document = TranscriptDocument(recordingID: asset.id, title: title, configuration: configuration)
            try db.execute(sql: "INSERT INTO mediaDocument (id, createdAt, recordingID, title, text, revision, payload) VALUES (?, ?, ?, ?, ?, ?, ?)",
                           arguments: [document.id, document.createdAt, asset.id, title, "", 0, try JSONEncoder().encode(document)])
            return document
        }
    }

    /// Optimistic revision check prevents late callbacks from recreating removed/edited documents.
    @discardableResult public func updateDocument(_ document: TranscriptDocument) throws -> TranscriptDocument {
        try dbQueue.write { db in
            var next = document
            next.revision += 1
            try db.execute(sql: "UPDATE mediaDocument SET title = ?, text = ?, payload = ?, revision = ? WHERE id = ? AND revision = ?",
                           arguments: [next.title, next.text, try JSONEncoder().encode(next), next.revision, next.id, document.revision])
            guard db.changesCount == 1 else { throw MediaError.conflict }
            return next
        }
    }

    public func document(id: String) throws -> TranscriptDocument? {
        try dbQueue.read { db in try Row.fetchOne(db, sql: "SELECT payload, recordingID FROM mediaDocument WHERE id = ?", arguments: [id]).map(Self.decodeDocument) }
    }
    public func document(recordingID: String) throws -> TranscriptDocument? {
        try dbQueue.read { db in try Row.fetchOne(db, sql: "SELECT payload, recordingID FROM mediaDocument WHERE recordingID = ? ORDER BY createdAt DESC LIMIT 1", arguments: [recordingID]).map(Self.decodeDocument) }
    }
    public func documents(limit: Int = 200, offset: Int = 0, query: String = "") throws -> [TranscriptDocument] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT payload, recordingID FROM mediaDocument WHERE title LIKE ? OR text LIKE ? ORDER BY createdAt DESC, id DESC LIMIT ? OFFSET ?",
                             arguments: ["%\(query)%", "%\(query)%", limit, offset]).map(Self.decodeDocument)
        }
    }
    static func decodeDocument(_ row: Row) throws -> TranscriptDocument {
        var document = try JSONDecoder().decode(TranscriptDocument.self, from: row["payload"] as Data)
        document.recordingID = row["recordingID"] // Foreign-key deletion is authoritative, not the JSON snapshot.
        return document
    }
    public func deleteDocument(id: String) throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM mediaDocument WHERE id = ?", arguments: [id]) }
    }

    /// Adopts a completed, normalized WAV under the SQL writer lease. The importer owns its staging file.
    public func importRecording(from wav: URL, source: RecordingAsset.Source = .imported,
                                recordingID: String? = nil, captureIssue: String? = nil, createdAt: Date = Date()) throws -> RecordingAsset {
        try audioLock.withLock {
            let info = try FileManager.default.attributesOfItem(atPath: wav.path)
            guard info[.type] as? FileAttributeType == .typeRegular,
                  (info[.referenceCount] as? NSNumber)?.intValue == 1 else { throw MediaError.invalidAudio }
            let file = try AVAudioFile(forReading: wav)
            guard file.processingFormat.sampleRate == 16_000, (file.processingFormat.channelCount == 1 || (source == .meeting && file.processingFormat.channelCount == 2)), file.length > 0 else { throw MediaError.invalidAudio }
            let duration = Double(file.length) / 16_000
            guard duration <= MediaConfiguration.maximumDuration else { throw MediaError.tooLong }
            guard let directory = try checkedAudioDirectory(create: true) else { throw MediaError.unavailable }
            let id = recordingID ?? UUID().uuidString
            guard UUID(uuidString: id) != nil else { throw MediaError.invalidAudio }
            let destination = directory.appendingPathComponent(id + ".wav")
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw MeetingError.storage }
            do {
                return try dbQueue.write { db in
                    try FileManager.default.copyItem(at: wav, to: destination)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                    let handle = try FileHandle(forWritingTo: destination)
                    try handle.synchronize(); try handle.close()
                    let asset = RecordingAsset(filename: destination.lastPathComponent, createdAt: createdAt, duration: duration, source: source, captureIssue: captureIssue)
                    try asset.insert(db)
                    return asset
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }
}

public struct HistoryItem: Sendable {
    public let dictation: DictationRecord?
    public let document: TranscriptDocument?
    public let asset: RecordingAsset?
}

extension HistoryStore {
    /// A single SQL order/cursor across both kinds. Documents never masquerade as dictations.
    public func historyItems(limit: Int = 200, offset: Int = 0, query: String = "") throws -> [HistoryItem] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            let rows = try Row.fetchAll(db, sql: """
                SELECT 'dictation' AS kind, CAST(id AS TEXT) AS itemID, createdAt FROM dictation
                WHERE rawTranscript LIKE ? OR finalText LIKE ? OR appName LIKE ?
                UNION ALL
                SELECT 'document' AS kind, id AS itemID, createdAt FROM mediaDocument
                WHERE title LIKE ? OR text LIKE ?
                ORDER BY createdAt DESC, itemID DESC LIMIT ? OFFSET ?
                """, arguments: [pattern, pattern, pattern, pattern, pattern, limit, offset])
            return try rows.map { row in
                let id: String = row["itemID"]
                let record = row["kind"] as String == "dictation" ? try DictationRecord.fetchOne(db, key: Int64(id)) : nil
                let document = row["kind"] as String == "document" ? try Row.fetchOne(db, sql: "SELECT payload, recordingID FROM mediaDocument WHERE id = ?", arguments: [id]).map(Self.decodeDocument) : nil
                let assetID = record?.recordingID ?? document?.recordingID
                let asset = try assetID.flatMap { try RecordingAsset.fetchOne(db, key: $0) }
                let available = try asset.flatMap { try existingAudioURL(named: $0.filename) == nil ? nil : $0 }
                return HistoryItem(dictation: record, document: document, asset: available)
            }
        }
    }
}
