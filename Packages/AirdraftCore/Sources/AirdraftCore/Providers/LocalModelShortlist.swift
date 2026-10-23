import Foundation

extension LocalSpeechRecommendation.Model {
    /// The Models catalogue entry for this recommendation.
    public var catalogueID: String {
        switch self {
        case .qwen3Large: "qwen3:1.7b"
        case .senseVoice: "sherpa:senseVoiceMultilingual"
        case .whisperTurbo: "whisper:turbo"
        case .parakeetEnglish: "coreml:parakeet-v2"
        }
    }
}

/// AD-071: the compact local speech list Models opens with. It shows the
/// language recommendation plus at most `maximumAlternatives` curated, verified
/// alternatives that differ by size, speed or language reach, so ordinary users
/// are not asked to compare the whole catalogue. Models the user relies on
/// (default, profile binding, installed or downloading) are listed separately by
/// `inUse(catalogueOrder:inUse:)`, so they never disappear.
public struct LocalModelShortlist: Equatable, Sendable {
    /// Why a model is in the shortlist. Each pick shows one visible label.
    public enum Role: Equatable, Sendable {
        /// The language and memory recommendation itself.
        case recommended
        /// Smaller download and faster than the recommendation.
        case faster
        /// A smaller download than the recommendation.
        case smaller
        /// The full-size version of the recommendation, with a larger download.
        case fullSize
        /// Built for the user's language alone.
        case singleLanguage
        /// Best for Chinese speech mixed with English terms.
        case mixedChineseEnglish
        /// Best Mandarin accuracy, including dialects.
        case mandarin
        /// Recognizes many more languages than the recommendation.
        case multilingual
        /// More accurate than the memory-limited recommendation, using more memory.
        case moreAccurate
        /// Needs much less memory than the recommendation.
        case lessMemory
    }

    public struct Pick: Equatable, Sendable {
        public let id: String
        public let role: Role
        public init(id: String, role: Role) { self.id = id; self.role = role }
    }

    public static let maximumAlternatives = 2

    public let recommendation: LocalSpeechRecommendation
    /// The recommendation first, then its alternatives, best first.
    public let picks: [Pick]

    public var ids: [String] { picks.map(\.id) }

    public static func make(languageCode: String?, physicalMemory: UInt64) -> Self {
        let recommendation = LocalSpeechRecommendation.recommend(languageCode: languageCode, physicalMemory: physicalMemory)
        let limitedMemory = physicalMemory <= LocalSpeechRecommendation.limitedMemoryBytes
        // The recommendation's own alternatives come first; curated candidates
        // fill the remaining places, skipping duplicates of the recommendation.
        let suggested = recommendation.alternatives.map { model in
            Candidate(id: model.catalogueID, role: role(of: model, beside: recommendation), large: false)
        }
        var picks = [Pick(id: recommendation.model.catalogueID, role: .recommended)]
        for candidate in suggested + candidates(for: LocalSpeechRecommendation.normalized(languageCode))
        where picks.count <= maximumAlternatives && !picks.contains(where: { $0.id == candidate.id })
            && !(limitedMemory && candidate.large) {
            picks.append(Pick(id: candidate.id, role: candidate.role))
        }
        return Self(recommendation: recommendation, picks: picks)
    }

    /// Models in use that the shortlist does not already show, in catalogue order.
    public func inUse(catalogueOrder: [String], inUse: Set<String>) -> [String] {
        let shown = Set(ids)
        return catalogueOrder.filter { inUse.contains($0) && !shown.contains($0) }
    }

    private struct Candidate {
        let id: String
        let role: Role
        /// Skipped on Macs with 8 GB of memory or less.
        let large: Bool
    }

    /// The label of a recommendation's own alternative, which depends on what
    /// it is compared with.
    private static func role(of model: LocalSpeechRecommendation.Model,
                             beside recommendation: LocalSpeechRecommendation) -> Role {
        switch model {
        case .qwen3Large:
            switch recommendation.model {
            case .senseVoice: .mixedChineseEnglish
            case .whisperTurbo: .moreAccurate
            case .parakeetEnglish, .qwen3Large: .multilingual
            }
        case .senseVoice: .faster
        case .whisperTurbo: recommendation.model == .qwen3Large ? .lessMemory : .multilingual
        case .parakeetEnglish: .singleLanguage
        }
    }

    /// Verified models only (`ModelCatalogue.verificationEvidence`); the
    /// models-performance fixture asserts it for every language below.
    private static func candidates(for language: String?) -> [Candidate] {
        let largeV3 = "whisper:large-v3", senseVoice = LocalSpeechRecommendation.Model.senseVoice.catalogueID
        switch language {
        case "zh":
            return [Candidate(id: senseVoice, role: .faster, large: false),
                    Candidate(id: "sherpa:fireRed", role: .mandarin, large: false)]
        case "en", "ja", "ko":
            // AD-083: the recommendation and its alternative cover these. The
            // shipped SenseVoice failed on all three languages, and Parakeet
            // Japanese dropped a whole sentence from 3 of 60 FLEURS clips.
            return []
        case let code? where europeanLanguages.contains(code):
            return [Candidate(id: "coreml:parakeet-v3", role: .smaller, large: false),
                    Candidate(id: largeV3, role: .fullSize, large: true)]
        default:
            return [Candidate(id: largeV3, role: .fullSize, large: true)]
        }
    }

    /// Parakeet TDT v3's 25 European languages (`SpeechLanguagePolicy`).
    static let europeanLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk",
    ]
}

/// A readable form of a model's language list (AD-071): up to two full language
/// names, the user's language first, then English and other widely spoken
/// languages, then a count of the rest. The full list
/// belongs in a tooltip and the accessibility label.
public struct SpeechLanguageList: Equatable, Sendable {
    /// Full localized names, the user's language and English first.
    public let names: [String]
    /// Names shown in the compact form.
    public let shown: [String]
    public var remaining: Int { names.count - shown.count }

    public init(codes: [String], preferredLanguage: String?, nameFor: (String) -> String = SpeechLanguagePolicy.languageName) {
        let preferred = LocalSpeechRecommendation.normalized(preferredLanguage)
        let priority = [preferred, "en", "zh", "es", "fr", "de", "ja", "ko", "pt"].compactMap { $0 }
        var ordered: [String] = []
        for code in priority where codes.contains(code) && !ordered.contains(code) { ordered.append(code) }
        for code in codes where !ordered.contains(code) { ordered.append(code) }
        names = ordered.map(nameFor)
        shown = Array(names.prefix(2))
    }

    /// The model's supported languages, or nil when the operating system or
    /// the endpoint owns them.
    public static func supported(by config: ASRConfig, preferredLanguage: String?) -> Self? {
        guard let codes = SpeechLanguagePolicy.capabilities(for: config).supportedLanguages, !codes.isEmpty else { return nil }
        return Self(codes: codes, preferredLanguage: preferredLanguage)
    }
}
