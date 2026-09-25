import XCTest
@testable import AirdraftCore

@MainActor
final class SilentRecordingTests: XCTestCase {
    func testDigitalSilenceNeverLoadsRecognizesDeliversOrSaves() async throws {
        for destination in [TextOutputDestination.cursor, .script] {
            let fixture = try Fixture(destination: destination)
            defer { fixture.cleanup() }
            for samples in [[], [Float](repeating: 0, count: 48_000), [Float](repeating: -0.0, count: 16_000)] {
                fixture.pipeline.processSamples(samples)
                await settle(fixture.pipeline)
                XCTAssertEqual(fixture.pipeline.state, .idle)
                XCTAssertNil(fixture.pipeline.lastOutcome)
                XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
                XCTAssertEqual(fixture.engineBuilds.value, 0)
                XCTAssertEqual(fixture.deliveries.value, 0)
                XCTAssertTrue(try fixture.history.recent().isEmpty)
            }
        }
    }

    func testQuietNonzeroAudioStillReachesRecognizer() async throws {
        let fixture = try Fixture(destination: .cursor)
        defer { fixture.cleanup() }
        fixture.pipeline.processSamples([Float](repeating: 0.00000001, count: 16_000))
        await settle(fixture.pipeline)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.raw, "Quiet speech")
        XCTAssertEqual(fixture.engineBuilds.value, 1)
        XCTAssertEqual(try fixture.history.recent().count, 1)
    }

    private func settle(_ pipeline: DictationPipeline) async {
        for _ in 0..<200 where pipeline.isBusy { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(pipeline.isBusy)
    }

    @MainActor private final class Fixture {
        let suite = "airdraft.silent.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history: HistoryStore
        var pipeline: DictationPipeline!
        let engineBuilds = SilenceCounter()
        let deliveries = SilenceCounter()

        init(destination: TextOutputDestination) throws {
            history = try HistoryStore(directory: directory)
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet)
            settings.llm.select(.none)
            settings.useAppContext = false
            settings.outputDestination = destination
            settings.audioRetention = .forever
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Silent recording tests must not read credentials")
                return nil
            }, transcriberBuilder: { [engineBuilds] _ in
                engineBuilds.increment()
                return QuietSpeech()
            })
            pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
                profiles: ProfileStore(directory: directory), history: history, factory: factory,
                insertText: { [deliveries] _, _, _ in
                    deliveries.increment()
                    return InsertionResult(method: .accessibility, notice: nil)
                }, sendScript: { [deliveries] _, _ in deliveries.increment() })
        }

        func cleanup() {
            pipeline.cancel()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

private final class SilenceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}

private actor QuietSpeech: Transcriber {
    nonisolated let id = "quiet-fixture"
    func isReady() -> Bool { true }
    func prepare() {}
    func unload() {}
    func transcribe(samples: [Float], hints: TranscriptionHints) -> Transcript {
        Transcript(text: "Quiet speech", engine: id, latencyMs: 0)
    }
}
