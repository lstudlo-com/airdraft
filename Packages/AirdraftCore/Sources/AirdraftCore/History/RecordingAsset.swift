import Foundation
import GRDB

/// An app-owned recording survives deletion of its transcript. Do not store
/// transcript excerpts, application context, or speaker names in this record.
public struct RecordingAsset: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recordingAsset"

    public enum Source: String, Codable, Sendable, DatabaseValueConvertible {
        case dictation, imported, meeting
    }

    public let id: String
    public let createdAt: Date
    public let filename: String
    public let duration: Double
    public let source: Source

    init(filename: String, createdAt: Date, duration: Double, source: Source = .dictation) {
        self.id = String(filename.dropLast(4))
        self.filename = filename
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
    }
}

/// Cursor counts scanned database rows, including missing files, so a page of
/// missing recordings cannot hide older recordings that are still available.
public struct RecordingPage: Sendable {
    public struct Entry: Sendable, Identifiable {
        public var id: String { asset.id }
        public let asset: RecordingAsset
        public let dictation: DictationRecord?
        public var document: TranscriptDocument? = nil
    }
    public let entries: [Entry]
    public let nextOffset: Int?
}
