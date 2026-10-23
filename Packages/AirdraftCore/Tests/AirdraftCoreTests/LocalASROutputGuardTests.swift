import XCTest
@testable import AirdraftCore

/// AD-082: synthetic engine outputs for the local speech output guards.
final class LocalASROutputGuardTests: XCTestCase {
    private let qwen = ASRConfig(kind: .qwen3)
    private let whisper = ASRConfig(kind: .whisperKit)
    private let zhEnUser = LocalASROutputGuard.Policy(expectedLanguages: ["en", "zh"])
    /// Two seconds of a 440 Hz tone at -14 dBFS: audible, not silent.
    private let audible = (0..<32_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16_000) * 0.2) }

    // MARK: Decode budget

    func testQwenTokenBudgetScalesWithChunkDuration() {
        XCTAssertEqual(LocalASRDecodeBudget.qwenMaxTokens(sampleCount: 0), 48)
        XCTAssertEqual(LocalASRDecodeBudget.qwenMaxTokens(sampleCount: 16_000), 64)
        // The 3.2 s clip that looped to 1,024 tokens now stops near 100.
        XCTAssertEqual(LocalASRDecodeBudget.qwenMaxTokens(sampleCount: 51_200), 100)
        XCTAssertEqual(LocalASRDecodeBudget.qwenMaxTokens(sampleCount: 25 * 16_000), 448)
        XCTAssertEqual(LocalASRDecodeBudget.qwenMaxTokens(sampleCount: 600 * 16_000), 1024)
        // Fast measured speech (about 9 tokens/s plus the language prefix) keeps headroom.
        for seconds in [2.5, 5.0, 15.0, 25.0] {
            XCTAssertGreaterThan(Double(LocalASRDecodeBudget.qwenMaxTokens(sampleCount: Int(seconds * 16_000))), seconds * 9 + 6 + 20)
        }
    }

    // MARK: Repetition

    func testDecoderLoopIsCutToOneOccurrence() {
        let looped = "是爸爸在" + String(repeating: "克里", count: 60)
        XCTAssertEqual(TranscriptRepetition.trimmed(looped), "是爸爸在克里")
        let words = "we need to " + Array(repeating: "push the button", count: 9).joined(separator: " ") + " now"
        XCTAssertEqual(TranscriptRepetition.trimmed(words), "we need to push the button now")
        XCTAssertEqual(TranscriptRepetition.trimmed("好" + String(repeating: "的", count: 30) + "。"), "好的。")
        XCTAssertEqual(TranscriptRepetition.trimmed("Thank you. Thank you. Thank you. Thank you. Thank you. Thank you. Thank you."), "Thank you.")
    }

    func testOrdinaryRepetitionIsKept() {
        for text in ["對對對，我知道", "哈哈哈哈哈哈", "no no no no, not that one", "一個一個慢慢來", "謝謝謝謝",
                     "我覺得我覺得這個可以", "very very very good", "記得把 Docker Image Push 到 Registry。",
                     "cancel cancel cancel cancel cancel cancel cancel"] {
            XCTAssertNil(TranscriptRepetition.trimmed(text), text)
        }
    }

    func testLoopTrimmingIsMarkedOnTheTranscript() async throws {
        let engine = ScriptedSpeech(id: "qwen3-asr:test", outputs: ["zh": "是爸爸在" + String(repeating: "克里", count: 40)])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(language: "zh"),
                                                              config: qwen, policy: zhEnUser)
        XCTAssertEqual(result.text, "是爸爸在克里")
        XCTAssertEqual(result.adjustments, [.repetitionTrimmed])
    }

    // MARK: Language

    func testScriptProfileFlagsLanguagesOutsideTheUsersLanguages() {
        let expected: Set<String> = ["en", "zh"]
        XCTAssertTrue(ScriptProfile("Забавно, що вони так добре використовують свої власні слова.").isImplausible(expected: expected))
        XCTAssertTrue(ScriptProfile("これは日本語の文章です").isImplausible(expected: expected))
        XCTAssertTrue(ScriptProfile("안녕하세요 반갑습니다").isImplausible(expected: expected))
        XCTAssertFalse(ScriptProfile("我等一下把 PR merge 到 main branch").isImplausible(expected: expected))
        XCTAssertFalse(ScriptProfile("Please merge the pull request.").isImplausible(expected: expected))
        XCTAssertFalse(ScriptProfile("これは日本語の文章です").isImplausible(expected: ["en", "ja"]))
        XCTAssertFalse(ScriptProfile("Привет").isImplausible(expected: ["ru", "en"]))
        XCTAssertFalse(ScriptProfile("12345 !!!").isImplausible(expected: expected))
    }

    func testExpectedLanguagesFollowSystemPreferenceAndAlwaysIncludeEnglish() {
        XCTAssertEqual(LocalASROutputGuard.expectedLanguages(preferred: ["en-TW", "zh-Hant-TW"]), ["en", "zh"])
        XCTAssertEqual(LocalASROutputGuard.expectedLanguages(preferred: ["zh-Hant-TW"]), ["zh", "en"])
        XCTAssertEqual(LocalASROutputGuard.expectedLanguages(preferred: ["zh-Hant-HK", "ja-JP"]), ["yue", "zh", "ja", "en"])
        XCTAssertEqual(LocalASROutputGuard.expectedLanguages(preferred: ["not a locale!"]), ["en"])
    }

    func testAutoResultInUnexpectedScriptIsDecodedAgainWithTheUsersLanguage() async throws {
        let engine = ScriptedSpeech(id: "qwen3-asr:test", outputs: [
            nil: "Забавно, що вони так добре використовують свої власні слова.",
            "zh": "現在把這斯克里亞的push到這邊去。",
        ])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                              config: qwen, policy: zhEnUser)
        XCTAssertEqual(result.text, "現在把這斯克里亞的push到這邊去。")
        XCTAssertEqual(result.adjustments, [.languageRetried])
        let requested = await engine.requestedLanguages
        XCTAssertEqual(requested, [nil, "zh"], "English is the user's first language but would drop Chinese; zh is preferred")
    }

    func testLanguageRetryKeepsTheOriginalWhenItIsNotMorePlausible() async throws {
        let engine = ScriptedSpeech(id: "qwen3-asr:test", outputs: [nil: "Привет, как дела", "zh": "Привет"])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                              config: qwen, policy: zhEnUser)
        XCTAssertEqual(result.text, "Привет, как дела")
        XCTAssertEqual(result.adjustments, [])
    }

    func testExplicitLanguageAndExpectedScriptsAreNeverRetried() async throws {
        let cyrillic = ScriptedSpeech(id: "qwen3-asr:test", outputs: ["zh": "Привет"])
        _ = try await LocalASROutputGuard.transcribe(engine: cyrillic, samples: audible, hints: .init(language: "zh"),
                                                     config: ASRConfig(kind: .qwen3, language: "zh"), policy: zhEnUser)
        let explicitRequests = await cyrillic.requestedLanguages
        XCTAssertEqual(explicitRequests, ["zh"], "A user-selected language is never overridden")

        let mixed = ScriptedSpeech(id: "qwen3-asr:test", outputs: [nil: "我等一下把 PR merge 到 main branch"])
        let result = try await LocalASROutputGuard.transcribe(engine: mixed, samples: audible, hints: .init(),
                                                              config: qwen, policy: zhEnUser)
        let mixedRequests = await mixed.requestedLanguages
        XCTAssertEqual(mixedRequests, [nil])
        XCTAssertEqual(result.adjustments, [])
    }

    func testEnginesWithoutLanguageControlAreNotRetried() async throws {
        // FireRedASR2 ignores the language setting, so a retry could not change anything.
        let engine = ScriptedSpeech(id: "sherpa-onnx:fireRed", outputs: [nil: "Привет, как дела у тебя"])
        _ = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                     config: ASRConfig(kind: .fireRed), policy: zhEnUser)
        let requests = await engine.requestedLanguages
        XCTAssertEqual(requests, [nil])
    }

    func testProbableTranslationIsDecodedAgainInTheSpokenLanguage() async throws {
        let engine = ScriptedSpeech(id: "whisperkit:test", outputs: [
            nil: "So Candy Crush is a kill time, very good.",
            "zh": "所以candy crush就是一個kill time，很好。",
        ], probabilities: ["en": 0.55, "zh": 0.43])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                              config: whisper, policy: zhEnUser)
        XCTAssertEqual(result.text, "所以candy crush就是一個kill time，很好。")
        XCTAssertEqual(result.adjustments, [.languageRetried])
    }

    func testEnglishSpeechIsKeptWhenChineseIsUnlikely() async throws {
        let engine = ScriptedSpeech(id: "whisperkit:test", outputs: [
            nil: "Please merge the pull request after the tests pass.", "zh": "請在測試通過後合併拉取請求。",
        ], probabilities: ["en": 0.97, "zh": 0.02])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                              config: whisper, policy: zhEnUser)
        XCTAssertEqual(result.text, "Please merge the pull request after the tests pass.")
        let requests = await engine.requestedLanguages
        XCTAssertEqual(requests, [nil], "No second decode without audio evidence of Chinese")
    }

    func testTranslationRetryWithoutChineseKeepsTheOriginal() async throws {
        let engine = ScriptedSpeech(id: "whisperkit:test", outputs: [
            nil: "Actually, I love swimming.", "zh": "Actually, I love swimming.",
        ], probabilities: ["en": 0.6, "zh": 0.35])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                              config: whisper, policy: zhEnUser)
        XCTAssertEqual(result.text, "Actually, I love swimming.")
        XCTAssertEqual(result.adjustments, [])
    }

    // MARK: Empty output

    func testEmptyResultOnAudibleAudioGetsOneRelaxedRetry() async throws {
        let engine = ScriptedSpeech(id: "whisperkit:test", outputs: [nil: ""], relaxed: "基本上都是一些business related的project。")
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(language: "zh"),
                                                              config: ASRConfig(kind: .whisperKit, language: "zh"), policy: zhEnUser)
        XCTAssertEqual(result.text, "基本上都是一些business related的project。")
        XCTAssertEqual(result.adjustments, [.emptyRetried])
        let relaxedCalls = await engine.relaxedCalls
        XCTAssertEqual(relaxedCalls, 1)
    }

    func testQuietAudioAndHallucinatedRetriesStayEmpty() async throws {
        let quiet = [Float](repeating: 0.001, count: 32_000)
        let engine = ScriptedSpeech(id: "whisperkit:test", outputs: [nil: ""], relaxed: "Thank you.")
        let silentResult = try await LocalASROutputGuard.transcribe(engine: engine, samples: quiet, hints: .init(language: "zh"),
                                                                    config: ASRConfig(kind: .whisperKit, language: "zh"), policy: zhEnUser)
        XCTAssertTrue(silentResult.isEmpty)
        let quietCalls = await engine.relaxedCalls
        XCTAssertEqual(quietCalls, 0, "Room noise never triggers a relaxed decode")

        let hallucinated = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(language: "zh"),
                                                                    config: ASRConfig(kind: .whisperKit, language: "zh"), policy: zhEnUser)
        XCTAssertTrue(hallucinated.isEmpty)
        XCTAssertEqual(hallucinated.adjustments, [])
    }

    func testRetriesAreSkippedWhenTheFirstDecodeWasSlowAndFailuresKeepTheFirstResult() async throws {
        let slow = ScriptedSpeech(id: "whisperkit:test", outputs: [nil: ""], relaxed: "late text", latencyMs: 30_000)
        let slowResult = try await LocalASROutputGuard.transcribe(engine: slow, samples: audible, hints: .init(language: "zh"),
                                                                  config: ASRConfig(kind: .whisperKit, language: "zh"), policy: zhEnUser)
        XCTAssertTrue(slowResult.isEmpty)
        let slowCalls = await slow.relaxedCalls
        XCTAssertEqual(slowCalls, 0)

        let failing = ScriptedSpeech(id: "qwen3-asr:test", outputs: [nil: "Привет, как дела"], failExplicit: true)
        let kept = try await LocalASROutputGuard.transcribe(engine: failing, samples: audible, hints: .init(),
                                                            config: qwen, policy: zhEnUser)
        XCTAssertEqual(kept.text, "Привет, как дела")
    }

    func testCloudEnginesPassThroughUntouched() async throws {
        let engine = ScriptedSpeech(id: "openai:test", outputs: [nil: "是爸爸在" + String(repeating: "克里", count: 40)])
        let result = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(),
                                                              config: ASRConfig(kind: .openAI), policy: zhEnUser)
        XCTAssertEqual(result.adjustments, [])
        XCTAssertTrue(result.text.hasSuffix("克里克里"))
    }

    func testCancellationDuringARetryPropagates() async throws {
        let engine = ScriptedSpeech(id: "qwen3-asr:test", outputs: [nil: "Привет, как дела"], cancelExplicit: true)
        do {
            _ = try await LocalASROutputGuard.transcribe(engine: engine, samples: audible, hints: .init(), config: qwen, policy: zhEnUser)
            XCTFail("Cancellation must not be swallowed by the best-effort retry")
        } catch is CancellationError {}
    }
}

/// Returns scripted text per requested language; nil keys the Auto request.
private actor ScriptedSpeech: LocalASRGuardSupport {
    nonisolated let id: String
    private let outputs: [String?: String]
    private let probabilities: [String: Double]?
    private let relaxed: String?
    private let latencyMs: Int
    private let failExplicit: Bool
    private let cancelExplicit: Bool
    private(set) var requestedLanguages: [String?] = []
    private(set) var relaxedCalls = 0

    init(id: String, outputs: [String?: String], probabilities: [String: Double]? = nil, relaxed: String? = nil,
         latencyMs: Int = 300, failExplicit: Bool = false, cancelExplicit: Bool = false) {
        self.id = id
        self.outputs = outputs
        self.probabilities = probabilities
        self.relaxed = relaxed
        self.latencyMs = latencyMs
        self.failExplicit = failExplicit
        self.cancelExplicit = cancelExplicit
    }

    func prepare() async throws {}

    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        requestedLanguages.append(hints.language)
        if hints.language != nil, requestedLanguages.count > 1 {
            if cancelExplicit { throw CancellationError() }
            if failExplicit { throw TranscriberError.invalidResponse }
        }
        return Transcript(text: outputs[hints.language] ?? "", language: hints.language, engine: id, latencyMs: latencyMs)
    }

    func transcribeAfterEmptyResult(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        relaxedCalls += 1
        return Transcript(text: relaxed ?? "", language: hints.language, engine: id, latencyMs: latencyMs)
    }

    func spokenLanguageProbabilities(samples: [Float]) async throws -> [String: Double]? { probabilities }
}
