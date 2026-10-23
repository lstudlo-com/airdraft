import Foundation

/// The local speech model first-run setup and Models recommend for this Mac.
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
/// kana and most Korean (CER 76% and 77%) and had 32% English WER. Other
/// languages keep Whisper Large v3 Turbo.
public struct LocalSpeechRecommendation: Equatable, Sendable {
    public enum Model: String, Equatable, Sendable, CaseIterable {
        case qwen3Large, senseVoice, whisperTurbo, parakeetEnglish
    }

    public enum Reason: Equatable, Sendable {
        /// Chinese system language with enough memory for Qwen3-ASR 1.7B.
        case mixedChineseEnglish
        /// A Chinese, Japanese or Korean system language on a Mac with 8 GB of
        /// memory or less.
        case limitedMemory
        /// The best measured choice for this system language.
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
        case "en":
            return .init(model: .parakeetEnglish, reason: .systemLanguage, alternatives: [.qwen3Large])
        case "ja", "ko":
            return physicalMemory <= limitedMemoryBytes
                ? .init(model: .whisperTurbo, reason: .limitedMemory, alternatives: [.qwen3Large])
                : .init(model: .qwen3Large, reason: .systemLanguage, alternatives: [.whisperTurbo])
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
