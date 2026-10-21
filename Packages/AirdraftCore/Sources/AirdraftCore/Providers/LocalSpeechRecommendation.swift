import Foundation

/// The local speech model first-run setup and Models recommend for this Mac.
/// AD-074: Chinese system languages get Qwen3-ASR 1.7B, which handles mixed
/// Chinese and English best (`eval/mixed-asr/`). Macs with 8 GB of memory or
/// less get SenseVoice, which is smaller and faster but weaker with English
/// terms. Qwen3-ASR 0.6B is never the lighter default: it can loop and exhaust
/// memory. English, Japanese and Korean keep SenseVoice; other languages keep
/// Whisper Large v3 Turbo.
public struct LocalSpeechRecommendation: Equatable, Sendable {
    public enum Model: String, Equatable, Sendable, CaseIterable {
        case qwen3Large, senseVoice, whisperTurbo
    }

    public enum Reason: Equatable, Sendable {
        /// Chinese system language with enough memory for Qwen3-ASR 1.7B.
        case mixedChineseEnglish
        /// Chinese system language on a Mac with 8 GB of memory or less.
        case limitedMemory
        /// The established choice for this system language.
        case systemLanguage
    }

    public let model: Model
    public let reason: Reason
    /// Other choices worth showing beside the recommendation, best first.
    public let alternatives: [Model]

    /// 8 GB Macs report exactly 8 GiB of physical memory.
    public static let limitedMemoryBytes: UInt64 = 8 << 30

    public static func recommend(languageCode: String?, physicalMemory: UInt64) -> Self {
        switch normalized(languageCode) {
        case "zh":
            return physicalMemory <= limitedMemoryBytes
                ? .init(model: .senseVoice, reason: .limitedMemory, alternatives: [.qwen3Large])
                : .init(model: .qwen3Large, reason: .mixedChineseEnglish, alternatives: [.senseVoice])
        case "en", "ja", "ko":
            return .init(model: .senseVoice, reason: .systemLanguage, alternatives: [])
        default:
            return .init(model: .whisperTurbo, reason: .systemLanguage, alternatives: [])
        }
    }

    /// This Mac: its primary system language and physical memory.
    public static var current: Self {
        recommend(languageCode: systemLanguageCode, physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    /// The first preferred language in System Settings, which sets the interface
    /// language, falling back to the formatting locale.
    public static var systemLanguageCode: String? {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    /// `zh-Hant-TW`, `zh_TW` and `zh-Hans` are all Chinese.
    static func normalized(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale(identifier: code).language.languageCode?.identifier.lowercased()
    }
}
