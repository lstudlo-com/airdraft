import XCTest
@testable import AirdraftCore

final class SpeechLanguagePolicyTests: XCTestCase {
    /// Cohere's legacy Auto requires an explicit language; Mandarin aliases pass and Cantonese does not;
    /// an unknown checkpoint still cannot bypass the runtime language requirements.
    func testCohereRequiresAnExplicitSupportedLanguageEvenForUnknownCheckpoints() throws {
        do {
            for language in ["", "auto", " AUTO "] {
                let config = ASRConfig(kind: .cohere, language: language)
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(config)) { error in
                    XCTAssertEqual(error as? SpeechLanguageError, .automaticUnavailable(model: "Cohere Transcribe"))
                    XCTAssertTrue(error.localizedDescription.contains("Models"))
                }
            }
        }
        do {
            for language in ["zh", "zh-Hant", "zh_TW", " ZH-CN ", "cmn"] {
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .cohere, language: language)).language, "zh")
            }
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .cohere, language: "yue")))
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .cohere, language: "zz")))
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .cohere, language: "zh-HK")))
        }
        do {
            var config = ASRConfig(kind: .cohere, cohereModel: "custom/cohere-new")
            XCTAssertNil(SpeechLanguagePolicy.capabilities(for: config).supportedLanguages)
            XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: config).supportsAutomatic, false)
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(config))
            config.language = "zz"
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(config))
            config.language = "zh"
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "zh")
        }
    }

    /// Parakeet validates intent without pretending to force the decoder; SenseVoice accepts its five
    /// languages and canonical Cantonese, while the AD-083 Cantonese artifact (a 2025-09-09 fine-tune that
    /// wrote no kana for Japanese, CER 76%, and lost most Korean, 77%) does not claim them; FireRed uses joint
    /// recognition; Qwen variants use their exact language set and aliases.
    func testLocalModelsUseTheirExactLanguageSets() throws {
        do {
            let capabilities = SpeechLanguagePolicy.capabilities(for: ASRConfig(kind: .parakeet))
            XCTAssertEqual(capabilities.supportedLanguages?.count, 25)
            XCTAssertEqual(capabilities.manualControl, .notApplied)
            for language in ["zh", "zh-Hant", "yue"] {
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .parakeet, language: language)))
            }
            let resolved = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .parakeet, language: "de-DE"))
            XCTAssertEqual(resolved.requestedLanguage, "de")
            XCTAssertNil(resolved.language)
            XCTAssertFalse(resolved.isAutomatic)
            XCTAssertNil(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .parakeet)).language)
        }
        do {
            XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: ASRConfig(kind: .senseVoiceMultilingual)).supportedLanguages,
                           ["en", "ja", "ko", "yue", "zh"])
            for language in ["en", "ja", "ko", "yue", "zh"] {
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .senseVoiceMultilingual, language: language)).language, language)
            }
            for kind in [ASRProviderKind.senseVoiceMultilingual, .senseVoice] {
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: kind, language: "yue-HK")).language, "yue")
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: kind, language: "zh-yue")).language, "yue")
                XCTAssertNil(try SpeechLanguagePolicy.resolve(ASRConfig(kind: kind, language: "auto")).language)
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: kind, language: "fr")))
            }
        }
        do {
            let cantonese = SpeechLanguagePolicy.capabilities(for: ASRConfig(kind: .senseVoice))
            XCTAssertEqual(cantonese.modelName, "SenseVoice Cantonese")
            XCTAssertEqual(cantonese.supportedLanguages, ["en", "yue", "zh"])
            XCTAssertEqual(cantonese.manualControl, .forced)
            XCTAssertEqual(cantonese.supportsAutomatic, true)
            for language in ["ja", "ko"] {
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .senseVoice, language: language))) { error in
                    XCTAssertEqual(error as? SpeechLanguageError,
                                   .unsupportedLanguage(language: language, model: "SenseVoice Cantonese"))
                }
            }
            for language in ["en", "yue", "zh"] {
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .senseVoice, language: language)).language, language)
            }
            XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: ASRConfig(kind: .senseVoiceMultilingual)).modelName, "SenseVoice")
        }
        do {
            for language in ["", "zh", "en"] {
                XCTAssertNil(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .fireRed, language: language)).language)
            }
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .fireRed, language: "ja")))
        }
        do {
            for model in ["aufklarer/Qwen3-ASR-1.7B-MLX-5bit", "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"] {
                let config = ASRConfig(kind: .qwen3, qwen3Model: model, language: "tl")
                XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: config).supportedLanguages?.count, 30)
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "fil")
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .qwen3, qwen3Model: model, language: "uk")))
            }
        }
    }

    /// Apple uses its configured locale and never claims Auto; invalid syntax never becomes English;
    /// resolving never changes the saved language or provider binding.
    func testAppleLocaleInvalidCodesAndResolutionLeaveSavedSettingsAlone() throws {
        do {
            for config in [ASRConfig(kind: .apple, appleLocale: "ja-JP"),
                           ASRConfig(kind: .apple, appleLocale: "ja-JP", language: "en"),
                           ASRConfig(kind: .apple, appleLocale: "zh-HK", language: "zh-HK")] {
                let resolved = try SpeechLanguagePolicy.resolve(config)
                XCTAssertEqual(resolved.language, config.effectiveAppleLocale)
                XCTAssertEqual(resolved.capabilities.manualControl, .locale)
                XCTAssertEqual(resolved.capabilities.supportsAutomatic, false)
                XCTAssertFalse(resolved.isAutomatic)
            }
        }
        do {
            for language in ["English please", "zh/en", "<|en|>", "z", "en--US", "123"] {
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .openAICompatible, language: language))) { error in
                    XCTAssertEqual(error as? SpeechLanguageError, .invalidCode(language))
                }
            }
        }
        do {
            let config = ASRConfig(kind: .parakeet, language: "de-DE")
            let original = config
            _ = try SpeechLanguagePolicy.resolve(config)
            XCTAssertEqual(config, original)
        }
    }

    /// Deepgram multilingual is not Mandarin Auto; Nova-3 keeps its documented regional languages; the
    /// native cloud policy follows the model the existing fallback selects; Whisper versions do not share
    /// Cantonese token support.
    func testDeepgramAndWhisperModelsResolveTheirOwnLanguageCodes() throws {
        do {
            for language in ["zh", "yue", "ko"] {
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3-multilingual", language: language)))
            }
            let multi = ASRConfig(kind: .deepgram, model: "nova-3-multilingual", language: "en")
            XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: multi).supportedLanguages?.count, 10)
            XCTAssertNil(try SpeechLanguagePolicy.resolve(multi).language)
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3", language: "zh-HK")).language, "yue")
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3", language: "zh")).language, "zh")
        }
        do {
            // Nova-3's complete regional/script list, excluding Cantonese's separate
            // yue -> zh-HK adapter mapping. Source: Deepgram models-languages-overview.
            let locales = [
                "af-ZA", "ar-AE", "ar-SA", "ar-QA", "ar-KW", "ar-SY", "ar-LB", "ar-PS", "ar-JO",
                "ar-EG", "ar-SD", "ar-TD", "ar-MA", "ar-DZ", "ar-TN", "ar-IQ", "ar-IR", "as-IN",
                "zh-CN", "zh-Hans", "zh-TW", "zh-Hant", "cs-CZ", "da-DK", "en-US", "en-AU",
                "en-GB", "en-IN", "en-NZ", "nl-BE", "fr-CA", "ka-GE", "de-CH", "gu-IN", "kk-KZ",
                "ko-KR", "ps-AF", "pt-BR", "pt-PT", "pa-IN", "es-419", "sv-SE", "th-TH", "tr-TR"
            ]
            for locale in locales {
                var config = ASRConfig(kind: .deepgram, model: "nova-3",
                                       language: " \(locale.lowercased().replacingOccurrences(of: "-", with: "_")) ")
                let resolved = try SpeechLanguagePolicy.resolve(config)
                XCTAssertEqual(resolved.language, locale)
                XCTAssertEqual(resolved.requestedLanguage, try SpeechLanguagePolicy.canonicalLanguage(locale))
                config.language = try XCTUnwrap(resolved.language)
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(config), resolved,
                               "Factory and adapter resolution must preserve \(locale)")
            }
            // Regional variants of other models do not inherit Nova-3's wire codes.
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "whisper-large", language: "fr-CA")).language, "fr")
            XCTAssertNil(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3-multilingual", language: "en-GB")).language)
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3", language: "en-CA")).language, "en")
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3", language: "cy-GB")))
        }
        do {
            let config = ASRConfig(kind: .deepgram, model: "unknown-old-selection", language: "zh")
            XCTAssertEqual(config.speechModelID, "nova-3")
            XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: config),
                           SpeechLanguagePolicy.capabilities(for: ASRConfig(kind: .deepgram, model: "nova-3")))
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "zh")
        }
        do {
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .whisperKit, language: "yue")).language, "yue")
            XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: ASRConfig(kind: .whisperKit)).supportedLanguages?.count, 100)
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "whisper-large", language: "yue")))
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .groq, model: "whisper-large-v3", language: "fil")).language, "tl")
        }
    }

    /// OpenRouter uses exact checkpoint restrictions; known cloud hints remain hints; unknown models and
    /// custom endpoints are allowed without assumed capabilities.
    func testCloudCheckpointsHintsAndUnknownModelsKeepTheirCapabilities() throws {
        do {
            for model in ["nvidia/parakeet-tdt-0.6b-v3", "mistralai/voxtral-small-24b-2507-stt", "mistralai/voxtral-mini-3b-2507"] {
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .openRouter, model: model, language: "zh")))
            }
            for model in ["mistralai/voxtral-mini-transcribe", "mistralai/voxtral-mini-3b-2507-new", "x-ai/grok-stt-1.0"] {
                let config = ASRConfig(kind: .openRouter, model: model, language: "zh")
                XCTAssertNil(SpeechLanguagePolicy.capabilities(for: config).supportedLanguages)
                XCTAssertNil(SpeechLanguagePolicy.capabilities(for: config).supportsAutomatic)
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "zh")
            }
            let fish = ASRConfig(kind: .openRouter, model: "fish-audio/transcribe-1-pro", language: "zh")
            XCTAssertNil(try SpeechLanguagePolicy.resolve(fish).language)
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(fish).requestedLanguage, "zh")
        }
        do {
            for config in [ASRConfig(kind: .soniox, model: "stt-async-v5", language: "zh"),
                           ASRConfig(kind: .elevenLabs, model: "scribe_v2", language: "zh"),
                           ASRConfig(kind: .openAI, model: "gpt-transcribe", language: "zh")] {
                XCTAssertEqual(SpeechLanguagePolicy.capabilities(for: config).manualControl, .hint)
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "zh")
            }
        }
        do {
            for config in [ASRConfig(kind: .openAICompatible, baseURL: "http://localhost:8787/v1", model: "nvidia/parakeet-tdt-0.6b-v3", language: "zh"),
                           ASRConfig(kind: .qwen3, qwen3Model: "custom/Qwen3-ASR-new", language: "uk")] {
                let capabilities = SpeechLanguagePolicy.capabilities(for: config)
                XCTAssertNil(capabilities.supportedLanguages)
                XCTAssertNil(capabilities.supportsAutomatic)
                XCTAssertEqual(capabilities.manualControl, .unknown)
                XCTAssertNoThrow(try SpeechLanguagePolicy.resolve(config))
            }
        }
    }
}
