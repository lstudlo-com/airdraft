import XCTest
@testable import AirdraftCore

/// AD-074: first-run local speech recommendation by system language and memory.
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

    func testOtherLanguagesKeepTheirExistingRecommendationRegardlessOfMemory() {
        for memory in [8 * gib, 64 * gib] {
            for code in ["en", "en-US", "ja-JP", "ko"] {
                let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory)
                XCTAssertEqual(choice, .init(model: .senseVoice, reason: .systemLanguage, alternatives: []), code)
            }
            for code in ["de-DE", "fr", "yue", "", nil] as [String?] {
                let choice = LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory)
                XCTAssertEqual(choice, .init(model: .whisperTurbo, reason: .systemLanguage, alternatives: []), code ?? "nil")
            }
        }
    }

    func testNeverRecommendsQwenSmallAsALighterDefault() {
        // Qwen3-ASR 0.6B can loop until its token cap with a large memory spike.
        XCTAssertEqual(Set(LocalSpeechRecommendation.Model.allCases.map(\.rawValue)), ["qwen3Large", "senseVoice", "whisperTurbo"])
    }
}
