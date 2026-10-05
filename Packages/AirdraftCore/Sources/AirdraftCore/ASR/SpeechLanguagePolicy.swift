import Foundation

/// What an explicit language selection does at this model's transcription boundary.
public enum SpeechLanguageManualControl: Sendable, Equatable {
    case forced
    case hint
    /// The model jointly recognizes its supported languages; no language parameter is sent.
    case notApplied
    case locale
    case unknown
}

public struct SpeechLanguageCapabilities: Sendable, Equatable {
    public let modelName: String
    /// A complete known set of selectable language codes. nil means unverified, not unsupported.
    public let supportedLanguages: [String]?
    /// nil means the exact model/runtime contract has not been verified.
    public let supportsAutomatic: Bool?
    public let manualControl: SpeechLanguageManualControl
    public let summary: String
}

public struct ResolvedSpeechLanguage: Sendable, Equatable {
    /// The parameter to send to the adapter. nil also covers joint recognition, not just Auto.
    public let language: String?
    /// Canonical user intent, retained even when joint recognition does not take a parameter.
    public let requestedLanguage: String?
    public let capabilities: SpeechLanguageCapabilities
    public var isAutomatic: Bool { requestedLanguage == nil && capabilities.manualControl != .locale }
}

public enum SpeechLanguageError: Error, LocalizedError, Sendable, Equatable {
    case invalidCode(String)
    case ambiguousChineseLocale
    case automaticUnavailable(model: String)
    case unsupportedLanguage(language: String, model: String)

    public var errorDescription: String? {
        switch self {
        case .invalidCode(let code):
            return "\"\(code)\" is not a valid speech language code. Choose a language on Models."
        case .ambiguousChineseLocale:
            return "Choose Mandarin Chinese or Cantonese explicitly on Models instead of zh-HK."
        case .automaticUnavailable(let model):
            return "\(model) needs an explicit speech language. Choose a supported language on Models or select a model with Auto Detect."
        case .unsupportedLanguage(let language, let model):
            return "\(model) does not support \(SpeechLanguagePolicy.languageName(language)). Choose a supported language on Models or another speech model."
        }
    }
}

/// Shared by model selection, recording preflight, retries and engine adapters.
/// Capability evidence was checked on 2026-10-05. Only exact model IDs inherit
/// model-specific claims; a future checkpoint or a custom endpoint stays unknown.
public enum SpeechLanguagePolicy {
    public static func capabilities(for config: ASRConfig) -> SpeechLanguageCapabilities {
        // Native cloud adapters use this resolved selection, including the existing
        // catalog fallback. OpenRouter and custom endpoints keep exact stored IDs.
        let cloudModel = config.speechModelID
        switch config.kind {
        case .qwen3:
            guard ["aufklarer/Qwen3-ASR-1.7B-MLX-5bit", "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"].contains(config.qwen3Model) else {
                return unknown(config.qwen3Model)
            }
            return capability("Qwen3-ASR", qwenLanguages, true, .forced,
                              "30 languages, including Mandarin and Cantonese. Auto Detect available.")
        case .cohere:
            guard config.cohereModel == "aufklarer/Cohere-Transcribe-2B-MLX-5bit" else {
                return capability(config.cohereModel, nil, false, .forced,
                                  "Language coverage unverified. Select an explicit language.")
            }
            // speech-swift d655076: nil/unknown language becomes English. The
            // experimental unknown-language prompt is not an accepted Auto contract.
            return capability("Cohere Transcribe", cohereLanguages, false, .forced,
                              "14 languages, including Mandarin. Select a language; Auto Detect is unavailable.")
        case .fireRed:
            // https://github.com/FireRedTeam/FireRedASR2S (AED recognizer, not FireRedLID)
            return capability("FireRedASR2", ["en", "zh"], true, .notApplied,
                              "Automatically recognizes Mandarin and English; selection does not limit recognition.")
        case .senseVoice:
            // https://huggingface.co/FunAudioLLM/SenseVoiceSmall
            return capability("SenseVoice", ["en", "ja", "ko", "yue", "zh"], true, .forced,
                              "Mandarin, Cantonese, English, Japanese and Korean. Auto Detect available.")
        case .parakeet:
            return capability("Parakeet TDT v3", parakeetLanguages, true, .notApplied,
                              "Automatically recognizes 25 European languages. Selection has no effect; no Chinese support.")
        case .whisperKit:
            guard config.whisperModel == "large-v3-v20240930_turbo" else { return unknown(config.whisperModel) }
            return capability("Whisper Large v3 Turbo", whisperV3Languages, true, .forced,
                              "Auto Detect or a selected language.")
        case .apple:
            // The OS owns supported locales/assets. Keep ASRConfig's existing
            // locale selection rather than pretending the stored Auto means LID.
            return capability("Apple Speech", nil, false, .locale,
                              "Uses the selected Apple Speech locale. Auto Detect is unavailable.")
        case .openAICompatible:
            return unknown(config.model)
        case .openAI:
            guard ["gpt-transcribe", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"].contains(cloudModel) else {
                return unknown(cloudModel)
            }
            // https://developers.openai.com/api/docs/guides/speech-to-text
            // Its published accuracy list is not an exhaustive rejection list.
            return capability(cloudModel, nil, true, .hint,
                              "Auto Detect available. A selected language is a hint.")
        case .groq:
            guard ["whisper-large-v3", "whisper-large-v3-turbo"].contains(cloudModel) else { return unknown(cloudModel) }
            // https://console.groq.com/docs/speech-to-text
            return capability(cloudModel, whisperV3Languages, true, .forced,
                              "Auto Detect or a selected language.")
        case .elevenLabs:
            guard ["scribe_v2", "scribe_v2_medical"].contains(cloudModel) else { return unknown(cloudModel) }
            // https://elevenlabs.io/docs/api-reference/speech-to-text/convert
            return capability(cloudModel, nil, true, .hint,
                              "Auto Detect supports mixed languages. A selected language is a hint.")
        case .deepgram:
            switch cloudModel {
            case "nova-3":
                return capability("Deepgram Nova-3", novaLanguages, true, .forced,
                                  "Auto Detect selects one dominant language.")
            case "nova-3-multilingual":
                return capability("Deepgram Nova-3 Multilingual", novaMultilingualLanguages, true, .notApplied,
                                  "Automatically recognizes 10 languages, excluding Chinese; selection has no effect.")
            case "whisper-large":
                return capability("Deepgram Whisper Large v2", whisperV2Languages, true, .forced,
                                  "Auto Detect has its own language coverage; select a language if needed.")
            default: return unknown(cloudModel)
            }
        case .soniox:
            guard cloudModel == "stt-async-v5" else { return unknown(cloudModel) }
            // https://soniox.com/docs/stt/concepts/language-hints
            return capability("Soniox v5", nil, true, .hint,
                              "Recognizes mixed languages automatically. A selected language is a hint.")
        case .openRouter:
            return openRouterCapabilities(model: config.model)
        }
    }

    public static func resolve(_ config: ASRConfig) throws -> ResolvedSpeechLanguage {
        let capabilities = capabilities(for: config)
        let requested = try canonicalLanguage(config.language)
        if config.kind == .apple {
            return ResolvedSpeechLanguage(language: config.effectiveAppleLocale,
                                          requestedLanguage: requested, capabilities: capabilities)
        }
        guard var language = requested else {
            guard capabilities.supportsAutomatic != false else {
                throw SpeechLanguageError.automaticUnavailable(model: capabilities.modelName)
            }
            return ResolvedSpeechLanguage(language: nil, requestedLanguage: nil, capabilities: capabilities)
        }
        // zh-HK is a locale, not an unambiguous request for Mandarin. Deepgram
        // explicitly defines it as Cantonese; elsewhere require the actual language.
        if language == "zh-hk", capabilities.manualControl != .unknown {
            if config.kind == .deepgram, config.speechModelID == "nova-3" {
                language = "yue"
            } else {
                throw SpeechLanguageError.ambiguousChineseLocale
            }
        }
        // Even an unknown Cohere checkpoint goes through the same SDK tokenizer,
        // whose unrecognized language codes silently become English. Enforce its
        // known input vocabulary without claiming the checkpoint supports it all.
        let supportedLanguages = config.kind == .cohere ? cohereLanguages : capabilities.supportedLanguages
        if let supported = supportedLanguages {
            let aliases = ["fil": "tl", "tl": "fil", "nb": "no", "no": "nb", "jv": "jw", "jw": "jv"]
            if !supported.contains(language), let alias = aliases[language], supported.contains(alias) {
                language = alias
            }
            guard supported.contains(language) else {
                throw SpeechLanguageError.unsupportedLanguage(language: requested ?? language, model: capabilities.modelName)
            }
        }
        if config.kind == .deepgram, config.speechModelID == "nova-3", language != "yue" {
            // Validate the base language above, but preserve documented Nova-3
            // locales on the wire. EngineFactory resolves again before adapters.
            let locale = config.language.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-").lowercased()
            language = novaRegionalLanguages[locale] ?? language
        }
        return ResolvedSpeechLanguage(language: capabilities.manualControl == .notApplied ? nil : language,
                                      requestedLanguage: requested, capabilities: capabilities)
    }

    /// Normalize language intent without inferring unsupported languages or defaulting to English.
    public static func canonicalLanguage(_ value: String) throws -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
        if code.isEmpty || code == "auto" { return nil }
        guard code.range(of: "^[a-z]{2,3}(-[a-z0-9]{2,8})*$", options: .regularExpression) != nil else {
            throw SpeechLanguageError.invalidCode(value)
        }
        let parts = code.split(separator: "-")
        if parts.first == "zh" {
            if parts.contains("yue") { return "yue" }
            if parts.contains("hk") { return "zh-hk" }
            return "zh"
        }
        if parts.first == "cmn" { return "zh" }
        return String(parts[0])
    }

    public static func languageName(_ code: String) -> String {
        switch code {
        case "zh": return "Mandarin Chinese"
        case "yue": return "Cantonese"
        default: return Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized ?? code
        }
    }

    private static func capability(_ name: String, _ languages: [String]?, _ automatic: Bool?,
                                   _ manual: SpeechLanguageManualControl, _ summary: String) -> SpeechLanguageCapabilities {
        SpeechLanguageCapabilities(modelName: name, supportedLanguages: languages,
                                   supportsAutomatic: automatic, manualControl: manual, summary: summary)
    }

    private static func unknown(_ name: String) -> SpeechLanguageCapabilities {
        capability(name.isEmpty ? "This speech model" : name, nil, nil, .unknown,
                   "Language support is unverified for this model and endpoint.")
    }

    private static func openRouterCapabilities(model: String) -> SpeechLanguageCapabilities {
        // https://openrouter.ai/docs/guides/overview/multimodal/stt
        // The shared wire promises omitted-language Auto. Model-specific language
        // mappings remain unverified, so do not label those hints as forced.
        switch model {
        case "nvidia/parakeet-tdt-0.6b-v3":
            return capability("Parakeet TDT v3", parakeetLanguages, true, .notApplied,
                              "Automatically recognizes 25 European languages. Selection has no effect; no Chinese support.")
        case "mistralai/voxtral-small-24b-2507-stt", "mistralai/voxtral-mini-3b-2507":
            return capability(model, voxtral2507Languages, true, .hint,
                              "8 languages. Mandarin and Cantonese are unsupported.")
        case "qwen/qwen3-asr-1.7b", "qwen/qwen3-asr-0.6b":
            return capability(model, qwenLanguages, true, .hint,
                              "30 languages, including Chinese. Language hints through OpenRouter are unverified.")
        case "openai/whisper-large-v3", "openai/whisper-large-v3-turbo":
            return capability(model, whisperV3Languages, true, .hint,
                              "Multilingual Whisper. Language hints through OpenRouter are unverified.")
        case "openai/whisper-1":
            return capability(model, whisperV2Languages, true, .hint,
                              "Multilingual Whisper. Language hints through OpenRouter are unverified.")
        case "fish-audio/transcribe-1", "fish-audio/transcribe-1-pro":
            // https://docs.fish.audio/features/speech-to-text
            return capability(model, nil, true, .notApplied,
                              "Automatically recognizes speech; language selection has no effect.")
        case "deepgram/nova-3":
            return capability(model, novaLanguages, true, .hint,
                              "Supports Mandarin. Auto Detect and language hints through OpenRouter are unverified.")
        case "google/gemini-3.5-transcribe", "assemblyai/universal-3-5-pro",
             "microsoft/mai-transcribe-2", "microsoft/mai-transcribe-1.5",
             "openai/gpt-transcribe", "openai/gpt-4o-mini-transcribe", "openai/gpt-4o-transcribe",
             "qwen/qwen3-asr-flash-2026-02-10", "google/chirp-3":
            // Exact entries audited in Research/Models/Language Compatibility.
            // Partial published lists must not become an exhaustive allowlist.
            return capability(model, nil, true, .hint,
                              "Multilingual transcription. Exact language coverage and hints are unverified.")
        case "nvidia/nemotron-3.5-asr-streaming-multilingual-0.6b":
            // https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
            // Upstream needs target_lang=auto; the gateway mapping is unverified.
            return capability(model, nil, nil, .unknown,
                              "Supports Mandarin. Auto Detect through OpenRouter is unverified.")
        default:
            // Includes unknown aliases and revisions, muse-voice-transcribe-1.0,
            // grok-stt-1.0 and voxtral-mini-transcribe: never infer from a prefix.
            return unknown(model)
        }
    }

    // Complete language lists, not benchmark-only accuracy lists.
    // https://huggingface.co/Qwen/Qwen3-ASR-1.7B
    private static let qwenLanguages = [
        "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fil", "fr", "hi", "hu", "id", "it",
        "ja", "ko", "mk", "ms", "nl", "pl", "pt", "ro", "ru", "sv", "th", "tr", "vi", "yue", "zh"
    ]
    // https://huggingface.co/CohereLabs/cohere-transcribe-03-2026
    private static let cohereLanguages = ["ar", "de", "el", "en", "es", "fr", "it", "ja", "ko", "nl", "pl", "pt", "vi", "zh"]
    // https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
    private static let parakeetLanguages = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv",
        "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"
    ]
    // https://huggingface.co/mistralai/Voxtral-Small-24B-2507
    // https://huggingface.co/mistralai/Voxtral-Mini-3B-2507
    private static let voxtral2507Languages = ["de", "en", "es", "fr", "hi", "it", "nl", "pt"]
    // https://developers.deepgram.com/docs/models-languages-overview
    // Nova-3 table checked 2026-10-05: 60 distinct base languages, with
    // regional variants checked by base and the separate multi mode excluded.
    // Cantonese's wire code is zh-HK; the adapter maps the canonical yue intent.
    private static let novaLanguages = [
        "af", "ar", "as", "be", "bg", "bn", "bs", "ca", "cs", "da", "de", "el", "en", "es", "et",
        "fa", "fi", "fr", "gu", "he", "hi", "hr", "hu", "hy", "id", "it", "ja", "ka", "kk", "kn",
        "ko", "lt", "lv", "mk", "mn", "mr", "ms", "ne", "nl", "no", "pa", "pl", "ps", "pt", "ro",
        "ru", "sk", "sl", "sr", "sv", "ta", "te", "th", "tl", "tr", "uk", "ur", "vi", "yue", "zh"
    ]
    // Preserve only the locales explicitly listed for nova-3, not Nova-2 or
    // Nova-3 medical/pharma. Cantonese remains yue until adapter wire mapping.
    private static let novaRegionalLanguages = Dictionary(uniqueKeysWithValues: [
        "af-ZA", "ar-AE", "ar-SA", "ar-QA", "ar-KW", "ar-SY", "ar-LB", "ar-PS", "ar-JO",
        "ar-EG", "ar-SD", "ar-TD", "ar-MA", "ar-DZ", "ar-TN", "ar-IQ", "ar-IR", "as-IN",
        "zh-CN", "zh-Hans", "zh-TW", "zh-Hant", "cs-CZ", "da-DK", "en-US", "en-AU",
        "en-GB", "en-IN", "en-NZ", "nl-BE", "fr-CA", "ka-GE", "de-CH", "gu-IN", "kk-KZ",
        "ko-KR", "ps-AF", "pt-BR", "pt-PT", "pa-IN", "es-419", "sv-SE", "th-TH", "tr-TR"
    ].map { ($0.lowercased(), $0) })
    private static let novaMultilingualLanguages = ["de", "en", "es", "fr", "hi", "it", "ja", "nl", "pt", "ru"]
    // https://github.com/openai/whisper/blob/main/whisper/tokenizer.py
    // Large v2/whisper-1 have the first 99 language tokens; v3 adds Cantonese.
    private static let whisperV2Languages = [
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo", "br", "bs", "ca", "cs", "cy",
        "da", "de", "el", "en", "es", "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja", "jw", "ka", "kk", "km", "kn",
        "ko", "la", "lb", "ln", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt", "ro", "ru", "sa", "sd", "si",
        "sk", "sl", "sn", "so", "sq", "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "zh"
    ]
    private static let whisperV3Languages = (whisperV2Languages + ["yue"]).sorted()
}
