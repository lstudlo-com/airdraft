import Foundation

/// Exact Core ML variants available through Argmax's public model repository.
/// These v3 variants share the existing v3 tokenizer and retain word timing.
public enum WhisperModelVariant: String, CaseIterable, Codable, Sendable {
    case turbo = "large-v3-v20240930_turbo"
    case largeV3 = "large-v3"
    case turboCompressed = "large-v3-v20240930_626MB"
    case distilLargeV3 = "distil-large-v3"
    case distilLargeV3Compressed = "distil-large-v3_594MB"
    case distilTurbo = "distil-large-v3_turbo"
    case distilTurboCompressed = "distil-large-v3_turbo_600MB"

    public var isEnglishOnly: Bool { rawValue.hasPrefix("distil-") }
    public var directoryName: String { (isEnglishOnly ? "distil-whisper_" : "openai_whisper-") + rawValue }

    public var title: String {
        switch self {
        case .turbo: return "Whisper Large v3 Turbo"
        case .largeV3: return "Whisper Large v3"
        case .turboCompressed: return "Whisper Large v3 Turbo (Compressed)"
        case .distilLargeV3: return "Distil-Whisper Large v3"
        case .distilLargeV3Compressed: return "Distil-Whisper Large v3 (Compressed)"
        case .distilTurbo: return "Distil-Whisper Large v3 Turbo"
        case .distilTurboCompressed: return "Distil-Whisper Large v3 Turbo (Compressed)"
        }
    }

    /// The pinned download, so the label always matches the bytes the app fetches.
    public var sizeLabel: String {
        PinnedHubModelCatalog.whisper(self)?.sizeLabel ?? ""
    }

    public var note: String {
        switch self {
        case .turbo: return String(localized: "Runs on the Neural Engine.", bundle: .module)
        case .largeV3: return String(localized: "Full-size multilingual model.", bundle: .module)
        case .turboCompressed: return String(localized: "Compressed Core ML weights.", bundle: .module)
        case .distilLargeV3, .distilLargeV3Compressed, .distilTurbo, .distilTurboCompressed:
            return String(localized: "English-only distilled Whisper weights.", bundle: .module)
        }
    }
}
