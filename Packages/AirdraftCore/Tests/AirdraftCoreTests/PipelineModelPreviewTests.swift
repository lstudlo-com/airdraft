import XCTest
@testable import AirdraftCore

/// AD-084: the recording's own local model as live-preview source. Preview text
/// stays display-only and the final transcript is identical with preview on or off.
@MainActor
final class PipelineModelPreviewTests: XCTestCase {
    /// The model source uses the recording's config and hints, an Apple Speech model uses
    /// the Apple analyzer in its own locale, the Apple source keeps its builder, and the
    /// source setting persists with Apple Speech as the default.
    func testPreviewSourceRoutesToModelOrAppleAnalyzerAndPersists() async throws {
        do { // SelectedModelSourceUsesRecordingConfigAndHints
            let fixture = try Fixture(source: .speechModel)
            defer { fixture.cleanUp() }
            fixture.dictionary.add(DictionaryEntry(term: "Airdraft"))
            try await begin(fixture)
            let preview = try XCTUnwrap(fixture.builds.sessions.first)
            let request = try XCTUnwrap(fixture.builds.requests.first)
            XCTAssertEqual(request.asr, fixture.settings.asr)
            XCTAssertEqual(request.hints.vocabulary, ["Airdraft"])
            XCTAssertTrue(fixture.apple.sessions.isEmpty, "Apple Speech does not run for the model source")

            let chunk = [Float](repeating: 0.2, count: 8_000)
            fixture.recorder.capture(chunk)
            fixture.recorder.capture(chunk)
            XCTAssertEqual(preview.chunks, [chunk, chunk])
            preview.sendText("Provisional model text")
            try await waitUntil { fixture.pipeline.previewText == "Provisional model text" }

            fixture.pipeline.stopAndProcess()
            try await waitUntil { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertEqual(preview.cancelCount, 1)
            XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
            let received = await fixture.speech.receivedSamples
            XCTAssertEqual(received, [chunk + chunk])
            let finalHints = await fixture.speech.receivedVocabulary
            XCTAssertEqual(finalHints, [request.hints.vocabulary], "Preview and final share the same captured hints")
            let record = try XCTUnwrap(fixture.history.recent().first)
            XCTAssertEqual(record.rawTranscript, ModelPreviewTestSpeech.text(for: 16_000))
            XCTAssertFalse(record.finalText.contains("Provisional"), "Preview text never reaches history")
        }

        // The selected model is Apple Speech: the model source runs the Apple
        // analyzer in that model's locale, not the separate preview language.
        do { // AppleSpeechModelSourceUsesAppleAnalyzerInModelLocale
            let fixture = try Fixture(source: .speechModel)
            defer { fixture.cleanUp() }
            fixture.settings.asr = ASRConfig(kind: .apple, appleLocale: "ja-JP", language: "")
            fixture.settings.livePreviewLocale = "en-US"
            try await begin(fixture)
            XCTAssertEqual(fixture.appleLocales.value, ["ja-JP"])
            XCTAssertTrue(fixture.builds.sessions.isEmpty, "No model decode runs for Apple Speech")
            XCTAssertNil(fixture.pipeline.previewIssue)
            let preview = try XCTUnwrap(fixture.apple.sessions.first)
            let chunk = [Float](repeating: 0.2, count: 8_000)
            fixture.recorder.capture(chunk)
            XCTAssertEqual(preview.chunks, [chunk])
            preview.sendText("Apple provisional text")
            try await waitUntil { fixture.pipeline.previewText == "Apple provisional text" }
            fixture.pipeline.stopAndProcess()
            try await waitUntil { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertEqual(fixture.pipeline.lastOutcome?.raw, ModelPreviewTestSpeech.text(for: 8_000))
        }

        do { // AppleSourceStillUsesAppleSpeechBuilder
            let fixture = try Fixture(source: .appleSpeech)
            defer { fixture.cleanUp() }
            try await begin(fixture)
            XCTAssertEqual(fixture.apple.sessions.count, 1)
            XCTAssertTrue(fixture.builds.sessions.isEmpty)
        }

        do { // SourceSettingPersistsAndDefaultsToAppleSpeech
            let suite = "airdraft.model-preview-setting.\(UUID().uuidString)"
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            let defaults = UserDefaults(suiteName: suite)!
            XCTAssertEqual(AppSettings(defaults: defaults).livePreviewSource, .appleSpeech)
            AppSettings(defaults: defaults).livePreviewSource = .speechModel
            XCTAssertEqual(AppSettings(defaults: defaults).livePreviewSource, .speechModel)
            defaults.set(Data("\"unknown\"".utf8), forKey: "settings.livePreviewSource")
            XCTAssertEqual(AppSettings(defaults: defaults).livePreviewSource, .appleSpeech)
        }
    }

    func testUnavailableModelOpensNoPreviewAndNoticeShowsOncePerProfileAndModel() async throws {
        do { // UnavailableModelOpensNoPreviewAndRecordingContinues
            let fixture = try Fixture(source: .speechModel, availability: { _ in "Live text is unavailable for this model." })
            defer { fixture.cleanUp() }
            try await begin(fixture)
            XCTAssertTrue(fixture.builds.sessions.isEmpty)
            XCTAssertNil(fixture.recorder.samplesHandler)
            // The HUD keeps the live-text window closed and shows the reason briefly.
            XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)
            XCTAssertEqual(fixture.pipeline.previewIssue, "Live text is unavailable for this model.")
            fixture.recorder.capture([Float](repeating: 0.2, count: 16_000))
            fixture.pipeline.stopAndProcess()
            try await waitUntil { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy }
            XCTAssertEqual(fixture.pipeline.lastOutcome?.raw, ModelPreviewTestSpeech.text(for: 16_000))
            XCTAssertNil(fixture.pipeline.previewIssue)
        }

        // The notice is said once per profile and model: repeating the same setup
        // stays quiet, while another profile, another model, or a recording that
        // had live text in between brings it back.
        do { // UnavailableNoticeShowsOncePerProfileAndModel
            let unavailable = Locked(true)
            let fixture = try Fixture(source: .speechModel, availability: { asr in
                unavailable.withLock { $0 } ? "\(asr.engineID) has no live text" : nil
            })
            defer { fixture.cleanUp() }
            let parakeet = "\(fixture.settings.asr.engineID) has no live text"
            let first = try await recordedIssue(fixture)
            XCTAssertEqual(first, parakeet)
            let repeated = try await recordedIssue(fixture)
            XCTAssertNil(repeated, "Same profile and model: no second notice")
            XCTAssertFalse(fixture.pipeline.previewEnabledForRecording)

            let other = try XCTUnwrap(fixture.profiles.profiles.first { $0.id != fixture.profiles.activeProfileID })
            fixture.profiles.setActive(other.id)
            let otherProfile = try await recordedIssue(fixture)
            XCTAssertEqual(otherProfile, parakeet)

            fixture.settings.asr = ASRConfig(kind: .senseVoiceMultilingual)
            let otherModel = try await recordedIssue(fixture)
            XCTAssertEqual(otherModel, "\(fixture.settings.asr.engineID) has no live text")

            unavailable.withLock { $0 = false }
            let previewed = try await recordedIssue(fixture)
            XCTAssertNil(previewed)
            unavailable.withLock { $0 = true }
            let again = try await recordedIssue(fixture)
            XCTAssertEqual(again, "\(fixture.settings.asr.engineID) has no live text")
        }
    }

    /// Records once and returns the notice the HUD had while recording.
    private func recordedIssue(_ fixture: Fixture) async throws -> String? {
        try await begin(fixture)
        let issue = fixture.pipeline.previewIssue
        fixture.recorder.capture([Float](repeating: 0.2, count: 16_000))
        fixture.pipeline.stopAndProcess()
        try await waitUntil { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        return issue
    }

    func testStaleSessionTextIsRejectedByTheNextRecording() async throws {
        let fixture = try Fixture(source: .speechModel)
        defer { fixture.cleanUp() }
        try await begin(fixture)
        let old = try XCTUnwrap(fixture.builds.sessions.first)
        fixture.pipeline.cancel()
        try await begin(fixture)
        let current = try XCTUnwrap(fixture.builds.sessions.last)
        XCTAssertFalse(old === current)
        XCTAssertEqual(old.cancelCount, 1)
        old.sendText("Old session text")
        old.sendIssue("Old session issue")
        await drainCallbacks()
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        XCTAssertNil(fixture.pipeline.previewIssue)
        current.sendText("Current session text")
        try await waitUntil { fixture.pipeline.previewText == "Current session text" }
        // Release quiesces model preview at once: decodes stop during the release
        // grace, the last text stays, and late text never replaces it.
        fixture.recorder.capture([Float](repeating: 0.1, count: 16_000))
        fixture.pipeline.stopAndProcess()
        XCTAssertEqual(current.cancelCount, 1, "Model preview stops at release, before final inference")
        current.sendText("Late after stop")
        await drainCallbacks()
        XCTAssertTrue(fixture.pipeline.isRecording, "The release grace is still recording")
        XCTAssertEqual(fixture.pipeline.previewText, "Current session text")
        try await waitUntil { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        XCTAssertEqual(current.cancelCount, 1)
        await drainCallbacks()
        XCTAssertTrue(fixture.pipeline.previewText.isEmpty)
        XCTAssertNotEqual(fixture.pipeline.lastOutcome?.final, "Late after stop")
    }

    func testFinalTranscriptIsIdenticalWithProductionPreviewOnAndOff() async throws {
        let audio = (0..<48_000).map { Float(sin(Double($0) * 0.02)) * 0.25 }
        var finals: [String] = []
        var previewDecodes: [Int] = []
        for enabled in [false, true] {
            let fixture = try Fixture(source: .speechModel, production: true)
            defer { fixture.cleanUp() }
            fixture.settings.livePreviewEnabled = enabled
            try await begin(fixture)
            for offset in stride(from: 0, to: audio.count, by: 1_600) {
                fixture.recorder.capture(Array(audio[offset..<(offset + 1_600)]))
                try await Task.sleep(for: .milliseconds(25))
            }
            if enabled {
                // The production session decodes with the same fake engine through the factory lease.
                try await waitUntil(seconds: 5) { !fixture.pipeline.previewText.isEmpty }
            }
            fixture.pipeline.stopAndProcess()
            try await waitUntil(seconds: 5) { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            finals.append(try XCTUnwrap(fixture.pipeline.lastOutcome?.final))
            let received = await fixture.speech.receivedSamples
            previewDecodes.append(received.count - 1)
            XCTAssertEqual(received.last, audio, "Final inference always receives the complete capture")
        }
        XCTAssertEqual(finals[0], finals[1])
        XCTAssertEqual(previewDecodes[0], 0)
        XCTAssertGreaterThan(previewDecodes[1], 0)
    }

    // MARK: - Helpers

    private func begin(_ fixture: Fixture) async throws {
        fixture.pipeline.startRecording()
        try await waitUntil { fixture.pipeline.isRecording }
    }

    private func waitUntil(seconds: Double = 3, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out", file: file, line: line)
        throw CancellationError()
    }

    private func drainCallbacks() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @MainActor
    private struct Fixture {
        let suite: String
        let directory: URL
        let settings: AppSettings
        let dictionary: DictionaryStore
        let history: HistoryStore
        let recorder: ModelPreviewTestRecorder
        let builds: ModelPreviewTestBuilder
        let apple: ModelPreviewTestBuilder
        let appleLocales = Locked<[String]>([])
        let speech: ModelPreviewTestSpeech
        let profiles: ProfileStore
        let pipeline: DictationPipeline

        init(source: LivePreviewSource, production: Bool = false,
             availability: @escaping @Sendable (ASRConfig) -> String? = { _ in nil }) throws {
            suite = "airdraft.pipeline-model-preview.\(UUID().uuidString)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet)
            settings.llm = LLMConfig(kind: .none)
            settings.useAppContext = false
            settings.livePreviewEnabled = true
            settings.livePreviewSource = source
            dictionary = DictionaryStore(directory: directory)
            history = try HistoryStore(inMemory: true)
            recorder = ModelPreviewTestRecorder()
            let builds = ModelPreviewTestBuilder()
            let apple = ModelPreviewTestBuilder()
            self.builds = builds
            self.apple = apple
            let speech = ModelPreviewTestSpeech()
            self.speech = speech
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Model preview tests must not read credentials")
                return nil
            }, transcriberBuilder: { _ in speech })
            let appleLocales = self.appleLocales
            let applePreview: DictationPipeline.PreviewBuilder = { locale, onText, onIssue in
                appleLocales.withLock { $0.append(locale) }
                return apple.build(request: nil, onText: onText, onIssue: onIssue)
            }
            let fakeModelPreview: DictationPipeline.ModelPreviewBuilder = { request, onText, onIssue in
                builds.build(request: request, onText: onText, onIssue: onIssue)
            }
            profiles = ProfileStore(directory: directory)
            pipeline = DictationPipeline(settings: settings, dictionary: dictionary,
                profiles: profiles, history: history, factory: factory, recorder: recorder,
                previewBuilder: applePreview,
                modelPreviewBuilder: production ? nil : fakeModelPreview,
                modelPreviewAvailability: availability,
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

/// Unchecked: driven only by the MainActor pipeline under test.
private final class ModelPreviewTestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var samplesHandler: (@Sendable ([Float]) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    private var samples: [Float] = []

    func start(microphone: MicrophonePreference) throws {
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

private final class ModelPreviewTestBuilder: Sendable {
    private let built = Locked((sessions: [ModelPreviewTestSession](), requests: [ModelPreviewRequest]()))
    var sessions: [ModelPreviewTestSession] { built.value.sessions }
    var requests: [ModelPreviewRequest] { built.value.requests }

    func build(request: ModelPreviewRequest?, onText: @escaping @Sendable (String) -> Void,
               onIssue: @escaping @Sendable (String) -> Void) -> ModelPreviewTestSession {
        let session = ModelPreviewTestSession(onText: onText, onIssue: onIssue)
        built.withLock {
            $0.sessions.append(session)
            if let request { $0.requests.append(request) }
        }
        return session
    }
}

private final class ModelPreviewTestSession: SpeechPreviewSession, Sendable {
    private let appended = Locked<[[Float]]>([])
    private let cancellations = Locked(0)
    private let onText: @Sendable (String) -> Void
    private let onIssue: @Sendable (String) -> Void
    var chunks: [[Float]] { appended.value }
    var cancelCount: Int { cancellations.value }

    init(onText: @escaping @Sendable (String) -> Void, onIssue: @escaping @Sendable (String) -> Void) {
        self.onText = onText
        self.onIssue = onIssue
    }

    func append(_ samples: [Float]) { appended.withLock { $0.append(samples) } }
    func cancel() { cancellations.withLock { $0 += 1 } }
    // Remains callable after cancel to model late engine callbacks.
    func sendText(_ text: String) { onText(text) }
    func sendIssue(_ issue: String) { onIssue(issue) }
}

/// Output depends only on the audio, so the same capture always yields the same text.
private actor ModelPreviewTestSpeech: Transcriber {
    nonisolated let id = "model-preview-test-speech"
    private(set) var receivedSamples: [[Float]] = []
    private(set) var receivedVocabulary: [[String]] = []
    static func text(for count: Int) -> String { "Model heard \(count) samples" }
    func isReady() async -> Bool { true }
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        receivedSamples.append(samples)
        receivedVocabulary.append(hints.vocabulary)
        return Transcript(text: Self.text(for: samples.count), engine: id, latencyMs: 1)
    }
}
