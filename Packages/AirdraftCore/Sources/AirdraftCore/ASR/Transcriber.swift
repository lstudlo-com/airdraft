import Foundation

public struct TranscriptionHints: Sendable {
    /// ISO 639-1 code, or nil for auto-detect.
    public var language: String?
    /// Dictionary terms used to bias decoding.
    public var vocabulary: [String]
    public var chineseScript: ChineseScript

    public init(language: String? = nil, vocabulary: [String] = [], chineseScript: ChineseScript = .auto) {
        self.language = language
        self.vocabulary = vocabulary
        self.chineseScript = chineseScript
    }

    /// Whisper-style "initial prompt". A short sentence in the wanted script
    /// steers Whisper's Chinese output far more reliably than the language flag.
    /// Whisper treats the prompt as preceding speech and repeats bare terms on
    /// silence or trailing audio, so dictionary terms stay out of it; the LLM
    /// and dictionary aliases apply them after transcription.
    /// Only sent when Chinese is the selected language: with auto-detect a
    /// Chinese prompt pulls detection to Chinese and Whisper translates English
    /// speech. `ChineseScriptConverter` still normalises the script afterwards.
    public var promptText: String? {
        guard let code = language?.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-").first?.lowercased(),
              code == "zh" || code == "yue" else { return nil }
        switch chineseScript {
        case .traditional: return "以下是繁體中文的內容。"
        case .simplified: return "以下是简体中文的内容。"
        case .auto: return nil
        }
    }

    /// Context for engines with a dedicated hot-word context (Qwen3-ASR).
    public var contextText: String? {
        let terms = vocabulary.filter { !$0.isEmpty }
        let parts = [promptText, terms.isEmpty ? nil : terms.joined(separator: ", ")].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var language: String?
    public var engine: String
    public var latencyMs: Int

    public init(text: String, language: String? = nil, engine: String, latencyMs: Int) {
        self.text = text
        self.language = language
        self.engine = engine
        self.latencyMs = latencyMs
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public protocol Transcriber: Sendable {
    /// Stable identifier for history records, e.g. "whisperkit:large-v3-v20240930_turbo".
    var id: String { get }
    /// False while a local model still has to be loaded or compiled.
    func isReady() async -> Bool
    /// Load models, warm caches. Safe to call repeatedly.
    func prepare() async throws
    /// Release model memory. The next transcribe loads again.
    func unload() async
    /// `samples` are 16 kHz mono Float32 in -1...1.
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript
}

public extension Transcriber {
    func isReady() async -> Bool { true }
    func unload() async {}
}

public enum TranscriberError: Error, LocalizedError {
    case emptyAudio
    case http(status: Int, body: String)
    case invalidResponse
    case modelNotDownloaded
    case appleUnavailable
    case missingAPIKey(String)
    case timedOut
    case providerFailure(String, String)

    public var errorDescription: String? {
        switch self {
        case .emptyAudio: return "No audio was captured."
        case .http(let status, let body):
            let detail = ProviderErrorBody.summary(body).map { ": \($0)" } ?? "."
            return "Speech provider returned HTTP \(status)\(detail)"
        case .invalidResponse: return "The speech provider returned an unexpected response."
        case .modelNotDownloaded: return "Speech model is not downloaded. Download it on the Models page."
        case .appleUnavailable: return "Apple speech recognition needs macOS 26 or newer."
        case .missingAPIKey(let provider): return "Add your \(provider) API key on the Models page."
        case .timedOut: return "Transcription took too long. Please try again."
        case .providerFailure(let provider, let message): return "\(provider): \(message.prefix(300))"
        }
    }
}
