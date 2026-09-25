import XCTest
@testable import AirdraftCore

final class HistoryStoreTests: XCTestCase {
    func testSaveAndSearch() throws {
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
    }

    func testOverviewSummarisesPeriodLocally() throws {
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

    func testStreakSurvivesUntilTheDayAfter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-09-25T12:00:00Z")!
        let day = { (ago: Double) in now.addingTimeInterval(-ago * 86_400) }
        XCTAssertEqual(HistoryStore.streak([day(1), day(2), day(4)], now: now, calendar: calendar), 2)
        XCTAssertEqual(HistoryStore.streak([day(2), day(3)], now: now, calendar: calendar), 0)
        XCTAssertEqual(HistoryStore.streak([], now: now, calendar: calendar), 0)
    }

    func testWavEncoderHeader() {
        let data = WAVEncoder.encode(samples: [0, 0.5, -0.5], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
    }
}
