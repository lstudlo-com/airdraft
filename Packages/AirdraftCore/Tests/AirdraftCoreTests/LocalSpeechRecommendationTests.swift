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

    func testOtherLanguagesKeepWhisperTurboRegardlessOfMemory() {
        for memory in [8 * gib, 64 * gib] {
            for code in ["de-DE", "fr", "yue", "", nil] as [String?] {
                let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory)
                XCTAssertEqual(choice, .init(model: .whisperTurbo, reason: .systemLanguage, alternatives: []), code ?? "nil")
            }
        }
    }

    func testNeverRecommendsQwenSmallAsALighterDefault() {
        // Qwen3-ASR 0.6B can loop until its token cap with a large memory spike.
        XCTAssertEqual(Set(LocalSpeechRecommendation.Model.allCases.map(\.rawValue)),
                       ["qwen3Large", "senseVoice", "whisperTurbo", "parakeetEnglish"])
        XCTAssertEqual(LocalSpeechRecommendation.Model.allCases.map(\.catalogueID),
                       ["qwen3:1.7b", "sherpa:senseVoice", "whisper:turbo", "coreml:parakeet-v2"])
    }
}
