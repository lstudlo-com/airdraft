import XCTest
@testable import AirdraftCore

@MainActor
final class PipelinePreviewTests: XCTestCase {
    func testPreviewReceivesSameCapturedSamplesAsFinalSpeechEngine() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let preview = try XCTUnwrap(fixture.previews.sessions.first)
        let first = [Float](repeating: 0.125, count: 8_000)
        let second = [Float](repeating: -0.25, count: 8_000)

        fixture.recorder.capture(first)
        fixture.recorder.capture(second)
        preview.sendText("Temporary preview")
        try await waitUntil("Preview appears") { fixture.pipeline.previewText == "Temporary preview" }

        XCTAssertTrue(fixture.pipeline.previewEnabledForRecording)
        XCTAssertEqual(fixture.previews.locales, ["zh-TW"])
        XCTAssertEqual(preview.chunks, [first, second])
        XCTAssertEqual(try fixture.history.count(), 0)

        fixture.pipeline.stopAndProcess()
        try await waitUntil("Final transcription finishes") { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy }
        let received = await fixture.speech.receivedSamples
        XCTAssertEqual(received, [first + second])
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, FinalPreviewTestSpeech.finalText)
        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertEqual(preview.cancelCount, 1)
        XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.rawTranscript, FinalPreviewTestSpeech.finalText)
        XCTAssertEqual(record.refinedText, FinalPreviewTestSpeech.finalText)
        XCTAssertEqual(record.finalText, FinalPreviewTestSpeech.finalText)
    }

    func testDisablingPreviewKeepsRecordingAndFinalTranscription() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let preview = try XCTUnwrap(fixture.previews.sessions.first)
        fixture.recorder.capture(Fixture.samples)
        fixture.pipeline.disableLivePreview()
        preview.sendText("Late disabled preview")
        await drainCallbacks()
        XCTAssertTrue(fixture.pipeline.isRecording)
        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertEqual(preview.cancelCount, 1)
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        fixture.pipeline.stopAndProcess()
        try await waitUntil("Final speech finishes") { fixture.pipeline.lastOutcome != nil }
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, FinalPreviewTestSpeech.finalText)
    }

    func testCancelDetachesPreviewAndIgnoresItsLateCallbacks() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let preview = try XCTUnwrap(fixture.previews.sessions.first)
        fixture.recorder.capture(Fixture.samples)
        preview.sendText("Temporary preview")
        try await waitUntil("Preview appears") { !fixture.pipeline.previewText.isEmpty }

        fixture.pipeline.cancel()
        preview.sendText("Late cancelled text")
        preview.sendIssue("Late cancelled error")
        await drainCallbacks()

        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertEqual(preview.cancelCount, 1)
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertEqual(fixture.pipeline.state, .idle)
        XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        XCTAssertNil(fixture.pipeline.previewIssue)
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertEqual(try fixture.history.count(), 0)
        let received = await fixture.speech.receivedSamples
        XCTAssertTrue(received.isEmpty)
    }

    func testFinalTranscriptionDoesNotWaitForPreviewCompletion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let preview = try XCTUnwrap(fixture.previews.sessions.first)
        fixture.recorder.capture(Fixture.samples)

        // This fake only records cancellation. It never completes its preview work.
        fixture.pipeline.stopAndProcess()
        try await waitUntil("Final speech completes independently of preview") {
            fixture.pipeline.lastOutcome?.final == FinalPreviewTestSpeech.finalText && !fixture.pipeline.isBusy
        }
        preview.sendText("Preview still producing text after stop")
        preview.sendIssue("Preview still producing errors after stop")
        await drainCallbacks()

        XCTAssertEqual(preview.cancelCount, 1)
        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        XCTAssertNil(fixture.pipeline.previewIssue)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.raw, FinalPreviewTestSpeech.finalText)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testPreviousRecordingCallbacksCannotAffectNewRecordingPreview() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let previous = try XCTUnwrap(fixture.previews.sessions.first)
        fixture.pipeline.cancel()
        try await begin(fixture)
        let current = try XCTUnwrap(fixture.previews.sessions.last)
        XCTAssertFalse(previous === current)
        current.sendText("Current preview")
        try await waitUntil("Current preview appears") { fixture.pipeline.previewText == "Current preview" }

        previous.sendText("Stale preview")
        previous.sendIssue("Stale preview error")
        await drainCallbacks()

        XCTAssertTrue(fixture.pipeline.isRecording)
        XCTAssertTrue(fixture.pipeline.previewEnabledForRecording)
        XCTAssertEqual(fixture.pipeline.previewText, "Current preview")
        XCTAssertNil(fixture.pipeline.previewIssue)
        XCTAssertEqual(previous.cancelCount, 1)
        XCTAssertEqual(current.cancelCount, 0)
        fixture.recorder.capture(Fixture.samples)
        XCTAssertTrue(previous.chunks.isEmpty)
        XCTAssertEqual(current.chunks, [Fixture.samples])
    }

    func testPreviewFailureDoesNotChangeFinalTranscriptOrHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let preview = try XCTUnwrap(fixture.previews.sessions.first)
        fixture.recorder.capture(Fixture.samples)
        preview.sendText("Unreliable temporary words")
        try await waitUntil("Preview appears") { !fixture.pipeline.previewText.isEmpty }
        preview.sendIssue("Preview language assets are unavailable")
        try await waitUntil("Preview issue appears") { fixture.pipeline.previewIssue != nil }

        XCTAssertTrue(fixture.pipeline.isRecording)
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        XCTAssertNil(fixture.pipeline.lastIssue)
        fixture.pipeline.stopAndProcess()
        try await waitUntil("Final transcription survives preview failure") {
            fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy
        }

        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, FinalPreviewTestSpeech.finalText)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        let records = try fixture.history.recent()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.rawTranscript, FinalPreviewTestSpeech.finalText)
        XCTAssertEqual(record.refinedText, FinalPreviewTestSpeech.finalText)
        XCTAssertEqual(record.finalText, FinalPreviewTestSpeech.finalText)
        XCTAssertNil(record.error)
    }

    func testPreviewIsNotCreatedWhenDisabled() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.livePreviewEnabled = false
        try await begin(fixture)

        XCTAssertTrue(fixture.previews.sessions.isEmpty)
        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        XCTAssertNil(fixture.pipeline.previewIssue)
    }

    func testHiddenHUDNeverStartsSpeechPreview() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.hudStyle = .none
        try await begin(fixture)
        fixture.recorder.capture(Fixture.samples)

        XCTAssertTrue(fixture.previews.sessions.isEmpty)
        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
        fixture.pipeline.stopAndProcess()
        try await waitUntil("Final speech still finishes with hidden HUD") {
            fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy
        }
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, FinalPreviewTestSpeech.finalText)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testRecorderStartFailureCancelsPreviewAndDetachesSamples() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.recorder.failOnStart = true
        fixture.pipeline.startRecording()
        try await waitUntil("Recording start failure finishes") { !fixture.pipeline.isBusy }

        let preview = try XCTUnwrap(fixture.previews.sessions.first)
        XCTAssertEqual(preview.cancelCount, 1)
        XCTAssertNil(fixture.recorder.samplesHandler)
        XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
        XCTAssertEqual(try fixture.history.count(), 0)
    }

    private func begin(_ fixture: Fixture) async throws {
        fixture.pipeline.startRecording()
        try await waitUntil("Recording starts") { fixture.pipeline.isRecording }
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

    private func drainCallbacks() async {
        // Preview callbacks enter the pipeline through a main-actor task.
        for _ in 0..<20 { await Task.yield() }
    }

    private enum WaitError: Error { case timedOut }

    @MainActor
    private struct Fixture {
        static let samples = [Float](repeating: 0.125, count: 16_000)
        let suite: String
        let directory: URL
        let settings: AppSettings
        let history: HistoryStore
        let recorder: PreviewTestRecorder
        let previews: PreviewTestBuilder
        let speech: FinalPreviewTestSpeech
        let pipeline: DictationPipeline

        init() throws {
            suite = "airdraft.pipeline-preview.\(UUID().uuidString)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet)
            settings.llm = LLMConfig(kind: .none)
            settings.useAppContext = false
            settings.livePreviewEnabled = true
            settings.livePreviewLocale = "zh-TW"
            history = try HistoryStore(inMemory: true)
            recorder = PreviewTestRecorder()
            let previews = PreviewTestBuilder()
            self.previews = previews
            let speech = FinalPreviewTestSpeech()
            self.speech = speech
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Preview lifecycle tests must not read credentials")
                return nil
            }, transcriberBuilder: { _ in speech })
            pipeline = DictationPipeline(settings: settings,
                dictionary: DictionaryStore(directory: directory), profiles: ProfileStore(directory: directory),
                history: history, factory: factory, recorder: recorder,
                previewBuilder: { previews.build(locale: $0, onText: $1, onIssue: $2) },
                recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
            pipeline.insertionEnabled = false
        }

        func cleanUp() {
            pipeline.cancel()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }
}

private final class PreviewTestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var failOnStart = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var samplesHandler: (@Sendable ([Float]) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    private var samples: [Float] = []

    func start(microphone: MicrophonePreference) throws {
        if failOnStart { throw CocoaError(.fileReadUnknown) }
        samples = []
        isRecording = true
    }

    func capture(_ chunk: [Float]) {
        guard isRecording else { return }
        samples.append(contentsOf: chunk)
        samplesHandler?(chunk)
    }

    func stop() -> [Float] { isRecording = false; return samples }
    func cancel() { isRecording = false; samples = [] }
}

private final class PreviewTestBuilder: @unchecked Sendable {
    private let lock = NSLock()
    private var builtSessions: [PreviewTestSession] = []
    private var builtLocales: [String] = []
    var sessions: [PreviewTestSession] { lock.withLock { builtSessions } }
    var locales: [String] { lock.withLock { builtLocales } }

    func build(locale: String, onText: @escaping @Sendable (String) -> Void,
               onIssue: @escaping @Sendable (String) -> Void) -> PreviewTestSession {
        let session = PreviewTestSession(onText: onText, onIssue: onIssue)
        lock.withLock {
            builtSessions.append(session)
            builtLocales.append(locale)
        }
        return session
    }
}

private final class PreviewTestSession: SpeechPreviewSession, @unchecked Sendable {
    private let lock = NSLock()
    private var appendedChunks: [[Float]] = []
    private var cancellations = 0
    private let onText: @Sendable (String) -> Void
    private let onIssue: @Sendable (String) -> Void
    var chunks: [[Float]] { lock.withLock { appendedChunks } }
    var cancelCount: Int { lock.withLock { cancellations } }

    init(onText: @escaping @Sendable (String) -> Void, onIssue: @escaping @Sendable (String) -> Void) {
        self.onText = onText
        self.onIssue = onIssue
    }

    func append(_ samples: [Float]) { lock.withLock { appendedChunks.append(samples) } }
    func cancel() { lock.withLock { cancellations += 1 } }
    // Deliberately remain callable after cancel to model late framework callbacks.
    func sendText(_ text: String) { onText(text) }
    func sendIssue(_ issue: String) { onIssue(issue) }
}

private actor FinalPreviewTestSpeech: Transcriber {
    nonisolated static let finalText = "Final speech engine output"
    nonisolated let id = "preview-test-final-speech"
    private(set) var receivedSamples: [[Float]] = []
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        receivedSamples.append(samples)
        return Transcript(text: Self.finalText, engine: id, latencyMs: 1)
    }
}
