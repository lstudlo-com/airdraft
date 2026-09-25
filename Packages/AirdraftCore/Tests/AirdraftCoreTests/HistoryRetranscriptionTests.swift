import XCTest
@testable import AirdraftCore

@MainActor
final class HistoryRetranscriptionTests: XCTestCase {
    func testRetranscriptionReturnsReviewWithoutInsertionOrDuplicateHistory() async throws {
        let fixture = try Fixture(speech: HistorySpeech([.success("New transcription")]))
        defer { fixture.cleanUp() }
        let original = try fixture.saveOriginal()

        fixture.pipeline.retranscribe(original)
        try await waitUntil("Retranscription finishes") { !fixture.pipeline.isBusy }

        XCTAssertEqual(fixture.pipeline.reviewOutcome?.raw, "New transcription")
        XCTAssertEqual(fixture.pipeline.reviewOutcome?.final, "New transcription")
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertTrue(fixture.probe.outcomes.isEmpty)
        XCTAssertEqual(try fixture.history.recent(), [original])
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)

        fixture.pipeline.dismissReview()
        XCTAssertNil(fixture.pipeline.reviewOutcome)
        XCTAssertEqual(fixture.pipeline.state, .idle)
    }

    func testRetryAfterSpeechFailureKeepsReviewOnlyDelivery() async throws {
        let fixture = try Fixture(speech: HistorySpeech([.failure, .success("Recovered transcription")]))
        defer { fixture.cleanUp() }
        let original = try fixture.saveOriginal()

        fixture.pipeline.retranscribe(original)
        try await waitUntil("Failed retranscription retains audio") { !fixture.pipeline.isBusy }
        XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
        XCTAssertNil(fixture.pipeline.reviewOutcome)
        XCTAssertEqual(fixture.probe.blockedRecordings, 0, "Review errors must stay in the review UI")

        fixture.pipeline.retryRecording()
        try await waitUntil("Retry finishes") { !fixture.pipeline.isBusy }

        XCTAssertEqual(fixture.pipeline.reviewOutcome?.final, "Recovered transcription")
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertTrue(fixture.probe.outcomes.isEmpty)
        XCTAssertEqual(try fixture.history.recent(), [original])
    }

    func testCancelledReviewCannotChangeNewRecordingWhenSpeechReturnsLate() async throws {
        let speech = HistorySpeech([.suspended("Late transcription")])
        let fixture = try Fixture(speech: speech)
        defer { fixture.cleanUp(); Task { await speech.release(call: 1) } }
        let original = try fixture.saveOriginal()

        fixture.pipeline.retranscribe(original)
        try await waitUntil("First ASR call starts") { await speech.callCount == 1 }
        fixture.pipeline.dismissReview()
        fixture.pipeline.startRecording()
        try await waitUntil("New recording starts") { fixture.pipeline.isRecording }

        await speech.release(call: 1)
        // Waiting on the same factory lease proves the old ASR operation has returned.
        try await fixture.factory.prepare(fixture.settings.asr)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(fixture.pipeline.state, .recording)
        XCTAssertTrue(fixture.recorder.isRecording)
        XCTAssertNil(fixture.pipeline.reviewOutcome)
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertEqual(try fixture.history.recent(), [original])
    }

    func testCancelledReviewCannotOverwriteNewReview() async throws {
        let speech = HistorySpeech([.suspended("Stale transcription"), .success("Current transcription")])
        let fixture = try Fixture(speech: speech)
        defer { fixture.cleanUp(); Task { await speech.release(call: 1) } }
        let original = try fixture.saveOriginal()

        fixture.pipeline.retranscribe(original)
        try await waitUntil("First ASR call starts") { await speech.callCount == 1 }
        fixture.pipeline.dismissReview()
        fixture.pipeline.retranscribe(original)
        await speech.release(call: 1)
        try await waitUntil("Replacement review finishes") {
            fixture.pipeline.reviewOutcome?.final == "Current transcription" && !fixture.pipeline.isBusy
        }

        XCTAssertEqual(fixture.pipeline.reviewOutcome?.raw, "Current transcription")
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertTrue(fixture.probe.outcomes.isEmpty)
        XCTAssertEqual(try fixture.history.recent(), [original])
    }

    func testSuccessfulDictationSavesAudioWhenRetentionEnabled() async throws {
        let fixture = try Fixture(speech: HistorySpeech([.success("Saved transcription")]))
        defer { fixture.cleanUp() }
        fixture.settings.audioRetention = .week
        fixture.pipeline.insertionEnabled = false

        fixture.pipeline.processSamples(Fixture.samples)
        try await waitUntil("Dictation and audio save finish") { !fixture.pipeline.isBusy }

        let records = try fixture.history.recent()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.finalText, "Saved transcription")
        XCTAssertFalse(record.inserted)
        XCTAssertNotNil(record.audioFilename)
        XCTAssertNotNil(fixture.history.audioURL(for: record))
        let samples = try fixture.history.audioSamples(for: record)
        XCTAssertEqual(samples.count, Fixture.samples.count)
        XCTAssertEqual(try XCTUnwrap(samples.first), 0.125, accuracy: 1.0 / 32767)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Saved transcription")
        XCTAssertEqual(fixture.probe.outcomes.count, 1)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertNil(fixture.pipeline.reviewOutcome)
        XCTAssertNil(fixture.pipeline.historyStorageError)
        XCTAssertNil(fixture.pipeline.audioStorageError)
    }

    func testSuccessfulDictationDoesNotSaveAudioByDefault() async throws {
        let fixture = try Fixture(speech: HistorySpeech([.success("Text only")]))
        defer { fixture.cleanUp() }
        XCTAssertEqual(fixture.settings.audioRetention, .off)
        fixture.pipeline.insertionEnabled = false

        fixture.pipeline.processSamples(Fixture.samples)
        try await waitUntil("Text-only dictation finishes") { !fixture.pipeline.isBusy }

        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.finalText, "Text only")
        XCTAssertNil(record.audioFilename)
        XCTAssertNil(fixture.history.audioURL(for: record))
        XCTAssertNil(fixture.pipeline.historyStorageError)
    }

    func testFailedAudioSaveRetainsSamplesForExplicitRetryWithoutDuplicates() async throws {
        let fixture = try Fixture(speech: HistorySpeech([.success("Pending transcription")]))
        defer { fixture.cleanUp() }
        fixture.settings.audioRetention = .week
        fixture.pipeline.insertionEnabled = false
        let blocker = fixture.directory.appendingPathComponent("Recordings")
        try Data("blocks the recordings directory".utf8).write(to: blocker)

        fixture.pipeline.processSamples(Fixture.samples)
        try await waitUntil("Failed audio save finishes") { !fixture.pipeline.isBusy }

        XCTAssertNotNil(fixture.pipeline.historyStorageError)
        XCTAssertEqual(try fixture.history.count(), 0)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Pending transcription")

        try FileManager.default.removeItem(at: blocker)
        await fixture.pipeline.retryHistorySave()

        XCTAssertNil(fixture.pipeline.historyStorageError)
        XCTAssertNil(fixture.pipeline.audioStorageError)
        let records = try fixture.history.recent()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.finalText, "Pending transcription")
        XCTAssertNotNil(record.audioFilename)
        let samples = try fixture.history.audioSamples(for: record)
        XCTAssertEqual(samples.count, Fixture.samples.count)
        XCTAssertTrue(zip(samples, Fixture.samples).allSatisfy { pair in abs(pair.0 - pair.1) <= 1.0 / 32767 })

        await fixture.pipeline.retryHistorySave()

        XCTAssertEqual(try fixture.history.recent(), [record])
        XCTAssertNil(fixture.pipeline.historyStorageError)
        XCTAssertEqual(try fixture.history.audioSamples(for: record), samples)
    }

    private func waitUntil(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                           condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(description + " timed out", file: file, line: line)
        throw WaitError.timedOut
    }

    private enum WaitError: Error { case timedOut }

    private final class Probe {
        var insertedTexts: [String] = []
        var outcomes: [DictationOutcome] = []
        var blockedRecordings = 0
    }

    @MainActor
    private struct Fixture {
        static let samples = [Float](repeating: 0.125, count: 16_000)
        let suite: String
        let directory: URL
        let settings: AppSettings
        let history: HistoryStore
        let factory: EngineFactory
        let recorder: HistoryTestRecorder
        let pipeline: DictationPipeline
        let probe: Probe

        init(speech: HistorySpeech) throws {
            suite = "airdraft.history-retranscription.\(UUID().uuidString)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet)
            settings.llm = LLMConfig(kind: .none)
            settings.useAppContext = false
            history = try HistoryStore(directory: directory)
            factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Tests must not read credentials")
                return nil
            }, transcriberBuilder: { _ in speech })
            recorder = HistoryTestRecorder()
            let probe = Probe()
            self.probe = probe
            pipeline = DictationPipeline(settings: settings,
                dictionary: DictionaryStore(directory: directory), profiles: ProfileStore(directory: directory),
                history: history, factory: factory, recorder: recorder,
                insertText: { text, _, _ in
                    probe.insertedTexts.append(text)
                    return InsertionResult(method: .accessibility, notice: nil)
                }, recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
            pipeline.onOutcome = { probe.outcomes.append($0) }
            pipeline.onRecordingBlocked = { probe.blockedRecordings += 1 }
        }

        func saveOriginal() throws -> DictationRecord {
            _ = try history.save(DictationRecord(
                appBundleId: "test.original", appName: "Original App", mode: "clean", family: "document",
                rawTranscript: "Original raw", refinedText: "Original refined", finalText: "Original final",
                asrEngine: "original-speech", audioSeconds: 1, asrMs: 10, llmMs: 20, inserted: true
            ), samples: Self.samples)
            return try XCTUnwrap(history.recent().first)
        }

        func cleanUp() {
            pipeline.cancel()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }
}

private final class HistoryTestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.125, count: 16_000) }
    func cancel() { isRecording = false }
}

private actor HistorySpeech: Transcriber {
    enum Response: Sendable {
        case success(String)
        case failure
        case suspended(String)
    }

    nonisolated let id = "history-test-speech"
    private let responses: [Response]
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var callCount = 0

    init(_ responses: [Response]) { self.responses = responses }
    func prepare() async throws {}

    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        callCount += 1
        guard callCount <= responses.count else {
            XCTFail("Unexpected speech call")
            throw TranscriberError.timedOut
        }
        let text: String
        switch responses[callCount - 1] {
        case .success(let value): text = value
        case .failure: throw TranscriberError.timedOut
        case .suspended(let value):
            let call = callCount
            // Deliberately ignores cancellation to exercise late provider results.
            await withCheckedContinuation { pending[call] = $0 }
            text = value
        }
        return Transcript(text: text, engine: id, latencyMs: 1)
    }

    func release(call: Int) { pending.removeValue(forKey: call)?.resume() }
}
