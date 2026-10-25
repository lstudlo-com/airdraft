import Foundation

extension LocalSpeechRecommendation.Model {
    /// The Models catalogue entry for this recommendation.
    public var catalogueID: String {
        switch self {
        case .qwen3Large: "qwen3:1.7b"
        case .senseVoice: "sherpa:senseVoiceMultilingual"
        case .whisperTurbo: "whisper:turbo"
        case .parakeetEnglish: "coreml:parakeet-v2"
        case .parakeetEuropean: "coreml:parakeet-v3"
        case .gigaAMRussian: "gguf:gigaam-v3-e2e-rnnt"
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
        let rule = LocalSpeechRecommendation.rule(for: languageCode)
        let choice = rule.choice(physicalMemory: physicalMemory)
        let recommendation = LocalSpeechRecommendation.recommend(languageCode: languageCode, physicalMemory: physicalMemory)
        let limitedMemory = physicalMemory <= rule.memoryThreshold
        // The recommendation's own alternatives come first, with the labels the
        // rule gives them; its curated candidates fill the remaining places,
        // skipping duplicates and, at or below the threshold, large models.
        let suggested = choice.alternatives.map { Candidate(id: $0.model.catalogueID, role: $0.role) }
        var picks = [Pick(id: recommendation.model.catalogueID, role: .recommended)]
        for candidate in suggested + rule.shortlist
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

    /// A curated shortlist entry: a Verified catalogue ID and its label.
    /// `ModelCatalogue.verificationEvidence` must list it; the
    /// models-performance fixture asserts it for every rule.
    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let role: Role
        /// Skipped on Macs at or below the rule's memory threshold.
        public let large: Bool
        public init(id: String, role: Role, large: Bool = false) { self.id = id; self.role = role; self.large = large }
    }

    /// Parakeet TDT v3's 25 European languages (`SpeechLanguagePolicy`).
    public static let europeanLanguages: Set<String> = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk",
    ]
}

/// A readable form of a model's language list (AD-071): up to two full language
/// names, the user's language first, then English and other languages by
/// number of speakers, then a count of the rest. The full list
/// belongs in a tooltip and the accessibility label.
public struct SpeechLanguageList: Equatable, Sendable {
    /// Full localized names, the user's language and English first.
    public let names: [String]
    /// Names shown in the compact form.
    public let shown: [String]
    public var remaining: Int { names.count - shown.count }

    public init(codes: [String], preferredLanguage: String?, nameFor: (String) -> String = SpeechLanguagePolicy.languageName) {
        let preferred = LocalSpeechRecommendation.normalized(preferredLanguage)
        let priority = [preferred].compactMap { $0 } + SpeechLanguagePolicy.widelySpokenLanguages
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
