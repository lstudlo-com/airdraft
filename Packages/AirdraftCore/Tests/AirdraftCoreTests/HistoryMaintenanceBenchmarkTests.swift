import Foundation
import XCTest
@testable import AirdraftCore

/// AD-072: per-dictation history maintenance must not scale with history size.
/// Opt-in (`AIRDRAFT_BENCHMARK=1`, or `TEST_RUNNER_AIRDRAFT_BENCHMARK=1` through
/// xcodebuild) because it writes thousands of WAV sidecars. Results go to
/// `AIRDRAFT_BENCHMARK_OUTPUT` when set, and always to the test log.
@MainActor
final class HistoryMaintenanceBenchmarkTests: XCTestCase {
    private static let sentence = "Please move the quarterly review to Thursday afternoon and send the agenda to the design team before lunch "

    func testPerDictationMaintenanceWithLargeHistory() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIRDRAFT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in history maintenance benchmark") }
        let count = Int(environment["AIRDRAFT_BENCHMARK_HISTORY_COUNT"] ?? "") ?? 2000
        let suite = "airdraft.benchmark.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let store = try HistoryStore(directory: directory)
        let samples = [Float](repeating: 0.01, count: 4_000)
        let now = Date()
        for index in 0..<count {
            let text = String(repeating: Self.sentence, count: 1 + index % 4)
            _ = try store.save(record(text: text, date: now.addingTimeInterval(Double(index - count) * 60)), samples: samples)
        }

        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.audioRetention = .month
        let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: ProfileStore(directory: directory), history: store, historyDirectory: directory,
            factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in nil }))

        // The pipeline's own save path: what every delivered dictation runs.
        var saveMs: [Double] = []
        for _ in 0..<15 {
            pipeline.unsavedHistory.append((record(text: Self.sentence, date: Date()), samples))
            let started = ContinuousClock.now
            await pipeline.retryHistorySave()
            saveMs.append(Self.milliseconds(ContinuousClock.now - started))
            XCTAssertNil(pipeline.historyStorageError)
        }
        // The sidebar total refreshed after every save.
        var wordsMs: [Double] = []
        var words = 0
        for _ in 0..<15 {
            let started = ContinuousClock.now
            words = try store.stats().words
            wordsMs.append(Self.milliseconds(ContinuousClock.now - started))
        }
        // The full reconciliation, still run at launch, hourly and on retention changes.
        var pruneMs: [Double] = []
        for _ in 0..<3 {
            let started = ContinuousClock.now
            try store.pruneAudio(olderThan: AudioRetention.month.cutoff())
            pruneMs.append(Self.milliseconds(ContinuousClock.now - started))
        }
        let rows = count + 15
        let expected = try store.recent(limit: rows).reduce(0) { $0 + DictationPipeline.approximateWordCount($1.finalText) }
        XCTAssertEqual(words, expected)

        let result: [String: Any] = [
            "historyCount": rows,
            "pipelineSaveMedianMs": Self.median(saveMs), "pipelineSaveMaxMs": saveMs.max() ?? 0,
            "wordTotalMedianMs": Self.median(wordsMs), "wordTotalMaxMs": wordsMs.max() ?? 0,
            "fullPruneMedianMs": Self.median(pruneMs),
            "words": words,
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print("HISTORY_BENCHMARK " + String(decoding: json, as: UTF8.self))
        if let output = environment["AIRDRAFT_BENCHMARK_OUTPUT"] {
            try json.write(to: URL(fileURLWithPath: output))
        }
    }

    private func record(text: String, date: Date) -> DictationRecord {
        DictationRecord(createdAt: date, appBundleId: "com.example.editor", appName: "Editor", mode: "clean",
                        family: "document", rawTranscript: text, refinedText: text, finalText: text,
                        asrEngine: "benchmark", audioSeconds: 0.25, asrMs: 1, llmMs: 0, inserted: true)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
