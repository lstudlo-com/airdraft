import XCTest
@testable import AirdraftCore

/// Regressions from history records where Apple Intelligence returned an earlier
/// dictation or an English translation instead of the new Chinese transcript.
@MainActor
final class RefinementFidelityTests: XCTestCase {
    private let echoed = "floze: What is the English expression for the recessed and protruding effects of Numorphism style?"

    // MARK: - Guard

    func testRejectsEarlierDictationReturnedForNewSpeech() {
        for transcript in ["我也想問你,所以", "這是什麼意思?"] {
            XCTAssertEqual(RefinementFidelity.violation(
                output: "Floze: What is the English expression for the recessed and protruding effects of Numorphism style?",
                transcript: transcript, recentDictations: [echoed, echoed], allowsLanguageChange: false),
                .repeatsEarlierDictation, transcript)
        }
        XCTAssertEqual(RefinementFidelity.violation(
            output: "Please send the quarterly report to Anna before Friday.",
            transcript: "can you check whether the build passed on main",
            recentDictations: ["Please send the quarterly report to Anna before Friday."], allowsLanguageChange: false),
            .repeatsEarlierDictation)
    }

    func testAcceptsSpeakerRepeatingTheSameSentence() {
        XCTAssertNil(RefinementFidelity.violation(
            output: "所以現在的結果是如何？", transcript: "所以現在的結果是如何?",
            recentDictations: ["所以現在的結果是如何？"], allowsLanguageChange: false))
        XCTAssertNil(RefinementFidelity.violation(
            output: "Hello, can you hear me?", transcript: "hello can you hear me",
            recentDictations: ["Hello, can you hear me?"], allowsLanguageChange: false))
    }

    func testUnrelatedEnglishDictationsAreNotMistakenForCopies() {
        let earlier = "I want you to do a comprehensive survey of the interface design and for mainly two parts, the microphone pop-up and the purchase pop-up."
        XCTAssertNil(RefinementFidelity.violation(
            output: "What does the dash only mean after a GPL 3.0 license name?",
            transcript: "What does the dash only mean after a GPAL 3.0 license name?",
            recentDictations: [earlier], allowsLanguageChange: false))
    }

    func testRejectsTranslationOfChineseSpeech() {
        let transcript = "另外我也想問你,Numorphism style它的凹陷跟凸起效果用英文應該怎麼表達?"
        XCTAssertEqual(RefinementFidelity.violation(output: echoed, transcript: transcript, recentDictations: [],
                                                    allowsLanguageChange: false), .changesLanguage)
        XCTAssertEqual(RefinementFidelity.violation(
            output: "Additionally, how should the recessed and protruding effects of the Numorphism style be expressed in English?",
            transcript: transcript, recentDictations: [], allowsLanguageChange: false), .changesLanguage)
        XCTAssertEqual(RefinementFidelity.violation(
            output: "Should we deploy the new build today?", transcript: "我們今天要部署新版本嗎",
            recentDictations: [], allowsLanguageChange: false), .changesLanguage)
        XCTAssertEqual(RefinementFidelity.violation(
            output: "我們今天要部署新版本嗎？", transcript: "should we deploy the new build today",
            recentDictations: [], allowsLanguageChange: false), .changesLanguage)
    }

    func testAcceptsCleanupThatKeepsMixedLanguage() {
        XCTAssertNil(RefinementFidelity.violation(
            output: "另外我也想問你，Numorphism style 的凹陷跟凸起效果用英文應該怎麼表達？",
            transcript: "另外我也想問你,Numorphism style它的凹陷跟凸起效果用英文應該怎麼表達?",
            recentDictations: [], allowsLanguageChange: false))
        XCTAssertNil(RefinementFidelity.violation(
            output: "你認為 Buy Me a Coffee 會跟我所提供的 subscription 訂閱服務產生衝突嗎？",
            transcript: "你認為,Buy me a coffee會跟我所提供的subscription訂閱服務產生衝突嗎?",
            recentDictations: [], allowsLanguageChange: false))
        XCTAssertNil(RefinementFidelity.violation(
            output: "接下來請一律以繁體中文回答。你已調查過即時聽寫，結論是需要支援即時聽寫模型。",
            transcript: "接下來請都用繁體中文來回答我的問題。OK,所以你已經去調查了real-time dictation,那調查結果是說需要支援real-time",
            recentDictations: [], allowsLanguageChange: false))
    }

    func testTaskOrSelectedTextMayChangeLanguage() {
        XCTAssertNil(RefinementFidelity.violation(output: "Should we deploy the new build today?",
            transcript: "我們今天要部署新版本嗎", recentDictations: [], allowsLanguageChange: true))
    }

    // MARK: - Prompt

    func testRecentDictationsContributeTermsNotSentences() {
        XCTAssertEqual(PromptBuilder.recentTerms(["今天測了 FireRedASR2 跟 SenseVoice 的中文準確度。"]),
                       ["FireRedASR2", "SenseVoice"])
        XCTAssertEqual(PromptBuilder.recentTerms([
            "Gemma runs locally. We compared it with Qwen3 and Claude Code on Next.js, OK?",
        ]), ["Qwen3", "Claude", "Code", "Next.js"])

        let request = RefineRequest(
            transcript: "我也想問你,所以", profile: RefinementProfile.defaults[1],
            context: AppContext(bundleId: "com.openai.codex", appName: "ChatGPT", recentDictations: [echoed]),
            family: .general, dictionary: [])
        let user = PromptBuilder.userMessage(for: request)
        XCTAssertFalse(user.contains("What is the English expression"))
        XCTAssertFalse(user.contains("<recent_dictations>"))
        XCTAssertTrue(user.contains("<recent_terms>\nEnglish, Numorphism\n</recent_terms>"))
    }

    func testOutputLanguageRuleSurvivesEditedBaseRules() {
        var request = RefineRequest(transcript: "這是什麼意思?", profile: RefinementProfile.defaults[1],
                                    baseRules: "Clean dictation. Output only final text.",
                                    context: .empty, family: .general, dictionary: [])
        XCTAssertTrue(PromptBuilder.systemPrompt(for: request).contains("OUTPUT LANGUAGE: write in the language or languages spoken in <transcription>"))

        request.profile = RefinementProfile.defaults[2]
        XCTAssertTrue(PromptBuilder.systemPrompt(for: request).contains("OUTPUT LANGUAGE: unless the TASK names another language"))

        request.context = AppContext(selectedText: "hello world")
        XCTAssertFalse(PromptBuilder.systemPrompt(for: request).contains("OUTPUT LANGUAGE"))
    }

    // MARK: - Pipeline

    func testPipelineInsertsRawTranscriptWhenRefinementRepeatsHistory() async throws {
        let fixture = try Fixture(transcript: "我也想問你,所以", refined: echoed)
        defer { fixture.cleanUp() }
        try fixture.saveEarlier(echoed)

        fixture.pipeline.processSamples(Fixture.samples, context: fixture.context)
        try await waitUntilIdle(fixture.pipeline)

        XCTAssertEqual(fixture.probe.insertedTexts, ["我也想問你,所以"])
        XCTAssertEqual(fixture.pipeline.lastIssue, "Refinement didn't match your speech; raw text inserted.")
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.finalText, "我也想問你,所以")
        XCTAssertEqual(record.refinedText, "我也想問你,所以")
        XCTAssertNil(record.llmEngine)
        XCTAssertTrue(record.error?.contains("repeated an earlier dictation") == true)
        let requests = await fixture.refiner.requests
        let sent = try XCTUnwrap(requests.first)
        XCTAssertFalse(PromptBuilder.userMessage(for: sent).contains("What is the English expression"))
    }

    func testPipelineInsertsRawTranscriptWhenRefinementTranslates() async throws {
        let fixture = try Fixture(transcript: "我們今天要部署新版本嗎", refined: "Should we deploy the new build today?")
        defer { fixture.cleanUp() }

        fixture.pipeline.processSamples(Fixture.samples, context: fixture.context)
        try await waitUntilIdle(fixture.pipeline)

        XCTAssertEqual(fixture.probe.insertedTexts, ["我們今天要部署新版本嗎"])
        XCTAssertTrue(try XCTUnwrap(fixture.history.recent().first).error?.contains("changed the language") == true)
    }

    func testPipelineKeepsFaithfulRefinement() async throws {
        let fixture = try Fixture(transcript: "我也想問你,所以", refined: "我也想問你，所以")
        defer { fixture.cleanUp() }
        try fixture.saveEarlier(echoed)

        fixture.pipeline.processSamples(Fixture.samples, context: fixture.context)
        try await waitUntilIdle(fixture.pipeline)

        XCTAssertEqual(fixture.probe.insertedTexts, ["我也想問你，所以"])
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertEqual(try XCTUnwrap(fixture.history.recent().first).llmEngine, "fidelity-test")
    }

    private func waitUntilIdle(_ pipeline: DictationPipeline) async throws {
        try await Task.sleep(for: .milliseconds(5))
        let deadline = Date().addingTimeInterval(3)
        while pipeline.isBusy, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(pipeline.isBusy, "Dictation did not finish")
    }

    private final class Probe {
        var insertedTexts: [String] = []
    }

    @MainActor
    private struct Fixture {
        static let samples = [Float](repeating: 0.125, count: 16_000)
        let suite: String
        let directory: URL
        let history: HistoryStore
        let refiner: FixedRefiner
        let pipeline: DictationPipeline
        let probe: Probe
        let context = AppContext(bundleId: "com.openai.codex", appName: "ChatGPT", windowTitle: "ChatGPT")

        init(transcript: String, refined: String) throws {
            suite = "airdraft.refinement-fidelity.\(UUID().uuidString)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet)
            settings.llm = LLMConfig(kind: .appleIntelligence)
            settings.useAppContext = true
            settings.livePreviewEnabled = false
            history = try HistoryStore(directory: directory)
            let refiner = FixedRefiner(text: refined)
            self.refiner = refiner
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Tests must not read credentials")
                return nil
            }, transcriberBuilder: { _ in FixedSpeech(text: transcript) }, refinerBuilder: { _ in refiner })
            let profiles = ProfileStore(directory: directory)
            profiles.setActive(RefinementProfile.conciseID)
            let probe = Probe()
            self.probe = probe
            pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
                profiles: profiles, history: history, factory: factory, recorder: SilentFixtureRecorder(),
                insertText: { text, _, _ in
                    probe.insertedTexts.append(text)
                    return InsertionResult(method: .paste, notice: nil)
                }, recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
        }

        func saveEarlier(_ final: String) throws {
            _ = try history.save(DictationRecord(
                appBundleId: context.bundleId, appName: context.appName, mode: "Concise", family: "general",
                rawTranscript: "另外我也想問你,Numorphism style它的凹陷跟凸起效果用英文應該怎麼表達?",
                refinedText: final, finalText: final, asrEngine: "fixture", audioSeconds: 1, asrMs: 1, llmMs: 1,
                inserted: true), samples: nil)
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
}

private actor FixedRefiner: Refiner {
    nonisolated let id = "fidelity-test"
    private let text: String
    private(set) var requests: [RefineRequest] = []
    init(text: String) { self.text = text }

    func refine(_ request: RefineRequest) async throws -> RefineResult {
        requests.append(request)
        return RefineResult(text: text, engine: id, latencyMs: 1, promptVersion: PromptBuilder.version)
    }
}

private struct FixedSpeech: Transcriber {
    let text: String
    let id = "fidelity-speech"
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        Transcript(text: text, engine: id, latencyMs: 1)
    }
}

private final class SilentFixtureRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [] }
    func cancel() { isRecording = false }
}
