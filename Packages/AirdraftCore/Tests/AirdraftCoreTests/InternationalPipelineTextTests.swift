import XCTest
@testable import AirdraftCore

/// AD-098: per-language data outside the speech guards: Apple Speech regions,
/// the practice sentence and the refinement sample.
@MainActor
final class InternationalPipelineTextTests: XCTestCase {
    func testAppleSpeechLocaleForALanguageFollowsTheMacsRegion() {
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "en", region: "GB"), "en-GB")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "en", region: "IN"), "en-IN")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "en", region: "TW"), "en-US",
                       "English on a Taiwan Mac is American English, not an en-TW formatting locale")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "en", region: nil), "en-US")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "pt", region: "PT"), "pt-PT")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "pt", region: "BR"), "pt-BR")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "es", region: "MX"), "es-MX")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "fr", region: "CA"), "fr-CA")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "hi", region: "IN"), "hi-IN")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "es", region: "TW"), "es", "No Spanish locale in Taiwan: the OS decides")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "fr-BE", region: "CA"), "fr-BE", "A full locale is kept")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "ja", region: "US"), "ja-JP")
        XCTAssertEqual(AppleSpeechTranscriber.locale(forLanguage: "zh", region: "US"), "zh-TW")
        XCTAssertNil(AppleSpeechTranscriber.locale(forLanguage: "", region: "US"))
    }

    // MARK: - Practice sentence and refinement sample

    private let english = "Hello! I’m trying Airdraft for the first time, and it’s writing what I say."

    func testPracticeSentenceAndRefinementSampleFollowTheLanguage() {
        // The practice sentence uses the interface catalog for the interface language.
        do {
            let localized = "¡Hola! (catalog)"
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: "es"), interfaceLanguage: "es",
                                                     localized: localized), localized)
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: ""), interfaceLanguage: "es",
                                                     localized: localized, preferredLanguages: ["es-ES"]), localized)
        }

        // The practice sentence follows an explicit speech language.
        do {
            XCTAssertTrue(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: "ru"), interfaceLanguage: "en",
                                                    localized: english).hasPrefix("Здравствуйте"))
            XCTAssertTrue(PracticeSentence.sentence(for: ASRConfig(kind: .whisperKit, language: "hi"), interfaceLanguage: "en",
                                                    localized: english).hasPrefix("नमस्ते"))
            XCTAssertTrue(PracticeSentence.sentence(for: ASRConfig(kind: .apple, appleLocale: "fr-FR", language: ""),
                                                    interfaceLanguage: "en", localized: english).hasPrefix("Bonjour"))
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: "zh", chineseScript: .simplified),
                                                     interfaceLanguage: "en", localized: english), PracticeSentence.sentences["zh-Hans"])
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: "yue", chineseScript: .traditional),
                                                     interfaceLanguage: "es", localized: "x"), PracticeSentence.sentences["zh-Hant"])
            // Cantonese speakers read the Chinese interface's sentence.
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: "yue"), interfaceLanguage: "zh-Hant",
                                                     localized: "catalog"), "catalog")
            // A language without a sentence keeps the interface's.
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .whisperKit, language: "sw"), interfaceLanguage: "en",
                                                     localized: english), english)
        }

        // Under Auto the practice sentence uses a language the model recognizes.
        do {
            // Parakeet v3 recognizes 25 European languages, not Japanese.
            let parakeet = ASRConfig(kind: .parakeet, language: "")
            XCTAssertEqual(PracticeSentence.sentence(for: parakeet, interfaceLanguage: "ja", localized: "こんにちは（catalog）",
                                                     preferredLanguages: ["ja-JP", "de-DE"]), PracticeSentence.sentences["de"])
            XCTAssertEqual(PracticeSentence.sentence(for: parakeet, interfaceLanguage: "ja", localized: "こんにちは（catalog）",
                                                     preferredLanguages: ["ja-JP"]), english)
            XCTAssertEqual(PracticeSentence.sentence(for: ASRConfig(kind: .qwen3, language: ""), interfaceLanguage: "ja",
                                                     localized: "catalog", preferredLanguages: ["ja-JP"]), "catalog")
        }

        // Every practice sentence names the app.
        do {
            for (language, sentence) in PracticeSentence.sentences {
                XCTAssertTrue(sentence.contains("Airdraft"), language)
            }
        }

        // The refinement sample covers the new interface languages.
        do {
            let expectations = ["fr": "premièrement", "pt": "primeiro", "ru": "во-первых", "ar": "أولاً", "hi": "दूसरा",
                                "id": "pertama", "de": "erstens", "ko": "첫째", "it": "primo"]
            for (language, marker) in expectations {
                XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: language)).contains(marker), language)
            }
            XCTAssertTrue(RefinementSample.transcript(for: ASRConfig(language: ""), preferredLanguages: ["ru-RU"]).contains("тест"))
        }
    }
}
