import XCTest
@testable import AirdraftCore

@MainActor
final class PipelineSafetyTests: XCTestCase {
    private func fixture(delay: Double = 0) -> (DictationPipeline, TestRecorder, URL, String) {
        let suite = "airdraft.safety.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .groq)
        settings.llm = LLMConfig(kind: .none)
        let recorder = TestRecorder()
        let factory = EngineFactory(status: EngineStatus(), transcriberBuilder: { _ in SlowSpeech(delay: delay) })
        let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: ProfileStore(directory: directory), history: nil, factory: factory,
            recorder: recorder, recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
        pipeline.insertionEnabled = false
        return (pipeline, recorder, directory, suite)
    }

    private func cleanup(_ directory: URL, _ suite: String) {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func begin(_ pipeline: DictationPipeline) async throws {
        pipeline.startRecording()
        for _ in 0..<100 where !pipeline.isRecording { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(pipeline.isRecording)
    }

    func testOldReleaseDoesNotStopNewRecording() async throws {
        let (pipeline, recorder, directory, suite) = fixture()
        defer { pipeline.cancel(); cleanup(directory, suite) }
        try await begin(pipeline)
        pipeline.stopAndProcess()
        pipeline.cancel()
        try await begin(pipeline)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(pipeline.state, .recording)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNil(pipeline.lastOutcome)
    }

    func testLateCancelledASRDoesNotResetNewRecording() async throws {
        let (pipeline, recorder, directory, suite) = fixture(delay: 0.25)
        defer { pipeline.cancel(); cleanup(directory, suite) }
        pipeline.processSamples([Float](repeating: 0.1, count: 16000))
        try await Task.sleep(for: .milliseconds(30))
        pipeline.cancel()
        try await begin(pipeline)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(pipeline.state, .recording)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertNil(pipeline.lastOutcome)
    }

    func testFailedRecordingCanRetryAfterProviderRecovery() async throws {
        let suite = "airdraft.recovery.\(UUID().uuidString)"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { cleanup(dir, suite) }
        let engine = RecoveringSpeech()
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .groq)
        settings.llm = LLMConfig(kind: .none)
        let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: dir),
            profiles: ProfileStore(directory: dir), history: nil,
            factory: EngineFactory(status: EngineStatus(), transcriberBuilder: { _ in engine }))
        pipeline.insertionEnabled = false
        pipeline.processSamples([Float](repeating: 0.1, count: 16000))
        for _ in 0..<100 where pipeline.isBusy { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(pipeline.hasRecoverableRecording)
        XCTAssertNotNil(pipeline.lastIssue)
        await engine.recover()
        pipeline.retryRecording()
        for _ in 0..<100 where pipeline.isBusy { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(pipeline.lastOutcome?.raw, "Recovered words")
        XCTAssertFalse(pipeline.hasRecoverableRecording)
    }

    func testStaleMicrophoneCallbackCannotCancelNewRecording() async throws {
        let (pipeline, recorder, directory, suite) = fixture()
        defer { pipeline.cancel(); cleanup(directory, suite) }
        try await begin(pipeline)
        let oldInterruption = recorder.interruptionHandler
        let oldLevel = recorder.levelHandler
        pipeline.cancel()
        try await begin(pipeline)
        oldInterruption?(.inputChanged)
        oldLevel?(0.9)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(pipeline.isRecording)
        XCTAssertTrue(pipeline.levelHistory.isEmpty)
        XCTAssertNil(pipeline.lastIssue)
    }

    func testReplacementVerificationUsesContentsAndUTF16Range() {
        XCTAssertEqual(TextInserter.replacing("cat", range: CFRange(location: 0, length: 3), with: "dog"), "dog")
        XCTAssertEqual(TextInserter.replacing("a😀b", range: CFRange(location: 1, length: 2), with: "x"), "axb")
        XCTAssertNil(TextInserter.replacing("cat", range: CFRange(location: 2, length: 10), with: "dog"))
    }

    func testDeadlineReturnsWithoutWaitingForUncooperativeWork() async throws {
        let start = Date()
        do {
            let _: String = try await OperationDeadline.run(seconds: 0.04) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { continuation.resume(returning: "late") }
                }
            }
            XCTFail("Expected deadline")
        } catch RefinerError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
    }

    func testCancelledCLIIsNeverLaunched() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
            process.arguments = [marker.path]
            return try await CLIProcess.run(process, input: "", timeout: 2)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testIncompleteCompletionReasonsFailClosed() throws {
        for reason in [nil, "length", "max_tokens", "MAX_TOKENS", "refusal", "content_filter", "tool_calls"] as [String?] {
            XCTAssertThrowsError(try CompletionReason.validate(reason, allowed: ["stop", "STOP", "end_turn"]))
        }
        try CompletionReason.validate("stop", allowed: ["stop"])
    }
}

private final class TestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.1, count: 16000) }
    func cancel() { isRecording = false }
}

private struct SlowSpeech: Transcriber {
    let delay: Double
    let id = "test-speech"
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                continuation.resume(returning: Transcript(text: "Complete transcript", engine: id, latencyMs: 0))
            }
        }
    }
}

private actor RecoveringSpeech: Transcriber {
    nonisolated let id = "recovering"
    private var failing = true
    func recover() { failing = false }
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        if failing { throw TranscriberError.timedOut }
        return Transcript(text: "Recovered words", engine: id, latencyMs: 0)
    }
}
