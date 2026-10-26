import GRDB
import XCTest
@testable import AirdraftCore

final class HistoryStoreTests: XCTestCase {
    /// Merged: Home's first-run state, the period overview, SQL aggregates
    /// including uncounted rows (AD-077) and the streak rule.
    func testOverviewSummarisesPeriodAggregatesHomeFirstRunAndStreak() throws {
        XCTAssertEqual(HomeHistoryContent(loaded: false, available: true, hasDictations: false), .loading)
        XCTAssertEqual(HomeHistoryContent(loaded: true, available: true, hasDictations: false), .firstDictation)
        XCTAssertEqual(HomeHistoryContent(loaded: true, available: true, hasDictations: true), .metrics)
        // A failed read or a missing store is not a new user's first run.
        XCTAssertEqual(HomeHistoryContent(loaded: true, available: false, hasDictations: false), .unavailable)
        XCTAssertEqual(HomeHistoryContent(loaded: false, available: false, hasDictations: false), .unavailable)

        try overviewSummarisesPeriodLocally()
        try overviewAggregatesIncludeUncountedRowsAndKeepAppIdentity()

        // The streak survives until the day after the last active day.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        let day = { (ago: Double) in now.addingTimeInterval(-ago * 86_400) }
        XCTAssertEqual(HistoryStore.streak([day(1), day(2), day(4)], now: now, calendar: calendar), 2)
        XCTAssertEqual(HistoryStore.streak([day(2), day(3)], now: now, calendar: calendar), 0)
        XCTAssertEqual(HistoryStore.streak([], now: now, calendar: calendar), 0)
    }

    /// Merged: save, search and delete, waveform record identity and complete
    /// delivered text, and the WAV header used for saved audio.
    func testSaveSearchDeleteWaveformIdentityAndWavHeader() throws {
        let store = try HistoryStore(inMemory: true)
        let record = DictationRecord(
            appBundleId: "com.apple.Notes", appName: "Notes", mode: "clean", family: "document",
            rawTranscript: "raw text about floze", refinedText: "Raw text about Floze.", finalText: "Raw text about Floze.",
            asrEngine: "test", audioSeconds: 1.2, asrMs: 10, llmMs: 20, inserted: true
        )
        let saved = try store.save(record)
        XCTAssertNotNil(saved.id)
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.recent(query: "floze").count, 1)
        XCTAssertEqual(try store.recent(query: "nothing").count, 0)
        try store.delete(id: saved.id!)
        XCTAssertEqual(try store.count(), 0)

        try waveformKeepsRecordIdentityAndCompleteDeliveredText()

        let data = WAVEncoder.encode(samples: [0, 0.5, -0.5], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
    }

    /// The unverified-paste status is derived from existing columns, so it
    /// survives a save round trip and older rows keep their meaning.
    func testDeliveryStatusRoundTripsWithoutSchemaChange() throws {
        let store = try HistoryStore(inMemory: true)
        func saved(inserted: Bool, destination: TextOutputDestination?, succeeded: Bool?) throws -> TextDeliveryStatus {
            try store.save(DictationRecord(mode: "clean", family: "document", rawTranscript: "text", refinedText: "text",
                finalText: "text", asrEngine: "test", audioSeconds: 1, asrMs: 1, llmMs: 1, inserted: inserted,
                outputDestination: destination?.rawValue, outputSucceeded: succeeded))
            return try XCTUnwrap(store.recent(limit: 1).first).deliveryStatus
        }
        XCTAssertEqual(try saved(inserted: true, destination: .cursor, succeeded: true), .delivered)
        XCTAssertEqual(try saved(inserted: false, destination: .cursor, succeeded: true), .sentUnverified)
        XCTAssertEqual(try saved(inserted: false, destination: .cursor, succeeded: false), .notDelivered)
        XCTAssertEqual(try saved(inserted: false, destination: .script, succeeded: true), .delivered)
        XCTAssertEqual(try saved(inserted: false, destination: .script, succeeded: false), .notDelivered)
        XCTAssertEqual(try saved(inserted: true, destination: nil, succeeded: nil), .delivered)
        XCTAssertEqual(try saved(inserted: false, destination: nil, succeeded: nil), .notDelivered)
        // Statistics count every dictation whatever its delivery status.
        XCTAssertEqual(try store.overview().stats.dictations, 7)
    }

    private func overviewSummarisesPeriodLocally() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        let store = try HistoryStore(inMemory: true)
        func save(daysAgo: Double, app: String?, text: String, seconds: Double) throws {
            try store.save(DictationRecord(
                createdAt: now.addingTimeInterval(-daysAgo * 86_400), appBundleId: app.map { "test.\($0)" }, appName: app,
                mode: "clean", family: "document", rawTranscript: text, refinedText: text, finalText: text,
                asrEngine: "test", audioSeconds: seconds, asrMs: 1, llmMs: 1, inserted: true
            ))
        }
        try save(daysAgo: 10, app: "Mail", text: "one two three four five six", seconds: 3)
        try save(daysAgo: 2, app: "Slack", text: "one two", seconds: 1.5)
        try save(daysAgo: 1, app: "Slack", text: "one two three four", seconds: 3)
        try save(daysAgo: 0.1, app: "Notes", text: "one two three", seconds: 1.8)
        try save(daysAgo: 0, app: nil, text: "one", seconds: 0.5)

        let week = try store.overview(days: 7, now: now, calendar: calendar, pulseLimit: 3, appLimit: 2)
        XCTAssertEqual(week.stats.dictations, 4)
        XCTAssertEqual(week.stats.words, 10)
        XCTAssertEqual(week.pulses.map(\.words), [4, 3, 1], "latest pulses, oldest first")
        XCTAssertEqual(week.pulses.first?.wordsPerMinute, 80)
        XCTAssertEqual(week.pulses.last?.wordsPerMinute, 0, "sub-second audio has no rate")
        XCTAssertEqual(week.topApps.map(\.name), ["Slack", "Notes"])
        XCTAssertEqual(week.topApps.first?.words, 6)
        XCTAssertEqual(week.topApps.first?.bundleId, "test.Slack")
        XCTAssertEqual(week.streakDays, 3)
        XCTAssertEqual(week.activeDays, 3)
        XCTAssertEqual(week.longestWords, 4)

        let all = try store.overview(now: now, calendar: calendar)
        XCTAssertEqual(all.stats.dictations, 5)
        XCTAssertEqual(all.longestWords, 6)
        XCTAssertEqual(all.streakDays, week.streakDays, "streak ignores the period")
        XCTAssertEqual(try HistoryStore(inMemory: true).overview(now: now, calendar: calendar), .empty)
    }

    /// AD-077: the overview aggregates in SQL. Rows without a stored count
    /// (written by an older version) still count from their text, in totals,
    /// app shares and the longest dictation; an app keeps its earliest name.
    private func overviewAggregatesIncludeUncountedRowsAndKeepAppIdentity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        let store = try HistoryStore(inMemory: true)
        func save(hoursAgo: Double, bundle: String?, name: String?, text: String) throws {
            try store.save(DictationRecord(createdAt: now.addingTimeInterval(-hoursAgo * 3600), appBundleId: bundle,
                appName: name, mode: "clean", family: "document", rawTranscript: text, refinedText: text,
                finalText: text, asrEngine: "test", audioSeconds: 6, asrMs: 1, llmMs: 1, inserted: true))
        }
        try save(hoursAgo: 30, bundle: "test.mail", name: "Mail", text: "one two")
        try save(hoursAgo: 20, bundle: "test.mail", name: "Mail Renamed", text: "one two three")
        try save(hoursAgo: 10, bundle: nil, name: "Notes", text: "one")
        try save(hoursAgo: 2, bundle: nil, name: nil, text: "one two")
        // An older version's row: no stored count, so its text is counted.
        let long = "one two three four five six seven"
        try store.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dictation (createdAt, appBundleId, appName, mode, family, rawTranscript, refinedText,
                                       finalText, asrEngine, audioSeconds, asrMs, llmMs, inserted)
                VALUES (?, 'test.mail', 'Mail', 'clean', 'document', ?, ?, ?, 'old', 6, 1, 1, 1)
                """, arguments: [now.addingTimeInterval(-3600), long, long, long])
        }

        let all = try store.overview(now: now, calendar: calendar, pulseLimit: 2, appLimit: 5)
        XCTAssertEqual(all.stats, HistoryStore.Stats(dictations: 5, words: 15, audioSeconds: 30, apps: 2))
        XCTAssertEqual(all.longestWords, 7, "The uncounted row is the longest")
        XCTAssertEqual(all.topApps.map(\.name), ["Mail", "Notes"], "Earliest name; unnamed rows have no share")
        XCTAssertEqual(all.topApps.map(\.words), [12, 1])
        XCTAssertEqual(all.topApps.first?.bundleId, "test.mail")
        XCTAssertEqual(all.pulses.map(\.finalText), ["one two", long], "Latest pulses, oldest first")
        XCTAssertEqual(all.pulses.map(\.words), [2, 7])
        XCTAssertEqual(all.activeDays, 2)
        XCTAssertEqual(all.streakDays, 2)

        let today = try store.overview(days: 1, now: now, calendar: calendar, calendarDay: true)
        XCTAssertEqual(today.stats.dictations, 3, "Today starts at midnight in the calendar's time zone")
        XCTAssertEqual(today.stats.words, 10)
        XCTAssertEqual(today.activeDays, 1)
        XCTAssertEqual(try store.overview(now: now, calendar: calendar, pulseLimit: 0).pulses, [])
    }

    private func waveformKeepsRecordIdentityAndCompleteDeliveredText() throws {
        let store = try HistoryStore(inMemory: true)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let texts = ["First dictation.", String(repeating: "保留完整文字 🎙️\n", count: 300), "Final dictation."]
        let saved = try texts.map { text in
            try store.save(DictationRecord(createdAt: date, appName: "Notes", mode: "Clean", family: "document",
                rawTranscript: "unrefined source", refinedText: "before final processing", finalText: text,
                asrEngine: "test", audioSeconds: 3, asrMs: 1, llmMs: 1, inserted: true))
        }

        let overview = try store.overview(now: date, pulseLimit: 2)
        XCTAssertEqual(overview.pulses.map(\.id), saved.suffix(2).compactMap(\.id),
                       "Equal timestamps must still identify distinct, consistently ordered bars")
        XCTAssertEqual(overview.pulses.map(\.finalText), Array(texts.suffix(2)),
                       "The hero shows complete delivered text, not raw or intermediate refinement")
        try store.delete(id: XCTUnwrap(saved[1].id))
        let refreshed = try store.overview(now: date, pulseLimit: 2)
        XCTAssertEqual(refreshed.pulses.map(\.id), [saved[0], saved[2]].compactMap(\.id))
        XCTAssertEqual(refreshed.pulses.last?.finalText, texts.last)
        try store.deleteAll()
        XCTAssertEqual(try store.overview(now: date), .empty)
    }

    // MARK: - AD-072 stored word counts

    private func dictation(_ text: String, app: String? = "com.example.editor", date: Date = Date()) -> DictationRecord {
        DictationRecord(createdAt: date, appBundleId: app, appName: app.map { _ in "Editor" }, mode: "clean",
                        family: "document", rawTranscript: text, refinedText: text, finalText: text,
                        asrEngine: "test", audioSeconds: 6, asrMs: 1, llmMs: 1, inserted: true)
    }

    /// Merged: totals come from counts stored at save time and equal per-row
    /// counting; uncounted rows are counted and backfilled on open; a database
    /// from before `v7-word-count` gains the column and its counts.
    func testWordCountsAreStoredBackfilledAndMigrated() throws {
        let store = try HistoryStore(inMemory: true)
        let now = Date()
        let texts = ["Ship the build today.", "會議改到星期四下午", "Mixed 中文 and English words 123", ""]
        for (index, text) in texts.enumerated() {
            let saved = try store.save(dictation(text, app: index == 3 ? nil : "app.\(index % 2)",
                                                 date: now.addingTimeInterval(-Double(index) * 2 * 86_400)))
            XCTAssertEqual(saved.wordCount, DictationPipeline.approximateWordCount(text))
        }
        let expected = texts.map(DictationPipeline.approximateWordCount)
        XCTAssertEqual(try store.totalWords(), expected.reduce(0, +))
        let all = try store.stats(now: now)
        XCTAssertEqual(all, HistoryStore.Stats(dictations: 4, words: expected.reduce(0, +), audioSeconds: 24, apps: 2))
        // The period filter is the same as before: the last `days` days from now.
        let recent = try store.stats(days: 3, now: now)
        XCTAssertEqual(recent.dictations, 2)
        XCTAssertEqual(recent.words, expected[0] + expected[1])
        XCTAssertEqual(try store.overview(now: now).stats, all)
        XCTAssertEqual(try store.recent(limit: 4).map(\.wordCount), expected.map(Optional.some))

        try uncountedRowsAreCountedAndBackfilledOnOpen()
        try wordCountMigrationBackfillsExistingHistory()
    }

    /// Rows written without a count (by an older version, or before migration)
    /// are still counted from their text, then backfilled when the store opens.
    private func uncountedRowsAreCountedAndBackfilledOnOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "Four words right here"
        do {
            let store = try HistoryStore(directory: directory)
            try store.save(dictation(text))
            try store.save(dictation("two words"))
            // An older app version inserts rows without the new column.
            try store.dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO dictation (createdAt, mode, family, rawTranscript, refinedText, finalText,
                                           asrEngine, audioSeconds, asrMs, llmMs, inserted)
                    VALUES (?, 'clean', 'document', ?, ?, ?, 'old', 1, 1, 1, 1)
                    """, arguments: [Date(), text, text, text])
            }
            XCTAssertEqual(try store.totalWords(), 10, "Uncounted rows are counted from their text")
            XCTAssertEqual(try store.stats().words, 10)
            try store.close()
        }
        let reopened = try HistoryStore(directory: directory)
        let uncounted = try reopened.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dictation WHERE wordCount IS NULL")
        }
        XCTAssertEqual(uncounted, 0)
        XCTAssertEqual(try reopened.totalWords(), 10)
        try reopened.close()
    }

    /// A database from before `v7-word-count` gains the column and its counts.
    private func wordCountMigrationBackfillsExistingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try HistoryStore(directory: directory)
            for text in ["one", "one two", "會議"] { try store.save(dictation(text)) }
            // Return the schema to v6: no column, index or migration record.
            try store.dbQueue.write { db in
                try db.execute(sql: """
                    DROP INDEX dictation_uncounted;
                    ALTER TABLE dictation DROP COLUMN wordCount;
                    DELETE FROM grdb_migrations WHERE identifier = 'v7-word-count';
                    """)
            }
            try store.close()
        }
        let migrated = try HistoryStore(directory: directory)
        XCTAssertEqual(try migrated.recent().map(\.wordCount).sorted { ($0 ?? 0) < ($1 ?? 0) }, [1, 2, 2])
        XCTAssertEqual(try migrated.totalWords(), 5)
        try migrated.close()
    }
}
