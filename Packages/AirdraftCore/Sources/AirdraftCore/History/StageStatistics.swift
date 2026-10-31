import Foundation
import GRDB

/// AD-142: how long each dictation stage takes, overall and per model, from
/// the timings History already stores. Speaking is the recording's length,
/// transcription is `asrMs` (lease wait, model preparation and inference) and
/// refinement is `llmMs` for rows refinement produced. Rates are weighted:
/// total stage seconds over total delivered words, so long dictations count
/// by their length rather than as one sample each.
public struct StageStatistics: Sendable, Equatable {
    public struct Stage: Sendable, Equatable {
        /// Dictations measured for this stage.
        public var dictations: Int
        /// Mean seconds per dictation.
        public var averageSeconds: Double
        /// Stage seconds per 100 delivered words; nil without counted words.
        public var secondsPer100Words: Double?

        public init(dictations: Int = 0, averageSeconds: Double = 0, secondsPer100Words: Double? = nil) {
            self.dictations = dictations
            self.averageSeconds = averageSeconds
            self.secondsPer100Words = secondsPer100Words
        }
    }

    /// One speech or refinement model the user dictated with.
    public struct Model: Sendable, Equatable, Identifiable {
        /// The stored engine identifier the rows are grouped by.
        public var id: String
        /// The latest readable name saved with it, or the identifier for rows
        /// saved before names were stored.
        public var name: String
        /// Whether it ran on this Mac; nil when no saved row says.
        public var onDevice: Bool?
        public var stage: Stage
    }

    public var speaking = Stage()
    public var transcription = Stage()
    public var refinement = Stage()
    /// Most used first.
    public var speechModels: [Model] = []
    /// Most used first; empty when nothing was refined.
    public var refinementModels: [Model] = []

    public init() {}

    public static let empty = StageStatistics()
    public var isEmpty: Bool { speaking.dictations == 0 }
}

extension HistoryStore {
    /// Aggregated in SQL over the same period as `overview`; reads no text.
    public func stageStatistics(days: Int? = nil, now: Date = Date(), calendar: Calendar = .current,
                                calendarDay: Bool = false) throws -> StageStatistics {
        try dbQueue.read { db in
            let period = Self.period(days: days, now: now, since: calendarDay ? calendar.startOfDay(for: now) : nil)
            let refined = "llmEngine IS NOT NULL AND llmMs > 0"
            var stats = StageStatistics()
            stats.speaking = try Self.stage(db, seconds: "audioSeconds", where: period.condition, period.arguments)
            stats.transcription = try Self.stage(db, seconds: "asrMs / 1000.0", where: period.condition, period.arguments)
            stats.refinement = try Self.stage(db, seconds: "llmMs / 1000.0", where: "\(refined) AND \(period.condition)",
                                              period.arguments)
            stats.speechModels = try Self.models(db, key: "asrEngine", name: "speechModel", onDevice: "speechOnDevice",
                                                 seconds: "asrMs / 1000.0", where: period.condition, period.arguments)
            stats.refinementModels = try Self.models(db, key: "llmEngine", name: "refinementModel",
                                                     onDevice: "refinementOnDevice", seconds: "llmMs / 1000.0",
                                                     where: "\(refined) AND \(period.condition)", period.arguments)
            return stats
        }
    }

    /// Mean seconds and the weighted rate over rows with a counted word total.
    private static func aggregates(_ seconds: String) -> String {
        """
        COUNT(*) AS dictations, COALESCE(AVG(\(seconds)), 0) AS average,
        SUM(CASE WHEN wordCount > 0 THEN \(seconds) END) AS rateSeconds,
        SUM(CASE WHEN wordCount > 0 THEN wordCount END) AS rateWords
        """
    }

    private static func stage(from row: Row) -> StageStatistics.Stage {
        let seconds: Double? = row["rateSeconds"]
        let words: Int? = row["rateWords"]
        let rate = seconds.flatMap { seconds in words.flatMap { $0 > 0 ? seconds / Double($0) * 100 : nil } }
        return .init(dictations: row["dictations"], averageSeconds: row["average"], secondsPer100Words: rate)
    }

    private static func stage(_ db: Database, seconds: String, where condition: String,
                              _ arguments: StatementArguments) throws -> StageStatistics.Stage {
        guard let row = try Row.fetchOne(db, sql: "SELECT \(aggregates(seconds)) FROM dictation WHERE \(condition)",
                                         arguments: arguments) else { return .init() }
        return stage(from: row)
    }

    private static func models(_ db: Database, key: String, name: String, onDevice: String, seconds: String,
                               where condition: String, _ arguments: StatementArguments) throws -> [StageStatistics.Model] {
        // SQLite returns the bare columns of the row that holds MAX(createdAt):
        // each model shows the name it was last saved with.
        var labels: [String: (name: String, onDevice: Bool?)] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT \(key) AS key, \(name) AS name, \(onDevice) AS onDevice, MAX(createdAt)
            FROM dictation WHERE \(name) IS NOT NULL AND \(condition) GROUP BY \(key)
            """, arguments: arguments) {
            labels[row["key"]] = (row["name"], row["onDevice"])
        }
        return try Row.fetchAll(db, sql: """
            SELECT \(key) AS key, \(aggregates(seconds)) FROM dictation
            WHERE \(key) IS NOT NULL AND \(condition) GROUP BY \(key)
            """, arguments: arguments).map { row in
            let id: String = row["key"]
            return StageStatistics.Model(id: id, name: labels[id]?.name ?? id, onDevice: labels[id]?.onDevice,
                                         stage: stage(from: row))
        }
        .sorted { $0.stage.dictations != $1.stage.dictations ? $0.stage.dictations > $1.stage.dictations : $0.name < $1.name }
    }
}
