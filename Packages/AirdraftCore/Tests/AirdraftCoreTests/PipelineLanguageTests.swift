import XCTest
@testable import AirdraftCore

@MainActor
final class PipelineLanguageTests: XCTestCase {
    func testInvalidRecordingLanguageBlocksBeforeCredentialsModelsAndMicrophone() async throws {
        for config in [ASRConfig(kind: .cohere), ASRConfig(kind: .parakeet, language: "zh")] {
            let fixture = try LanguagePipelineFixture(config: config)
            defer { fixture.cleanUp() }
            fixture.settings.llm = LLMConfig(kind: .openAI)

            do {
                try await fixture.pipeline.startFromAutomation()
                XCTFail("Incompatible language must block capture")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }

            for event in ["credential", "installation", "engine", "prepare", "microphone", "capture"] {
                XCTAssertEqual(fixture.probe.count(event), 0, "Language rejection must precede \(event)")
            }
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording, "No audio was captured")
            XCTAssertNotNil(fixture.pipeline.lastIssue)
            XCTAssertEqual(try fixture.history.count(), 0)
        }
    }

    func testProcessSamplesUsesEffectiveProfileAndLanguageSnapshot() async throws {
        // The app default cannot transcribe Chinese; the bound model can.
        let fixture = try LanguagePipelineFixture(config: ASRConfig(kind: .parakeet, language: "zh"))
        defer { fixture.cleanUp() }
        let profile = fixture.profiles.add(RefinementProfile(name: "Chinese binding", usesLLM: false, instructions: "",
            speechModel: ProfileSpeechModel(config: ASRConfig(kind: .senseVoice))))
        fixture.profiles.setActive(profile.id)

        fixture.pipeline.processSamples(LanguagePipelineFixture.samples)
        fixture.profiles.setActive(RefinementProfile.cleanID)
        fixture.settings.asr.language = "en"
        try await waitForCompletion(fixture.pipeline)

        let call = try XCTUnwrap(fixture.probe.invocations.first)
        XCTAssertEqual(fixture.probe.invocations.count, 1)
        XCTAssertEqual(call.config.kind, .senseVoice)
        XCTAssertEqual(call.config.language, "zh")
        XCTAssertEqual(call.language, "zh")
        XCTAssertEqual(fixture.settings.asr.kind, .parakeet, "A profile must not overwrite the app default")
        XCTAssertEqual(fixture.settings.asr.language, "en")
        let saved = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(saved.asrEngine, "sherpa-onnx:senseVoice")
        XCTAssertEqual(saved.mode, "Chinese binding")
        XCTAssertNil(fixture.pipeline.lastIssue)
    }

    func testInvalidLanguageRetainsAudioAndRetryUsesCorrectedSelection() async throws {
        let fixture = try LanguagePipelineFixture(config: ASRConfig(kind: .cohere))
        defer { fixture.cleanUp() }
        fixture.pipeline.processSamples(LanguagePipelineFixture.samples)
        try await waitForCompletion(fixture.pipeline)

        XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
        XCTAssertEqual(fixture.probe.count("engine"), 0)
        XCTAssertTrue(fixture.probe.invocations.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)

        fixture.settings.asr.language = "zh"
        fixture.pipeline.retryRecording()
        try await waitForCompletion(fixture.pipeline)

        let call = try XCTUnwrap(fixture.probe.invocations.first)
        XCTAssertEqual(call.language, "zh")
        XCTAssertEqual(call.sampleCount, LanguagePipelineFixture.samples.count)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.raw, LanguagePipelineFixture.transcript)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testHistoryLanguageFailureAndRetryStayReviewOnly() async throws {
        for destination in [TextOutputDestination.cursor, .script] {
            let fixture = try LanguagePipelineFixture(config: ASRConfig(kind: .cohere))
            defer { fixture.cleanUp() }
            fixture.settings.outputDestination = destination
            fixture.settings.outputScriptPath = "/unused-review-only-script"
            fixture.pipeline.insertionEnabled = true
            fixture.pipeline.onOutputDelivered = { XCTFail("A history review must never deliver text") }
            let original = try fixture.saveOriginal()

            fixture.pipeline.retranscribe(original)
            try await waitForCompletion(fixture.pipeline)
            XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)
            XCTAssertEqual(fixture.probe.count("engine"), 0)
            XCTAssertNil(fixture.pipeline.reviewOutcome)

            fixture.settings.asr.language = "zh"
            fixture.pipeline.retryRecording()
            try await waitForCompletion(fixture.pipeline)

            XCTAssertEqual(fixture.pipeline.reviewOutcome?.raw, LanguagePipelineFixture.transcript)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
            XCTAssertNil(fixture.pipeline.lastOutcome)
            XCTAssertEqual(fixture.probe.count("insert"), 0)
            XCTAssertEqual(fixture.probe.count("script"), 0)
            XCTAssertEqual(try fixture.history.recent(), [original])
            XCTAssertNotNil(fixture.history.audioURL(for: original))
        }
    }

    func testFactoryRejectsInvalidConfigDespiteSupportedLanguageHint() async throws {
        let fixture = try LanguagePipelineFixture(config: ASRConfig(kind: .parakeet, language: "zh"))
        defer { fixture.cleanUp() }
        do {
            _ = try await fixture.factory.transcribe(LanguagePipelineFixture.samples,
                hints: .init(language: "en"), config: fixture.settings.asr)
            XCTFail("A caller must not bypass incompatible settings through different hints")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(fixture.probe.count("credential"), 0)
        XCTAssertEqual(fixture.probe.count("engine"), 0)
        XCTAssertTrue(fixture.probe.invocations.isEmpty)
    }

    func testFactoryResolvesLanguageFromConfigAndPreservesOtherHints() async throws {
        let fixture = try LanguagePipelineFixture(config: ASRConfig(kind: .senseVoice, language: "zh-TW"))
        defer { fixture.cleanUp() }
        _ = try await fixture.factory.transcribe(LanguagePipelineFixture.samples,
            hints: .init(language: "en", vocabulary: ["AirDraft"], chineseScript: .traditional),
            config: fixture.settings.asr)

        let call = try XCTUnwrap(fixture.probe.invocations.first)
        XCTAssertEqual(call.language, "zh", "The recording configuration owns language selection")
        XCTAssertEqual(call.vocabulary, ["AirDraft"])
        XCTAssertEqual(call.script, .traditional)
        XCTAssertEqual(fixture.probe.count("credential"), 0)
    }

    private func waitForCompletion(_ pipeline: DictationPipeline, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(3)
        while pipeline.isBusy, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(pipeline.isBusy, "Pipeline did not finish", file: file, line: line)
        if pipeline.isBusy { throw WaitError.timedOut }
    }

    private enum WaitError: Error { case timedOut }
}

@MainActor
private final class LanguagePipelineFixture {
    static let samples = [Float](repeating: 0.125, count: 16_000)
    static let transcript = "Language fixture transcript"
    let suite = "airdraft.pipeline-language.\(UUID().uuidString)"
    let directory: URL
    let settings: AppSettings
    let profiles: ProfileStore
    let history: HistoryStore
    let factory: EngineFactory
    let recorder: LanguageRecorder
    let pipeline: DictationPipeline
    let probe = LanguagePipelineProbe()

    init(config: ASRConfig) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings = AppSettings(defaults: defaults)
        settings.asr = config
        settings.llm = LLMConfig(kind: .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        settings.hudStyle = .none
        profiles = ProfileStore(directory: directory)
        history = try HistoryStore(directory: directory)
        let probe = self.probe
        factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            probe.note("credential")
            return nil
        }, transcriberBuilder: { config in
            probe.note("engine")
            return LanguageFixtureSpeech(config: config, probe: probe)
        })
        recorder = LanguageRecorder(probe: probe)
        pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: profiles, history: history, factory: factory, recorder: recorder,
            insertText: { _, _, _ in
                probe.note("insert")
                return InsertionResult(method: .accessibility, notice: nil)
            }, sendScript: { _, _ in probe.note("script") },
            recordingPreflight: { asr, llm, refining, microphone, insertion in
                let environment = RecordingPrerequisites.Environment(
                    microphoneAuthorized: true, accessibilityAuthorized: true,
                    devices: [.init(id: 7, uid: "language-fixture", name: "Fixture input", inputChannelCount: 1)],
                    defaultDeviceID: 7, readCredential: { _ in probe.note("credential"); return nil },
                    installed: { _ in probe.note("installation"); return true },
                    appleIntelligenceUnavailable: { nil })
                try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: refining,
                    microphone: microphone, insertionEnabled: insertion, environment: environment)
            }, requestMicrophoneAccess: {
                probe.note("microphone")
                return true
            })
        pipeline.insertionEnabled = false
    }

    func saveOriginal() throws -> DictationRecord {
        _ = try history.save(DictationRecord(mode: "Original", family: "document", rawTranscript: "Original words",
            refinedText: "Original words", finalText: "Original words", asrEngine: "original-engine",
            audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: false), samples: Self.samples)
        // Compare the persisted snapshot before and after review. Database date
        // encoding can round the in-memory Date passed to save().
        return try XCTUnwrap(history.recent().first)
    }

    func cleanUp() {
        pipeline.cancel()
        do {
            try history.close()
            try FileManager.default.removeItem(at: directory)
        } catch { XCTFail("Fixture cleanup failed: \(error)") }
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

private final class LanguagePipelineProbe: @unchecked Sendable {
    struct Invocation {
        let config: ASRConfig
        let language: String?
        let vocabulary: [String]
        let script: ChineseScript
        let sampleCount: Int
    }
    private let lock = NSLock()
    private var events: [String: Int] = [:]
    private var calls: [Invocation] = []
    func note(_ event: String) { lock.withLock { events[event, default: 0] += 1 } }
    func count(_ event: String) -> Int { lock.withLock { events[event, default: 0] } }
    var invocations: [Invocation] { lock.withLock { calls } }
    func record(config: ASRConfig, hints: TranscriptionHints, sampleCount: Int) {
        lock.withLock {
            calls.append(.init(config: config, language: hints.language, vocabulary: hints.vocabulary,
                               script: hints.chineseScript, sampleCount: sampleCount))
        }
    }
}

private struct LanguageFixtureSpeech: Transcriber {
    let config: ASRConfig
    let probe: LanguagePipelineProbe
    var id: String { config.engineID }
    func prepare() async throws { probe.note("prepare") }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        probe.record(config: config, hints: hints, sampleCount: samples.count)
        return Transcript(text: "Language fixture transcript", language: hints.language, engine: id, latencyMs: 0)
    }
}

private final class LanguageRecorder: AudioRecording, @unchecked Sendable {
    let probe: LanguagePipelineProbe
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    init(probe: LanguagePipelineProbe) { self.probe = probe }
    func start(microphone: MicrophonePreference) throws { probe.note("capture"); isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.125, count: 16_000) }
    func cancel() { isRecording = false }
}
