import XCTest
@testable import AirdraftCore

@MainActor
final class PersistenceRecoveryTests: XCTestCase {
    func testUnsavedDictionaryDraftCanBeRetriedAfterStorageRecovery() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocking file".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DictionaryStore(directory: folder)
        store.add(DictionaryEntry(term: "Airdraft"))
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(store.entries.count, 1, "Unsaved work stays available")
        try FileManager.default.removeItem(at: folder)
        store.retrySave()
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(DictionaryStore(directory: folder).entries.first?.term, "Airdraft")
    }

    func testUnsavedProfileDraftSurvivesAndRetries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocking file".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(directory: folder)
        store.setBaseRules("A custom draft")
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(store.baseRules, "A custom draft")
        try FileManager.default.removeItem(at: folder)
        store.retrySave()
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(ProfileStore(directory: folder).baseRules, "A custom draft")
    }

    func testAliasRemovalPreservesSiblingsAndCanBeUndone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DictionaryStore(directory: folder)
        let entry = DictionaryEntry(term: "Airdraft", aliases: ["air draft", "air draught"])
        store.add(entry)
        store.removeAlias("air draft", from: entry.id)
        XCTAssertEqual(DictionaryStore(directory: folder).entries.first?.aliases, ["air draught"])
        store.restore(entry)
        XCTAssertEqual(store.entries.first?.aliases, entry.aliases)
    }

    func testHistoryPaginationHasNoGapsWithEqualTimestamps() throws {
        let store = try HistoryStore(inMemory: true)
        let date = Date()
        for i in 0..<305 { _ = try store.save(record(String(i), at: date)) }
        let first = try store.recent(limit: 200)
        let next = try store.recent(limit: 200, offset: 200)
        XCTAssertEqual(first.count, 200)
        XCTAssertEqual(next.count, 105)
        XCTAssertEqual(Set((first + next).compactMap(\.id)).count, 305)
        XCTAssertEqual(try store.recent(limit: 200, offset: 400), [])
    }

    func testCalendarTodayExcludesYesterdayAcrossDST() throws {
        let store = try HistoryStore(inMemory: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-03-08T18:00:00Z")!
        let start = calendar.startOfDay(for: now)
        _ = try store.save(record("yesterday", at: start.addingTimeInterval(-1)))
        _ = try store.save(record("today", at: start))
        let overview = try store.overview(days: 1, now: now, calendar: calendar, calendarDay: true)
        XCTAssertEqual(overview.stats.dictations, 1)
    }

    func testGroqLimitIsAppliedBeforeUploadWithoutChangingOtherProviders() {
        XCTAssertEqual(SpeechInputLimits.recordingSeconds(1800, for: .groq), 740)
        XCTAssertEqual(SpeechInputLimits.recordingSeconds(300, for: .groq), 300)
        XCTAssertEqual(SpeechInputLimits.recordingSeconds(1800, for: .apple), 1800)
        XCTAssertThrowsError(try SpeechInputLimits.validate(sampleCount: 12_000_001, for: .groq))
    }

    private func record(_ text: String, at date: Date) -> DictationRecord {
        DictationRecord(createdAt: date, mode: "Clean", family: "general", rawTranscript: text,
            refinedText: text, finalText: text, asrEngine: "test", audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: false)
    }
}
