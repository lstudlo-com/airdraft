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

    public var sizeLabel: String {
        switch self {
        case .turbo: return "1.5 GB"
        case .largeV3: return "3.1 GB"
        case .turboCompressed: return "626 MB"
        case .distilLargeV3, .distilTurbo: return "1.5 GB"
        case .distilLargeV3Compressed: return "594 MB"
        case .distilTurboCompressed: return "600 MB"
        }
    }

    public var note: String {
        switch self {
        case .turbo: return "Runs on the Neural Engine."
        case .largeV3: return "Full-size multilingual model."
        case .turboCompressed: return "Compressed Core ML weights."
        case .distilLargeV3, .distilLargeV3Compressed, .distilTurbo, .distilTurboCompressed:
            return "English-only distilled Whisper weights."
        }
    }
}
