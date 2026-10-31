import Foundation
import XCTest
@testable import AirdraftCore

/// The iOS flow keeps the macOS pipeline's processing contracts (AD-141):
/// refinement is best effort, fidelity rejections keep the raw transcript and
/// the dictionary has the last word.
final class MobileDictationTests: XCTestCase {
    @MainActor func testProcessingFallsBackToRawTextAndAppliesDictionaryLast() async throws {
        let dictionary = [DictionaryEntry(term: "Airdraft", aliases: ["air draft"])]
        let speech = "i use air draft every single day"

        do { // RefinedTextGetsDictionaryCorrection
            let fixture = Fixture(speech: speech, reply: { _ in "I use air draft every single day." })
            let result = try await XCTUnwrapAsync(await fixture.process(dictionary: dictionary))
            XCTAssertEqual(result.refined, "I use air draft every single day.")
            XCTAssertEqual(result.final, "I use Airdraft every single day.")
            XCTAssertEqual(result.llmEngine, "fake-refiner")
            XCTAssertNil(result.refinementError)
            XCTAssertEqual(fixture.requests.withLock { $0.map(\.transcript) }, [speech])
        }

        do { // RefinerErrorKeepsRawTranscript
            let fixture = Fixture(speech: speech, reply: { _ in throw URLError(.timedOut) })
            let result = try await XCTUnwrapAsync(await fixture.process(dictionary: dictionary))
            XCTAssertEqual(result.refined, speech)
            XCTAssertEqual(result.final, "i use Airdraft every single day")
            XCTAssertNotNil(result.refinementError)
            XCTAssertFalse(result.refinementRejected)
        }

        do { // OutputInAnotherScriptIsRejected
            let fixture = Fixture(speech: speech, reply: { _ in "私は毎日エアドラフトを使います。" })
            let result = try await XCTUnwrapAsync(await fixture.process(dictionary: dictionary))
            XCTAssertTrue(result.refinementRejected)
            XCTAssertEqual(result.final, "i use Airdraft every single day")
        }

        do { // VerbatimNeverCallsTheRefiner
            let fixture = Fixture(speech: speech, reply: { _ in "changed" })
            let result = try await XCTUnwrapAsync(await fixture.process(dictionary: [], profileID: RefinementProfile.verbatimID))
            XCTAssertEqual(result.final, speech)
            XCTAssertTrue(fixture.requests.withLock { $0.isEmpty })
        }

        do { // ShortUtteranceSkipsRefinement
            let fixture = Fixture(speech: "hello", reply: { _ in "Hello!" })
            let result = try await XCTUnwrapAsync(await fixture.process(dictionary: []))
            XCTAssertEqual(result.final, "hello")
            XCTAssertTrue(fixture.requests.withLock { $0.isEmpty })
        }

        do { // DigitalSilenceProducesNothing
            let fixture = Fixture(speech: speech, reply: { _ in "x" })
            let result = try await fixture.process(dictionary: [], samples: [Float](repeating: 0, count: 16_000))
            XCTAssertNil(result)
            XCTAssertEqual(fixture.speechCalls.withLock { $0 }, 0)
        }
    }

    @MainActor func testRecordingChecksSetupThenSavesDeliveredTextToHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mobile-dictation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "airdraft.mobile-dictation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.asr = ASRConfig(kind: .apple)
        settings.llm = LLMConfig(kind: .none)
        let history = try HistoryStore(directory: root)
        let recorder = FixtureRecorder()
        let microphoneAllowed = Locked(false)
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil },
                                    transcriberBuilder: { config in FixtureSpeech(id: config.engineID, text: "notes for the meeting", calls: Locked(0)) })
        let dictation = MobileDictation(settings: settings, profiles: ProfileStore(directory: root),
                                        dictionary: DictionaryStore(directory: root), factory: factory,
                                        history: history, recorder: recorder, environment: {
            RecordingPrerequisites.Environment(
                microphoneAuthorized: microphoneAllowed.withLock { $0 }, accessibilityAuthorized: false,
                devices: [Microphone(id: 1, uid: "fixture", name: "Fixture")], defaultDeviceID: 1,
                readCredential: { _ in nil }, installed: { _ in true }, appleIntelligenceUnavailable: { nil })
        })

        do { // MissingMicrophonePermissionNeverOpensTheInput
            XCTAssertThrowsError(try dictation.start())
            XCTAssertNotNil(dictation.readinessIssue())
            XCTAssertFalse(recorder.isRecording)
            XCTAssertEqual(dictation.phase, .idle)
        }

        do { // AcceptedRecordingIsProcessedAndRecorded
            microphoneAllowed.withLock { $0 = true }
            XCTAssertNil(dictation.readinessIssue())
            try dictation.start()
            XCTAssertEqual(dictation.phase, .recording)
            XCTAssertThrowsError(try dictation.start())
            let result = try await XCTUnwrapAsync(await dictation.stop())
            XCTAssertEqual(result.final, "notes for the meeting")
            XCTAssertEqual(dictation.phase, .idle)
            let saved = try XCTUnwrap(dictation.record(result, delivery: .copied))
            XCTAssertEqual(saved.outputDestination, DictationRecord.copyDestination)
            XCTAssertEqual(saved.deliveryStatus, .delivered)
            XCTAssertEqual(try history.recent(limit: 5).map(\.finalText), ["notes for the meeting"])
        }

        do { // CancelDiscardsTheCapture
            try dictation.start()
            dictation.cancel()
            XCTAssertFalse(recorder.isRecording)
            let none = await dictation.stop()
            XCTAssertNil(none)
        }
    }
}

// MARK: - Fixtures

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}

private struct FixtureSpeech: Transcriber {
    let id: String
    let text: String
    let calls: Locked<Int>
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        calls.withLock { $0 += 1 }
        return Transcript(text: text, language: "en", engine: id, latencyMs: 1)
    }
}

private struct FixtureRefiner: Refiner {
    let id = "fake-refiner"
    let requests: Locked<[RefineRequest]>
    let reply: @Sendable (String) throws -> String
    func prewarmPrompt(_ request: RefineRequest, backend: RefinementPreparationBackend) async throws {}
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        requests.withLock { $0.append(request) }
        return RefineResult(text: try reply(request.transcript), engine: id, latencyMs: 1, promptVersion: "test")
    }
}

@MainActor
private struct Fixture {
    let requests = Locked<[RefineRequest]>([])
    let speechCalls = Locked(0)
    let factory: EngineFactory

    init(speech: String, reply: @escaping @Sendable (String) throws -> String) {
        let requests = self.requests
        let calls = self.speechCalls
        factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil },
                                transcriberBuilder: { config in FixtureSpeech(id: config.engineID, text: speech, calls: calls) },
                                refinerBuilder: { _ in FixtureRefiner(requests: requests, reply: reply) })
    }

    func process(dictionary: [DictionaryEntry], profileID: UUID = RefinementProfile.cleanID,
                 samples: [Float] = [Float](repeating: 0.1, count: 16_000)) async throws -> MobileDictationResult? {
        let profile = try XCTUnwrap(RefinementProfile.defaults.first { $0.id == profileID })
        let snapshot = MobileDictationSnapshot(asr: ASRConfig(kind: .apple), profile: profile,
                                               llm: LLMConfig(kind: .openAI), baseRules: PromptBuilder.defaultBaseRules,
                                               dictionary: dictionary)
        return try await MobileDictation.process(samples: samples, snapshot: snapshot, factory: factory)
    }
}

/// Unchecked: driven only by the MainActor flow under test.
private final class FixtureRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.1, count: 16_000) }
    func cancel() { isRecording = false }
}
