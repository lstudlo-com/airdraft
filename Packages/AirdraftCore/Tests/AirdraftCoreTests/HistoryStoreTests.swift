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

    func testWavEncoderHeader() {
        let data = WAVEncoder.encode(samples: [0, 0.5, -0.5], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
    }
}
