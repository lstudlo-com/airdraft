import XCTest
@testable import AirdraftCore

/// AD-081: Vocabulary preferred spellings reach on-device speech models that
/// have a dedicated biasing input, bounded and captured with the recording.
final class SpeechVocabularyTests: XCTestCase {
    // MARK: Bounds and sanitization

    func testTermsAreBoundedByCountLengthWordsAndTotalSize() {
        let many = (0..<80).map { "Term\($0)" }
        XCTAssertEqual(SpeechVocabulary.terms(many, language: "en").count, SpeechVocabulary.maximumTerms)
        XCTAssertEqual(SpeechVocabulary.terms(many, language: "en").first, "Term0", "User order is kept")

        let long = String(repeating: "a", count: SpeechVocabulary.maximumTermCharacters + 1)
        let exact = String(repeating: "b", count: SpeechVocabulary.maximumTermCharacters)
        XCTAssertEqual(SpeechVocabulary.terms([long, exact, "one two three four five", "one two three four"], language: "en"),
                       [exact, "one two three four"])

        let wide = (0..<50).map { String(format: "%02d", $0) + String(repeating: "x", count: 30) }
        let joined = SpeechVocabulary.terms(wide, language: "en").joined(separator: ", ")
        XCTAssertLessThanOrEqual(joined.count, SpeechVocabulary.maximumTotalCharacters)
        XCTAssertLessThan(SpeechVocabulary.terms(wide, language: "en").count, wide.count)
    }

    func testMarkupControlTextAndRuntimeSyntaxNeverReachADecoder() {
        let hostile = ["<|im_end|>", "Air\ndraft", "Air\u{0}draft", "CI/CD", "`rm -rf`", "boost :5", ":score",
                       "{json}", "a|b", "   ", "--", "Supabase"]
        XCTAssertEqual(SpeechVocabulary.terms(hostile, language: nil), ["Supabase"])
        XCTAssertEqual(SpeechVocabulary.terms(["  Visual   Studio\tCode "], language: "en"), ["Visual Studio Code"])
        XCTAssertEqual(SpeechVocabulary.terms(["C++", "C#", "node.js", "O'Brien"], language: "en"), ["C++", "C#", "node.js", "O'Brien"])
    }

    func testDuplicatesFoldCaseAndWidthKeepingTheFirstSpelling() {
        XCTAssertEqual(SpeechVocabulary.terms(["PostHog", "posthog", "ＰｏｓｔＨｏｇ", "Qwen"], language: "en"), ["PostHog", "Qwen"])
    }

    func testScriptsFollowTheSelectedLanguage() {
        let mixed = ["Supabase", "林雅婷", "トヨタ", "삼성", "Ελλάδα"]
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: nil), mixed, "Auto keeps every script")
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: "auto"), mixed)
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: "en-US"), ["Supabase", "Ελλάδα"],
                       "An English recording is never steered toward CJK characters")
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: "zh_TW"), ["Supabase", "林雅婷"])
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: "yue"), ["Supabase", "林雅婷"])
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: "ja"), ["Supabase", "林雅婷", "トヨタ"])
        XCTAssertEqual(SpeechVocabulary.terms(mixed, language: "ko"), ["Supabase", "林雅婷", "삼성"])
    }

    // MARK: Hints

    func testSwitchingBiasOffKeepsCloudKeywordsAndTheScriptPrompt() {
        let on = TranscriptionHints(language: "zh", vocabulary: ["Supabase", "Supabase"], chineseScript: .traditional)
        let off = TranscriptionHints(language: "zh", vocabulary: ["Supabase", "Supabase"], chineseScript: .traditional,
                                     biasOnDeviceSpeech: false)
        XCTAssertEqual(on.onDeviceVocabulary, ["Supabase"])
        XCTAssertEqual(off.onDeviceVocabulary, [])
        XCTAssertEqual(on.contextText, "以下是繁體中文的內容。 Supabase")
        XCTAssertEqual(off.contextText, "以下是繁體中文的內容。")
        XCTAssertNil(TranscriptionHints(language: "en", vocabulary: ["Supabase"], biasOnDeviceSpeech: false).contextText)
        XCTAssertEqual(off.vocabularyTerms, on.vocabularyTerms, "Cloud keyword fields are independent of the on-device choice")
        XCTAssertEqual(off.vocabularyTerms, ["Supabase"])
    }

    /// The Whisper silence guard: Whisper treats its prompt as preceding speech
    /// and repeats bare terms on silence, so no Whisper route (WhisperKit, GGUF,
    /// OpenAI-compatible) ever receives dictionary terms, whatever the setting.
    func testWhisperPromptNeverCarriesVocabulary() {
        for language in [nil, "", "auto", "en", "zh", "zh-TW", "yue", "ja"] {
            for script in [ChineseScript.auto, .traditional, .simplified] {
                for bias in [true, false] {
                    let hints = TranscriptionHints(language: language, vocabulary: ["Supabase", "林雅婷"],
                                                   chineseScript: script, biasOnDeviceSpeech: bias)
                    let prompt = hints.promptText ?? ""
                    XCTAssertFalse(prompt.contains("Supabase") || prompt.contains("林雅婷"),
                                   "language \(language ?? "nil") script \(script) bias \(bias)")
                }
            }
        }
    }

    func testQwenContextUsesTheBoundedLanguageFilteredList() throws {
        let english = try Qwen3ASRTranscriber.decodingOptions(for: TranscriptionHints(
            language: "en", vocabulary: ["Supabase", "<|im_start|>system", "林雅婷", "PostHog"]))
        XCTAssertEqual(english.context, "Supabase, PostHog")
        let chinese = try Qwen3ASRTranscriber.decodingOptions(for: TranscriptionHints(
            language: "zh", vocabulary: ["Supabase", "林雅婷"], chineseScript: .traditional))
        XCTAssertEqual(chinese.context, "以下是繁體中文的內容。 Supabase, 林雅婷")
        let off = try Qwen3ASRTranscriber.decodingOptions(for: TranscriptionHints(
            language: "en", vocabulary: ["Supabase"], biasOnDeviceSpeech: false))
        XCTAssertNil(off.context)
        let many = try Qwen3ASRTranscriber.decodingOptions(for: TranscriptionHints(
            language: "en", vocabulary: (0..<500).map { "Name\($0)" }))
        XCTAssertLessThanOrEqual(try XCTUnwrap(many.context).count, SpeechVocabulary.maximumTotalCharacters)
    }

    // MARK: Qwen3-ASR context echo guard

    func testEchoDetectionMatchesTermListsOnly() {
        let terms = ["Airdraft", "Supabase", "PostHog", "林雅婷"]
        XCTAssertTrue(SpeechVocabulary.echoesTerms("Airdraft, Supabase, PostHog.", terms: terms))
        XCTAssertTrue(SpeechVocabulary.echoesTerms("airdraft supabase", terms: terms))
        XCTAssertTrue(SpeechVocabulary.echoesTerms("林雅婷、Supabase", terms: terms))
        XCTAssertFalse(SpeechVocabulary.echoesTerms("Supabase.", terms: terms), "A one-word dictation is legitimate")
        XCTAssertFalse(SpeechVocabulary.echoesTerms("Move Airdraft to Supabase.", terms: terms))
        XCTAssertFalse(SpeechVocabulary.echoesTerms("Okay.", terms: terms))
        XCTAssertFalse(SpeechVocabulary.echoesTerms("Airdraft, Supabase", terms: []))
    }

    func testSilenceGateKeepsQuietSpeech() {
        XCTAssertTrue(SpeechVocabulary.isNearSilent([]))
        XCTAssertTrue(SpeechVocabulary.isNearSilent([Float](repeating: 0.001, count: 1600)), "-60 dBFS")
        XCTAssertFalse(SpeechVocabulary.isNearSilent([Float](repeating: 0.008, count: 1600)), "-42 dBFS quiet speech")
        XCTAssertFalse(SpeechVocabulary.isNearSilent([Float](repeating: 0.15, count: 1600)), "-16 dBFS speech")
    }

    func testQwenChunkDecodingDropsVocabularyOnSilenceAndEcho() throws {
        let terms = ["Airdraft", "Supabase"]
        let options = try Qwen3ASRTranscriber.decodingOptions(for: TranscriptionHints(
            language: "zh", vocabulary: terms, chineseScript: .traditional))
        XCTAssertEqual(options.context, "以下是繁體中文的內容。 Airdraft, Supabase")
        let speech = [Float](repeating: 0.15, count: 1600)
        let silence = [Float](repeating: 0.001, count: 1600)
        var contexts: [String?] = []
        func run(_ chunk: [Float], _ outputs: [String]) -> String {
            contexts = []
            var remaining = outputs
            return Qwen3ASRTranscriber.decodeGuardingVocabulary(chunk, options: options, fallbackContext: "以下是繁體中文的內容。",
                                                                terms: terms) { _, used in
                contexts.append(used.context)
                return remaining.removeFirst()
            }
        }
        XCTAssertEqual(run(speech, ["Deploy Airdraft"]), "Deploy Airdraft")
        XCTAssertEqual(contexts, [options.context], "Speech decodes once with the vocabulary")
        XCTAssertEqual(run(silence, [""]), "")
        XCTAssertEqual(contexts, ["以下是繁體中文的內容。"], "Silence never sees the vocabulary; the script sentence stays")
        XCTAssertEqual(run(speech, ["Airdraft, Supabase.", "Okay."]), "Okay.")
        XCTAssertEqual(contexts, [options.context, "以下是繁體中文的內容。"], "An echoed list is decoded once more without terms")
        let unbiased = Qwen3ASRTranscriber.decodeGuardingVocabulary(silence, options: options, fallbackContext: nil, terms: []) { _, used in
            used.context ?? "nil"
        }
        XCTAssertEqual(unbiased, options.context, "Without terms the options pass through unchanged")
    }

    // MARK: sherpa-onnx transducer hotwords

    private typealias Configuration = SherpaTranscriber.RecognizerConfiguration
    private let folder = URL(fileURLWithPath: "/airdraft-hotword-fixture", isDirectory: true)
    private let files = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]

    func testOnlyTransducersSwitchToHotwordDecoding() throws {
        let hints = TranscriptionHints(language: "en", vocabulary: ["Supabase"])
        for model in SherpaTranscriber.Model.allCases {
            let language = model == .fireRed ? "zh" : "en"
            var modelHints = hints
            modelHints.language = language
            let configuration = try Configuration(model: model, hints: modelHints)
            XCTAssertEqual(configuration.hotwordDecoding, model == .parakeet || model == .orukeet, "\(model)")
            XCTAssertEqual(model.supportsHotwords, configuration.hotwordDecoding)
        }
        XCTAssertFalse(try Configuration(model: .parakeet, hints: .init(language: "en")).hotwordDecoding, "No terms, greedy")
        XCTAssertFalse(try Configuration(model: .parakeet, hints: .init(language: "en", vocabulary: ["Supabase"],
                                                                         biasOnDeviceSpeech: false)).hotwordDecoding)
        XCTAssertFalse(try Configuration(model: .parakeet, hints: .init(language: "en", vocabulary: ["林雅婷"])).hotwordDecoding,
                       "Terms the language filter removes do not change decoding")
        XCTAssertNotEqual(try Configuration(model: .parakeet, hints: hints), try Configuration(model: .parakeet),
                          "Turning hotwords on rebuilds the recognizer")
    }

    func testHotwordDecodingSetsBeamSearchAndTheBPEVocabularyTogether() throws {
        let configuration = try Configuration(model: .parakeet, hints: .init(language: "en", vocabulary: ["Supabase"]))
        configuration.withCConfiguration(folder: folder, files: files, bpeVocabulary: "/tmp/scored.txt") { native in
            XCTAssertEqual(String(cString: native.decoding_method), "modified_beam_search")
            XCTAssertEqual(native.max_active_paths, 4)
            XCTAssertEqual(native.hotwords_score, SherpaTranscriber.hotwordScore)
            XCTAssertEqual(String(cString: native.model_config.modeling_unit), "bpe")
            XCTAssertEqual(String(cString: native.model_config.bpe_vocab), "/tmp/scored.txt")
            XCTAssertNil(native.hotwords_file, "Hotwords are per stream, never a file")
        }
        // Without a vocabulary file the native encoder would dereference null.
        configuration.withCConfiguration(folder: folder, files: files) { native in
            XCTAssertEqual(String(cString: native.decoding_method), "greedy_search")
            XCTAssertNil(native.model_config.modeling_unit)
            XCTAssertNil(native.model_config.bpe_vocab)
        }
        try Configuration(model: .parakeet).withCConfiguration(folder: folder, files: files, bpeVocabulary: "/tmp/scored.txt") { native in
            XCTAssertEqual(String(cString: native.decoding_method), "greedy_search", "Greedy configuration ignores the file")
            XCTAssertNil(native.model_config.bpe_vocab)
        }
    }

    func testTokenVocabularyCoverageAndScoredFile() throws {
        let tokens = SherpaTranscriber.TokenVocabulary(text: """
        <unk> 0
        ▁ 1
        ▁Sup 2
        a 3
        base 4
        ▁P 5
        ost 6
        H 7
        og 8
        broken line 9
        x
        """)
        XCTAssertEqual(tokens.pieces, ["<unk>", "▁", "▁Sup", "a", "base", "▁P", "ost", "H", "og"])
        XCTAssertTrue(tokens.canEncode("▁Supabase"))
        XCTAssertTrue(tokens.canEncode("▁PostHog"))
        XCTAssertFalse(tokens.canEncode("▁Qwen"), "Unspellable terms are skipped, not partially boosted")
        XCTAssertEqual(SherpaTranscriber.hotwords(["Supabase", "Qwen", "PostHog"], vocabulary: tokens), "Supabase/PostHog")
        XCTAssertNil(SherpaTranscriber.hotwords(["Qwen"], vocabulary: tokens))

        // simple-sentencepiece exits the process on any malformed line.
        let lines = tokens.scoredVocabulary().split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.last, "", "File ends with a newline")
        for line in lines.dropLast() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: false)
            XCTAssertEqual(fields.count, 2, String(line))
            let score = try XCTUnwrap(Float(fields[1]), String(line))
            XCTAssertLessThanOrEqual(score, -1)
            XCTAssertGreaterThan(score, -2)
        }
        XCTAssertEqual(lines.count - 1, tokens.pieces.count)
    }

    func testPrewarmFollowsTheAnticipatedVocabularyChoice() {
        SherpaTranscriber.anticipate(TranscriptionHints(language: "en", vocabulary: ["Supabase"]))
        XCTAssertTrue(SherpaTranscriber.anticipatesHotwordDecoding)
        SherpaTranscriber.anticipate(TranscriptionHints(language: "en", vocabulary: ["Supabase"], biasOnDeviceSpeech: false))
        XCTAssertFalse(SherpaTranscriber.anticipatesHotwordDecoding)
        SherpaTranscriber.anticipate(TranscriptionHints(language: "en"))
        XCTAssertFalse(SherpaTranscriber.anticipatesHotwordDecoding)
    }

    /// Real model, opt-in through test-local-e2e.py --parakeet-model (the same
    /// AIRDRAFT_PARAKEET_TEST_MODEL_DIR as ParakeetTests). Optionally
    /// AIRDRAFT_VOCABULARY_TEST_WAV names speech containing "kubectl"
    /// (eval/vocab-bias en05); otherwise the archive's test_wavs/en.wav runs.
    func testInstalledParakeetBuildsAHotwordRecognizer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["AIRDRAFT_PARAKEET_TEST_MODEL_DIR"] else {
            throw XCTSkip("Set AIRDRAFT_PARAKEET_TEST_MODEL_DIR to an installed Parakeet INT8 folder")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let speech = environment["AIRDRAFT_VOCABULARY_TEST_WAV"]
        let samples = try AudioFile.load(path: speech ?? folder.appendingPathComponent("test_wavs/en.wav").path)
        let engine = SherpaTranscriber(model: .parakeet, modelDirectory: folder)
        let plain = try await engine.transcribe(samples: samples, hints: .init(language: "en"))
        let biased = try await engine.transcribe(samples: samples, hints: .init(language: "en", vocabulary: ["kubectl", "林雅婷"]))
        XCTAssertFalse(plain.text.isEmpty)
        XCTAssertFalse(biased.text.isEmpty, "Hotword decoding must still transcribe")
        if speech != nil { XCTAssertTrue(biased.text.contains("kubectl"), biased.text) }
        let temporary = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        XCTAssertFalse(temporary.contains { $0.hasPrefix("airdraft-hotword-vocab-") }, "The scored vocabulary is deleted after creation")
    }
}

// MARK: Pipeline snapshot

@MainActor
final class SpeechVocabularyPipelineTests: XCTestCase {
    func testSettingDefaultsOnAndPersists() throws {
        let suite = "airdraft.speech-vocabulary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AppSettings(defaults: defaults).vocabularyBiasesOnDeviceSpeech)
        AppSettings(defaults: defaults).vocabularyBiasesOnDeviceSpeech = false
        XCTAssertFalse(AppSettings(defaults: defaults).vocabularyBiasesOnDeviceSpeech)
    }

    func testRecordingCapturesPreferredSpellingsAndTheChoiceAtStart() async throws {
        let fixture = try VocabularyPipelineFixture()
        defer { fixture.cleanUp() }
        fixture.dictionary.add(DictionaryEntry(term: "Supabase", aliases: ["super base", "soup a base"]))
        fixture.dictionary.add(DictionaryEntry(term: "林雅婷"))

        fixture.pipeline.processSamples(VocabularyPipelineFixture.samples)
        // Changes after capture apply to the next recording only.
        fixture.settings.vocabularyBiasesOnDeviceSpeech = false
        fixture.dictionary.add(DictionaryEntry(term: "PostHog"))
        try await fixture.waitForIdle()

        fixture.pipeline.processSamples(VocabularyPipelineFixture.samples)
        try await fixture.waitForIdle()

        let calls = fixture.probe.calls.value
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].vocabulary, ["Supabase", "林雅婷"], "Aliases are misheard forms and never bias recognition")
        XCTAssertTrue(calls[0].bias)
        XCTAssertEqual(calls[0].onDevice, ["Supabase"], "English recording drops the Chinese name")
        XCTAssertEqual(calls[1].vocabulary, ["Supabase", "林雅婷", "PostHog"], "Cloud keyword input is unchanged")
        XCTAssertFalse(calls[1].bias)
        XCTAssertEqual(calls[1].onDevice, [])
        // Dictionary post-processing still runs last on the final text.
        XCTAssertEqual(try fixture.history.recent().first?.finalText, "Deploy to Supabase")
    }
}

@MainActor
private final class VocabularyPipelineFixture {
    static let samples = [Float](repeating: 0.125, count: 16_000)
    let suite = "airdraft.speech-vocabulary-pipeline.\(UUID().uuidString)"
    let directory: URL
    let settings: AppSettings
    let dictionary: DictionaryStore
    let history: HistoryStore
    let probe = VocabularyProbe()
    let pipeline: DictationPipeline

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        settings.asr = ASRConfig(kind: .qwen3, language: "en")
        settings.llm = LLMConfig(kind: .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        settings.hudStyle = .none
        dictionary = DictionaryStore(directory: directory)
        history = try HistoryStore(directory: directory)
        let probe = probe
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil },
                                    transcriberBuilder: { config in VocabularyFixtureSpeech(config: config, probe: probe) })
        pipeline = DictationPipeline(settings: settings, dictionary: dictionary, profiles: ProfileStore(directory: directory),
            history: history, factory: factory, recorder: SilentFixtureRecorder(),
            insertText: { _, _, _ in InsertionResult(method: .accessibility, notice: nil) }, sendScript: { _, _ in },
            recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
        pipeline.insertionEnabled = false
    }

    func waitForIdle() async throws {
        let deadline = Date().addingTimeInterval(3)
        while pipeline.isBusy || pipeline.isFinishingDelivery, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(pipeline.isBusy || pipeline.isFinishingDelivery)
    }

    func cleanUp() {
        pipeline.cancel()
        try? history.close()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

private final class VocabularyProbe: Sendable {
    struct Call: Sendable { let vocabulary: [String]; let bias: Bool; let onDevice: [String] }
    let calls = Locked<[Call]>([])
}

private struct VocabularyFixtureSpeech: Transcriber {
    let config: ASRConfig
    let probe: VocabularyProbe
    var id: String { config.engineID }
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        probe.calls.withLock { $0.append(.init(vocabulary: hints.vocabulary, bias: hints.biasOnDeviceSpeech,
                                               onDevice: hints.onDeviceVocabulary)) }
        return Transcript(text: "Deploy to super base", language: hints.language, engine: id, latencyMs: 0)
    }
}

/// Unchecked: driven only by the MainActor pipeline under test.
private final class SilentFixtureRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.125, count: 16_000) }
    func cancel() { isRecording = false }
}
