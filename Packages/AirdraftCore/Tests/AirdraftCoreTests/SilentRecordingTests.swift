import XCTest
@testable import AirdraftCore

@MainActor
final class SilentRecordingTests: XCTestCase {
    /// Silence, including a quiet room's noise floor, never loads, recognizes,
    /// delivers or saves (AD-143); quiet speech and a single short word still do.
    func testDigitalSilenceIsDroppedButQuietNonzeroAudioReachesRecognizer() async throws {
        let roomNoise = (0..<48_000).map { Float($0 % 2 == 0 ? 0.001 : -0.001) }
        var clickInRoom = roomNoise
        for index in 8_000..<9_600 { clickInRoom[index] = 0.3 }
        for destination in [TextOutputDestination.cursor, .script] {
            let fixture = try Fixture(destination: destination)
            defer { fixture.cleanup() }
            for samples in [[], [Float](repeating: 0, count: 48_000), [Float](repeating: -0.0, count: 16_000),
                            roomNoise, clickInRoom] {
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

        var shortWord = roomNoise
        for index in 16_000..<19_200 { shortWord[index] = 0.1 }
        // -42 dBFS quiet speech, and a 0.2 s word in an otherwise silent recording.
        for (index, samples) in [[Float](repeating: 0.008, count: 16_000), shortWord].enumerated() {
            let fixture = try Fixture(destination: .cursor)
            defer { fixture.cleanup() }
            fixture.pipeline.processSamples(samples)
            await settle(fixture.pipeline)
            XCTAssertEqual(fixture.pipeline.lastOutcome?.raw, "Quiet speech", "case \(index)")
            XCTAssertEqual(fixture.engineBuilds.value, 1)
            XCTAssertEqual(try fixture.history.recent().count, 1)
        }
    }

    private func settle(_ pipeline: DictationPipeline) async {
        for _ in 0..<200 where pipeline.isBusy || pipeline.isFinishingDelivery { try? await Task.sleep(for: .milliseconds(5)) }
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
            do {
                try history.close()
                try FileManager.default.removeItem(at: directory)
            } catch {
                XCTFail("Could not clean up silent-recording fixture: \(error)")
            }
        }
    }
}

private final class SilenceCounter: Sendable {
    private let count = Locked(0)
    var value: Int { count.value }
    func increment() { count.withLock { $0 += 1 } }
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
