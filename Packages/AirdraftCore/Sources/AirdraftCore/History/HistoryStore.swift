import Foundation
import GRDB

public struct DictationRecord: Codable, Sendable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "dictation"

    public var id: Int64?
    public var createdAt: Date
    public var appBundleId: String?
    public var appName: String?
    public var windowTitle: String?
    public var url: String?
    public var mode: String
    public var family: String
    public var rawTranscript: String
    public var refinedText: String
    public var finalText: String
    public var language: String?
    public var asrEngine: String
    public var llmEngine: String?
    public var promptVersion: String?
    public var audioSeconds: Double
    public var asrMs: Int
    public var llmMs: Int
    public var inserted: Bool
    public var error: String?

    public init(
        id: Int64? = nil,
        createdAt: Date = Date(),
        appBundleId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        mode: String,
        family: String,
        rawTranscript: String,
        refinedText: String,
        finalText: String,
        language: String? = nil,
        asrEngine: String,
        llmEngine: String? = nil,
        promptVersion: String? = nil,
        audioSeconds: Double,
        asrMs: Int,
        llmMs: Int,
        inserted: Bool,
        error: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.mode = mode
        self.family = family
        self.rawTranscript = rawTranscript
        self.refinedText = refinedText
        self.finalText = finalText
        self.language = language
        self.asrEngine = asrEngine
        self.llmEngine = llmEngine
        self.promptVersion = promptVersion
        self.audioSeconds = audioSeconds
        self.asrMs = asrMs
        self.llmMs = llmMs
        self.inserted = inserted
        self.error = error
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// SQLite history at ~/Library/Application Support/Transcribar/history.sqlite.
public final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.sqlite")
        dbQueue = try DatabaseQueue(path: url.path)
        try migrate()
    }

    public init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: DictationRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("appBundleId", .text).indexed()
                t.column("appName", .text)
                t.column("windowTitle", .text)
                t.column("url", .text)
                t.column("mode", .text).notNull()
                t.column("family", .text).notNull()
                t.column("rawTranscript", .text).notNull()
                t.column("refinedText", .text).notNull()
                t.column("finalText", .text).notNull()
                t.column("language", .text)
                t.column("asrEngine", .text).notNull()
                t.column("llmEngine", .text)
                t.column("promptVersion", .text)
                t.column("audioSeconds", .double).notNull()
                t.column("asrMs", .integer).notNull()
                t.column("llmMs", .integer).notNull()
                t.column("inserted", .boolean).notNull()
                t.column("error", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }

    @discardableResult
    public func save(_ record: DictationRecord) throws -> DictationRecord {
        try dbQueue.write { db in
            var r = record
            try r.insert(db)
            return r
        }
    }

    public func recent(limit: Int = 200, query: String = "") throws -> [DictationRecord] {
        try dbQueue.read { db in
            var request = DictationRecord.order(Column("createdAt").desc).limit(limit)
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let pattern = "%\(q)%"
                request = request.filter(
                    Column("rawTranscript").like(pattern) || Column("finalText").like(pattern) || Column("appName").like(pattern)
                )
            }
            return try request.fetchAll(db)
        }
    }

    /// Final texts of recent dictations into the same app, oldest first.
    public func recentFinals(appBundleId: String?, within seconds: TimeInterval = 20 * 60, limit: Int = 3) throws -> [String] {
        guard let appBundleId else { return [] }
        return try dbQueue.read { db in
            let since = Date().addingTimeInterval(-seconds)
            let rows = try DictationRecord
                .filter(Column("appBundleId") == appBundleId && Column("createdAt") >= since)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
            return rows.reversed().map(\.finalText)
        }
    }

    public func delete(id: Int64) throws {
        _ = try dbQueue.write { db in
            try DictationRecord.deleteOne(db, key: id)
        }
    }

    public func deleteAll() throws {
        _ = try dbQueue.write { db in
            try DictationRecord.deleteAll(db)
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in try DictationRecord.fetchCount(db) }
    }

    public struct Stats: Sendable, Equatable {
        public var dictations: Int
        public var words: Int
        public var audioSeconds: Double
        public var apps: Int
        /// Words per minute of speech.
        public var wordsPerMinute: Int { audioSeconds > 1 ? Int(Double(words) / (audioSeconds / 60)) : 0 }
        /// Typing the same words at 40 wpm minus the time spent speaking.
        public var minutesSaved: Int { max(0, Int(Double(words) / 40 - audioSeconds / 60)) }
    }

    /// Aggregates over all history, or over the last `days` days.
    public func stats(days: Int? = nil) throws -> Stats {
        try dbQueue.read { db in
            var request = DictationRecord.all()
            if let days {
                let since = Date().addingTimeInterval(-Double(days) * 86_400)
                request = request.filter(Column("createdAt") >= since)
            }
            let rows = try request.fetchAll(db)
            let words = rows.reduce(0) { $0 + DictationPipeline.approximateWordCount($1.finalText) }
            let seconds = rows.reduce(0.0) { $0 + $1.audioSeconds }
            let apps = Set(rows.compactMap { $0.appBundleId ?? $0.appName }).count
            return Stats(dictations: rows.count, words: words, audioSeconds: seconds, apps: apps)
        }
    }
}
