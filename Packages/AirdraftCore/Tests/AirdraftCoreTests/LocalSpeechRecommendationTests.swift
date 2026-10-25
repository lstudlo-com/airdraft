import XCTest
@testable import AirdraftCore

/// AD-074 and AD-083: first-run local speech recommendation by system language and memory.
final class LocalSpeechRecommendationTests: XCTestCase {
    private let gib: UInt64 = 1 << 30

    func testChineseSystemLanguagesGetQwenLargeWithSenseVoiceAsTheSmallerChoice() {
        for code in ["zh", "zh-Hant", "zh-Hant-TW", "zh_TW", "zh-Hans-CN", "zh-HK", "ZH-hant"] {
            let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 16 * gib)
            XCTAssertEqual(choice.model, .qwen3Large, code)
            XCTAssertEqual(choice.reason, .mixedChineseEnglish, code)
            XCTAssertEqual(choice.alternatives, [.senseVoice], code)
        }
    }

    func testMacsWithEightGigabytesOrLessGetSenseVoiceAndStillOfferQwen() {
        for memory in [8 * gib, 8 * gib - 1, 4 * gib] {
            let choice = LocalSpeechRecommendation.recommend(languageCode: "zh-Hant", physicalMemory: memory)
            XCTAssertEqual(choice.model, .senseVoice)
            XCTAssertEqual(choice.reason, .limitedMemory)
            XCTAssertEqual(choice.alternatives, [.qwen3Large])
        }
        XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: "zh", physicalMemory: 8 * gib + 1).model, .qwen3Large)
    }

    /// AD-083: English gets Parakeet TDT v2 on every Mac, with Qwen3-ASR 1.7B
    /// for speakers who also use other languages.
    func testEnglishGetsParakeetWithQwenAsTheMultilingualChoice() {
        for memory in [4 * gib, 8 * gib, 64 * gib] {
            for code in ["en", "en-US", "en-GB", "EN_au"] {
                let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory)
                XCTAssertEqual(choice, .init(model: .parakeetEnglish, reason: .systemLanguage, alternatives: [.qwen3Large]), code)
            }
        }
    }

    /// AD-083: Japanese and Korean get Qwen3-ASR 1.7B, or Whisper Large v3 Turbo
    /// on Macs with 8 GB or less. The shipped SenseVoice is never offered for them.
    func testJapaneseAndKoreanGetQwenOrWhisperOnEightGigabyteMacs() {
        for code in ["ja", "ja-JP", "ko", "ko-KR", "ko_KR"] {
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 16 * gib),
                           .init(model: .qwen3Large, reason: .systemLanguage, alternatives: [.whisperTurbo]), code)
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 8 * gib + 1).model, .qwen3Large, code)
            for memory in [8 * gib, 8 * gib - 1, 4 * gib] {
                XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory),
                               .init(model: .whisperTurbo, reason: .limitedMemory, alternatives: [.qwen3Large]), code)
            }
        }
        for code in ["en", "ja", "ko"] {
            for memory in [4 * gib, 8 * gib, 16 * gib] {
                let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory)
                XCTAssertFalse(([choice.model] + choice.alternatives).contains(.senseVoice), code)
            }
        }
    }

    /// AD-098: Spanish, French and Portuguese get Qwen3-ASR 1.7B, or Parakeet TDT v3
    /// (Core ML) on Macs with 8 GB or less.
    func testSpanishFrenchAndPortugueseGetQwenOrParakeetOnEightGigabyteMacs() {
        for code in ["es", "es-419", "es-ES", "fr", "fr-FR", "fr-CA", "pt", "pt-BR", "pt_PT"] {
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 16 * gib),
                           .init(model: .qwen3Large, reason: .systemLanguage, alternatives: [.parakeetEuropean]), code)
            for memory in [8 * gib, 4 * gib] {
                XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory),
                               .init(model: .parakeetEuropean, reason: .limitedMemory, alternatives: [.qwen3Large]), code)
            }
        }
    }

    /// AD-098: Russian gets Qwen3-ASR 1.7B, or GigaAM v3 on Macs with 8 GB or less.
    func testRussianGetsQwenOrGigaAMOnEightGigabyteMacs() {
        for code in ["ru", "ru-RU"] {
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 16 * gib),
                           .init(model: .qwen3Large, reason: .systemLanguage, alternatives: [.gigaAMRussian]), code)
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 8 * gib),
                           .init(model: .gigaAMRussian, reason: .limitedMemory, alternatives: [.qwen3Large]), code)
        }
    }

    /// AD-098: Arabic and Indonesian follow the Japanese and Korean rule; Hindi
    /// keeps Qwen3-ASR on every Mac because Whisper doubled its errors.
    func testArabicIndonesianAndHindi() {
        for code in ["ar", "ar-EG", "ar-SA", "id", "id-ID"] {
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 16 * gib),
                           .init(model: .qwen3Large, reason: .systemLanguage, alternatives: [.whisperTurbo]), code)
            XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: 8 * gib),
                           .init(model: .whisperTurbo, reason: .limitedMemory, alternatives: [.qwen3Large]), code)
        }
        for memory in [4 * gib, 8 * gib, 64 * gib] {
            for code in ["hi", "hi-IN"] {
                XCTAssertEqual(LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory),
                               .init(model: .qwen3Large, reason: .systemLanguage, alternatives: [.whisperTurbo]), code)
            }
        }
    }

    /// Languages without a measured rule keep the documented default.
    func testUnmeasuredLanguagesKeepWhisperTurboRegardlessOfMemory() {
        for memory in [8 * gib, 64 * gib] {
            for code in ["de-DE", "it", "th", "vi", "tr", "yue", "", nil] as [String?] {
                let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory)
                XCTAssertEqual(choice, .init(model: .whisperTurbo, reason: .systemLanguage, alternatives: []), code ?? "nil")
                XCTAssertNil(LocalSpeechRecommendation.rule(for: code).evidence, code ?? "nil")
            }
        }
    }

    /// The table: every measured language names its evidence, uses the shared
    /// 8 GB threshold, keeps its own choices and alternatives distinct, and makes
    /// the "most accurate in Airdraft's tests" claim only where it was measured.
    func testRuleTableIsConsistent() {
        XCTAssertEqual(Set(LocalSpeechRecommendation.rules.keys),
                       ["zh", "en", "ja", "ko", "es", "fr", "pt", "ru", "ar", "hi", "id"])
        for (language, rule) in LocalSpeechRecommendation.rules {
            XCTAssertNotNil(rule.evidence, language)
            XCTAssertEqual(rule.memoryThreshold, LocalSpeechRecommendation.limitedMemoryBytes, language)
            for choice in [rule.choice, rule.limitedMemoryChoice].compactMap({ $0 }) {
                let models = [choice.model] + choice.alternatives.map(\.model)
                XCTAssertEqual(Set(models).count, models.count, language)
                XCTAssertFalse(choice.alternatives.contains { $0.role == .recommended }, language)
            }
            if let limited = rule.limitedMemoryChoice {
                XCTAssertEqual(limited.reason, .limitedMemory, language)
                XCTAssertFalse(limited.isMostAccurate, language)
            }
        }
        let claims = LocalSpeechRecommendation.rules.filter { $0.value.choice.isMostAccurate }.keys
        // Spanish (Voxtral Mini 4B), Portuguese (Canary 1B v2, Voxtral) and Arabic
        // (Cohere Transcribe Arabic) had a model with a lower measured error.
        XCTAssertEqual(Set(claims), ["ja", "ko", "fr", "ru", "hi", "id"])
    }

    func testNeverRecommendsQwenSmallOrSenseVoiceCantonese() {
        // Qwen3-ASR 0.6B can loop until its token cap with a large memory spike;
        // the WSYue SenseVoice fine-tune lost Japanese and Korean (AD-083).
        XCTAssertEqual(Set(LocalSpeechRecommendation.Model.allCases.map(\.rawValue)),
                       ["qwen3Large", "senseVoice", "whisperTurbo", "parakeetEnglish", "parakeetEuropean", "gigaAMRussian"])
        XCTAssertEqual(LocalSpeechRecommendation.Model.allCases.map(\.catalogueID),
                       ["qwen3:1.7b", "sherpa:senseVoiceMultilingual", "whisper:turbo", "coreml:parakeet-v2",
                        "coreml:parakeet-v3", "gguf:gigaam-v3-e2e-rnnt"])
        let rules = Array(LocalSpeechRecommendation.rules.values) + [LocalSpeechRecommendation.unmeasuredRule(for: "de"),
                                                                       LocalSpeechRecommendation.unmeasuredRule(for: nil)]
        for rule in rules {
            let ids = [rule.choice, rule.limitedMemoryChoice].compactMap { $0 }
                .flatMap { [$0.model] + $0.alternatives.map(\.model) }.map(\.catalogueID) + rule.shortlist.map(\.id)
            XCTAssertFalse(ids.contains("qwen3:0.6b"))
            XCTAssertFalse(ids.contains("sherpa:senseVoice"))
        }
    }
}
