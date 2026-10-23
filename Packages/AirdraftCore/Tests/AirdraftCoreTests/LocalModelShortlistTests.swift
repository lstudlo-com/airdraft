import XCTest
@testable import AirdraftCore

/// AD-071: Models opens with a compact recommended set instead of the catalogue.
final class LocalModelShortlistTests: XCTestCase {
    private let gib: UInt64 = 1 << 30

    private func picks(_ code: String?, _ memory: UInt64) -> [LocalModelShortlist.Pick] {
        LocalModelShortlist.make(languageCode: code, physicalMemory: memory).picks
    }

    func testEachLanguageAndMemoryGetsADeterministicCuratedSet() {
        typealias P = LocalModelShortlist.Pick
        let cases: [(String?, UInt64, [P])] = [
            ("zh-Hant-TW", 16 * gib, [P(id: "qwen3:1.7b", role: .recommended), P(id: "sherpa:senseVoice", role: .faster),
                                      P(id: "sherpa:fireRed", role: .mandarin)]),
            ("zh-Hans", 8 * gib, [P(id: "sherpa:senseVoice", role: .recommended), P(id: "qwen3:1.7b", role: .mixedChineseEnglish),
                                  P(id: "sherpa:fireRed", role: .mandarin)]),
            ("en-US", 16 * gib, [P(id: "sherpa:senseVoice", role: .recommended), P(id: "coreml:parakeet-v2", role: .singleLanguage),
                                 P(id: "whisper:turbo", role: .multilingual)]),
            ("ja-JP", 8 * gib, [P(id: "sherpa:senseVoice", role: .recommended), P(id: "coreml:parakeet-ja", role: .singleLanguage),
                                P(id: "whisper:turbo", role: .multilingual)]),
            ("ko", 16 * gib, [P(id: "sherpa:senseVoice", role: .recommended), P(id: "whisper:turbo", role: .multilingual)]),
            ("fr-FR", 16 * gib, [P(id: "whisper:turbo", role: .recommended), P(id: "coreml:parakeet-v3", role: .smaller),
                                 P(id: "whisper:large-v3", role: .fullSize)]),
            ("de", 8 * gib, [P(id: "whisper:turbo", role: .recommended), P(id: "coreml:parakeet-v3", role: .smaller)]),
            ("th", 32 * gib, [P(id: "whisper:turbo", role: .recommended), P(id: "whisper:large-v3", role: .fullSize)]),
            ("th", 8 * gib, [P(id: "whisper:turbo", role: .recommended)]),
            (nil, 16 * gib, [P(id: "whisper:turbo", role: .recommended), P(id: "whisper:large-v3", role: .fullSize)]),
        ]
        for (code, memory, expected) in cases {
            let label = "\(code ?? "nil") \(memory / gib) GB"
            XCTAssertEqual(picks(code, memory), expected, label)
            XCTAssertEqual(picks(code, memory), picks(code, memory), label)
        }
    }

    func testTheRecommendationLeadsAndAlternativesAreCappedAndDistinct() {
        for code in ["zh", "zh-HK", "en", "ja", "ko", "es", "pt-BR", "vi", "ar", "", nil] as [String?] {
            for memory in [4 * gib, 8 * gib, 8 * gib + 1, 16 * gib, 128 * gib] {
                let shortlist = LocalModelShortlist.make(languageCode: code, physicalMemory: memory)
                let label = "\(code ?? "nil") \(memory)"
                XCTAssertEqual(shortlist.recommendation,
                               LocalSpeechRecommendation.recommend(languageCode: code, physicalMemory: memory), label)
                XCTAssertEqual(shortlist.picks.first, .init(id: shortlist.recommendation.model.catalogueID, role: .recommended), label)
                XCTAssertLessThanOrEqual(shortlist.picks.count, 1 + LocalModelShortlist.maximumAlternatives, label)
                XCTAssertEqual(Set(shortlist.ids).count, shortlist.ids.count, label)
                XCTAssertEqual(shortlist.picks.dropFirst().filter { $0.role == .recommended }, [], label)
                // The recommendation's own alternatives are always kept.
                for alternative in shortlist.recommendation.alternatives {
                    XCTAssertTrue(shortlist.ids.contains(alternative.catalogueID), label)
                }
                // AD-074: Qwen3-ASR 0.6B is never offered as the lighter choice.
                XCTAssertFalse(shortlist.ids.contains("qwen3:0.6b"), label)
            }
        }
    }

    func testLargeAlternativesAreSkippedOnEightGigabyteMacs() {
        XCTAssertTrue(picks("fr", 16 * gib).map(\.id).contains("whisper:large-v3"))
        XCTAssertFalse(picks("fr", 8 * gib).map(\.id).contains("whisper:large-v3"))
        XCTAssertFalse(picks("fr", 4 * gib).map(\.id).contains("whisper:large-v3"))
    }

    func testModelsInUseAreAddedOnceInCatalogueOrder() {
        let shortlist = LocalModelShortlist.make(languageCode: "zh-Hant", physicalMemory: 16 * gib)
        let catalogue = ["qwen3:1.7b", "qwen3:0.6b", "sherpa:fireRed", "cohere", "sherpa:senseVoice", "gguf:moonshine-tiny"]
        // The default (Cohere), a profile binding (Moonshine) and an installed
        // shortlist model: only models the shortlist does not show are added.
        let inUse: Set = ["gguf:moonshine-tiny", "cohere", "qwen3:1.7b"]
        XCTAssertEqual(shortlist.inUse(catalogueOrder: catalogue, inUse: inUse), ["cohere", "gguf:moonshine-tiny"])
        XCTAssertEqual(shortlist.inUse(catalogueOrder: catalogue, inUse: []), [])
        XCTAssertEqual(shortlist.inUse(catalogueOrder: catalogue, inUse: ["unknown"]), [])
    }

    func testLanguageListsUseFullNamesWithTheUsersLanguageFirst() {
        let name: (String) -> String = { ["zh": "Mandarin Chinese", "en": "English", "ja": "Japanese", "ko": "Korean",
                                          "yue": "Cantonese"][$0] ?? $0.uppercased() }
        let senseVoice = ["en", "ja", "ko", "yue", "zh"]
        let chinese = SpeechLanguageList(codes: senseVoice, preferredLanguage: "zh-Hant-TW", nameFor: name)
        XCTAssertEqual(chinese.shown, ["Mandarin Chinese", "English"])
        XCTAssertEqual(chinese.remaining, 3)
        XCTAssertEqual(chinese.names, ["Mandarin Chinese", "English", "Japanese", "Korean", "Cantonese"])
        let japanese = SpeechLanguageList(codes: senseVoice, preferredLanguage: "ja-JP", nameFor: name)
        XCTAssertEqual(japanese.shown, ["Japanese", "English"])
        let english = SpeechLanguageList(codes: ["af", "ar", "en", "zh"], preferredLanguage: "en-US", nameFor: name)
        XCTAssertEqual(english.shown, ["English", "Mandarin Chinese"])
        XCTAssertEqual(english.remaining, 2)
        let unsupported = SpeechLanguageList(codes: ["en"], preferredLanguage: "zh", nameFor: name)
        XCTAssertEqual(unsupported.shown, ["English"])
        XCTAssertEqual(unsupported.remaining, 0)
        let qwen = SpeechLanguageList.supported(by: ASRConfig(kind: .qwen3), preferredLanguage: "en")
        XCTAssertEqual(qwen?.names.count, 30)
        XCTAssertEqual(qwen?.remaining, 28)
        XCTAssertNil(SpeechLanguageList.supported(by: ASRConfig(kind: .apple), preferredLanguage: "en"))
    }

    @MainActor func testShowAllModelsChoiceIsRememberedWithoutCountingAsAnExistingSetup() {
        let suite = "airdraft.shortlist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AppSettings(defaults: defaults).showsAllLocalModels)
        AppSettings(defaults: defaults).showsAllLocalModels = true
        let reopened = AppSettings(defaults: defaults)
        XCTAssertTrue(reopened.showsAllLocalModels)
        XCTAssertFalse(reopened.hadExistingSetup)
    }
}
