import Foundation

/// The local speech model first-run setup and Models recommend for this Mac.
/// The choice is data: `rules` holds one measured rule per primary system
/// language, and `unmeasuredRule(for:)` covers every other language.
/// AD-074: Chinese system languages get Qwen3-ASR 1.7B, which handles mixed
/// Chinese and English best (`eval/mixed-asr/`). Macs with 8 GB of memory or
/// less get SenseVoice, which is smaller and faster but weaker with English
/// terms. Qwen3-ASR 0.6B is never the lighter default: it can loop and exhaust
/// memory.
/// AD-083 (`eval/eja-asr/`, FLEURS read speech): English gets Parakeet TDT v2,
/// as accurate as Qwen3-ASR 1.7B (WER 3.5% against 3.0%, not significant) at a
/// tenth of its latency and memory. Japanese and Korean get Qwen3-ASR 1.7B
/// (CER 6.2% and 11.6% under Auto), or Whisper Large v3 Turbo on Macs with 8 GB
/// or less. The shipped SenseVoice archive, a Cantonese fine-tune, lost Japanese
/// kana and most Korean (CER 76% and 77%) and had 32% English WER.
/// AD-098 (`eval/intl-asr/`, FLEURS read speech): Spanish, French, Portuguese,
/// Russian, Arabic, Hindi and Indonesian get Qwen3-ASR 1.7B. Macs with 8 GB or
/// less get Parakeet TDT v3 (es, fr, pt), GigaAM v3 (ru) or Whisper Large v3
/// Turbo (ar, id); Hindi keeps Qwen3-ASR, since Whisper doubled its errors.
public struct LocalSpeechRecommendation: Equatable, Sendable {
    public enum Model: String, Equatable, Sendable, CaseIterable {
        case qwen3Large, senseVoice, whisperTurbo, parakeetEnglish
        /// Parakeet TDT v3 (Core ML), 25 European languages (AD-098).
        case parakeetEuropean
        /// GigaAM v3 E2E RNN-T (GGUF), Russian only (AD-098).
        case gigaAMRussian
    }

    public enum Reason: Equatable, Sendable {
        /// Chinese system language with enough memory for Qwen3-ASR 1.7B.
        case mixedChineseEnglish
        /// The rule's choice for a Mac at or below its memory threshold.
        case limitedMemory
        /// The best measured choice for this system language, or the
        /// documented default for a language Airdraft has not measured.
        case systemLanguage
    }

    public let model: Model
    public let reason: Reason
    /// Other choices worth showing beside the recommendation, best first.
    public let alternatives: [Model]

    public init(model: Model, reason: Reason, alternatives: [Model]) {
        self.model = model
        self.reason = reason
        self.alternatives = alternatives
    }

    /// 8 GB Macs report exactly 8 GiB of physical memory. Every rule's default
    /// memory threshold: at or below it, the rule's limited-memory choice applies.
    public static let limitedMemoryBytes: UInt64 = 8 << 30

    /// An alternative and the one label Models shows for it beside this choice.
    public struct Alternative: Equatable, Sendable {
        public let model: Model
        public let role: LocalModelShortlist.Role
        public init(_ model: Model, _ role: LocalModelShortlist.Role) { self.model = model; self.role = role }
    }

    /// What one memory class of a rule recommends.
    public struct Choice: Equatable, Sendable {
        public let model: Model
        public let reason: Reason
        public let alternatives: [Alternative]
        /// The recommendation had the lowest measured error of every local model
        /// run for the language, so first-run setup may call it the most accurate
        /// in Airdraft's tests.
        public let isMostAccurate: Bool
        public init(_ model: Model, _ reason: Reason, _ alternatives: [Alternative] = [], mostAccurate: Bool = false) {
            self.model = model; self.reason = reason; self.alternatives = alternatives; self.isMostAccurate = mostAccurate
        }
    }

    /// One language's recommendation: the choice above the memory threshold,
    /// the choice at or below it (nil when memory does not change it), and the
    /// curated Verified models the Models shortlist may add after the choice's
    /// own alternatives.
    public struct Rule: Equatable, Sendable {
        public let choice: Choice
        public let limitedMemoryChoice: Choice?
        public let memoryThreshold: UInt64
        public let shortlist: [LocalModelShortlist.Candidate]
        /// The measurement behind the rule, or nil for the unmeasured default.
        public let evidence: String?

        public init(_ choice: Choice, limitedMemory: Choice? = nil, memoryThreshold: UInt64 = LocalSpeechRecommendation.limitedMemoryBytes,
                    shortlist: [LocalModelShortlist.Candidate] = [], evidence: String?) {
            self.choice = choice
            self.limitedMemoryChoice = limitedMemory
            self.memoryThreshold = memoryThreshold
            self.shortlist = shortlist
            self.evidence = evidence
        }

        public func choice(physicalMemory: UInt64) -> Choice {
            physicalMemory <= memoryThreshold ? limitedMemoryChoice ?? choice : choice
        }
    }

    /// Measured rules by primary system language code (`normalized(_:)`).
    public static let rules: [String: Rule] = {
        let mixed = "eval/mixed-asr (AD-074) and the eval/eja-asr follow-up"
        let fleurs = "eval/eja-asr (AD-083)"
        let chinese = Rule(
            Choice(.qwen3Large, .mixedChineseEnglish, [Alternative(.senseVoice, .faster)]),
            limitedMemory: Choice(.senseVoice, .limitedMemory, [Alternative(.qwen3Large, .mixedChineseEnglish)]),
            shortlist: [.init(id: Model.senseVoice.catalogueID, role: .faster),
                        .init(id: "sherpa:fireRed", role: .mandarin)],
            evidence: mixed)
        // The shipped SenseVoice failed on all three languages, and Parakeet
        // Japanese dropped a whole sentence from 3 of 60 FLEURS clips, so the
        // recommendation and its alternative are the whole shortlist.
        let english = Rule(Choice(.parakeetEnglish, .systemLanguage, [Alternative(.qwen3Large, .multilingual)]), evidence: fleurs)
        let japaneseKorean = Rule(
            Choice(.qwen3Large, .systemLanguage, [Alternative(.whisperTurbo, .lessMemory)], mostAccurate: true),
            limitedMemory: Choice(.whisperTurbo, .limitedMemory, [Alternative(.qwen3Large, .moreAccurate)]),
            evidence: fleurs)
        // AD-098 (eval/intl-asr, FLEURS, 40 utterances, WER under Auto): Qwen3-ASR
        // 1.7B has the lowest or a tied-lowest error of the models that detect the
        // language in all seven languages. Canary 1B v2, Cohere Transcribe Arabic
        // (ar, 6.0% against 10.8%) and Cohere need an explicit speech language,
        // which a new install does not have, so they are not first-run choices.
        // Voxtral Mini 4B was within half a point (es 1.5%, pt 3.9%) at about
        // 4.9 GB of memory and four times the latency. `mostAccurate` is false
        // where any measured model had a lower error: es (Voxtral), pt (Canary,
        // Voxtral), ar (Cohere Transcribe Arabic).
        let intl = "eval/intl-asr (AD-098)"
        // Spanish, French and Portuguese: Parakeet TDT v3 (Core ML) is within about
        // a point of Qwen3-ASR at a tenth of its latency and about 60 MB of process
        // memory, and ahead of Whisper Large v3 Turbo, so it is the 8 GB choice.
        func romance(mostAccurate: Bool) -> Rule {
            Rule(Choice(.qwen3Large, .systemLanguage, [Alternative(.parakeetEuropean, .faster)], mostAccurate: mostAccurate),
                 limitedMemory: Choice(.parakeetEuropean, .limitedMemory, [Alternative(.qwen3Large, .moreAccurate)]),
                 evidence: intl)
        }
        // Russian: GigaAM v3 E2E RNN-T is tied with Qwen3-ASR (6.4% against 5.8%)
        // at 430 MB and 60 ms; Parakeet TDT v3 adds English and 23 more languages.
        let russian = Rule(
            Choice(.qwen3Large, .systemLanguage, [Alternative(.gigaAMRussian, .lessMemory)], mostAccurate: true),
            limitedMemory: Choice(.gigaAMRussian, .limitedMemory, [Alternative(.qwen3Large, .moreAccurate)]),
            shortlist: [.init(id: Model.parakeetEuropean.catalogueID, role: .multilingual)],
            evidence: intl)
        // Arabic and Indonesian: the Japanese and Korean pattern, with Whisper
        // Large v3 Turbo as the lighter choice. For Arabic, Models also offers the
        // full-size Whisper Large v3, 2.5 points better than Turbo but about 3.5
        // times slower.
        func turboFallback(mostAccurate: Bool, shortlist: [LocalModelShortlist.Candidate] = []) -> Rule {
            Rule(Choice(.qwen3Large, .systemLanguage, [Alternative(.whisperTurbo, .lessMemory)], mostAccurate: mostAccurate),
                 limitedMemory: Choice(.whisperTurbo, .limitedMemory, [Alternative(.qwen3Large, .moreAccurate)]),
                 shortlist: shortlist, evidence: intl)
        }
        let arabic = turboFallback(mostAccurate: false, shortlist: [.init(id: "whisper:large-v3", role: .fullSize, large: true)])
        // Hindi: every Whisper model has about twice Qwen3-ASR's errors (WER 32-34%
        // against 18-19%), so Qwen3-ASR is recommended on every Mac.
        let hindi = Rule(Choice(.qwen3Large, .systemLanguage, [Alternative(.whisperTurbo, .lessMemory)], mostAccurate: true),
                         evidence: intl)
        return ["zh": chinese, "en": english, "ja": japaneseKorean, "ko": japaneseKorean,
                "es": romance(mostAccurate: false), "fr": romance(mostAccurate: true), "pt": romance(mostAccurate: false),
                "ru": russian, "ar": arabic, "id": turboFallback(mostAccurate: true), "hi": hindi]
    }()

    /// The documented default for a language without a measured rule: Whisper
    /// Large v3 Turbo, which recognizes about 100 languages in little memory,
    /// with no alternative in first-run setup. Models adds Parakeet TDT v3 for
    /// its 25 European languages and the full-size Whisper Large v3 (skipped at
    /// or below the memory threshold).
    public static func unmeasuredRule(for language: String?) -> Rule {
        let largeV3 = LocalModelShortlist.Candidate(id: "whisper:large-v3", role: .fullSize, large: true)
        let european = language.map(LocalModelShortlist.europeanLanguages.contains) ?? false
        return Rule(Choice(.whisperTurbo, .systemLanguage),
                    shortlist: european ? [.init(id: "coreml:parakeet-v3", role: .smaller), largeV3] : [largeV3],
                    evidence: nil)
    }

    /// The measured rule for a system language, or the unmeasured default.
    public static func rule(for languageCode: String?) -> Rule {
        let language = normalized(languageCode)
        return language.flatMap { rules[$0] } ?? unmeasuredRule(for: language)
    }

    public static func recommend(languageCode: String?, physicalMemory: UInt64) -> Self {
        let choice = rule(for: languageCode).choice(physicalMemory: physicalMemory)
        return .init(model: choice.model, reason: choice.reason, alternatives: choice.alternatives.map(\.model))
    }

    /// This Mac: its primary system language and physical memory.
    public static var current: Self {
        recommend(languageCode: systemLanguageCode, physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    /// The first preferred language in System Settings, which sets the interface
    /// language, falling back to the formatting locale.
    public static var systemLanguageCode: String? {
        SystemLanguages.preferred.first ?? Locale.current.identifier
    }

    /// `zh-Hant-TW`, `zh_TW` and `zh-Hans` are all Chinese.
    public static func normalized(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale(identifier: code).language.languageCode?.identifier.lowercased()
    }
}
