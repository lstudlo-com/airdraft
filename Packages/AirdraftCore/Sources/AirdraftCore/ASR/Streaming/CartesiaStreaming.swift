import Foundation

/// Cartesia streaming speech to text (https://docs.cartesia.ai/api-reference/stt/stt,
/// checked 2026-10-28). `X-API-Key` on the handshake; model, language, encoding,
/// sample rate and the required `cartesia_version` in the query; raw PCM16
/// binary frames. Each `transcript` with `is_final` is a delta from the previous
/// final one, carrying its own spacing. The text command `close` flushes the
/// remaining audio and the server acknowledges with `done`. Errors are
/// `{"type":"error","status_code":…,"title":…,"message":…}`.
///
/// Mirrors the batch request: `ink-whisper` with the same explicit language;
/// like the file endpoint, it never streams without one (Ink-Whisper's
/// streaming default would otherwise silently be English).
struct CartesiaStreaming: StreamingSpeechProvider {
    static let endpoint = "wss://api.cartesia.ai/stt/websocket"
    static let model = "ink-whisper"
    let hints: TranscriptionHints
    let engineID: String

    /// The streaming endpoint serves the batch model ID, `ink-whisper`.
    var matchesBatchModel: Bool { true }

    func request(apiKey: String) async throws -> URLRequest {
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .cartesia, language: hints.languageCode ?? "auto")).language
        guard let language else { throw SpeechLanguageError.automaticUnavailable(model: "Ink-Whisper") }
        let query: [(String, String)] = [
            ("model", Self.model), ("language", language), ("encoding", "pcm_s16le"),
            ("sample_rate", "\(sampleRate)"), ("cartesia_version", CartesiaTranscriber.apiVersion),
        ]
        var request = URLRequest(url: try Self.url(Self.endpoint, query))
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(CartesiaTranscriber.apiVersion, forHTTPHeaderField: "Cartesia-Version")
        return request
    }

    func startFrames() -> [StreamingFrame] { [] }

    func audioFrame(_ pcm16: Data) -> StreamingFrame { .data(pcm16) }

    func endFrames() -> [StreamingFrame] { [.text("close")] }

    func makeParser() -> any StreamingParser { Parser(language: hints.isoLanguage) }

    private static func url(_ base: String, _ query: [(String, String)]) throws -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        var components = URLComponents(string: base)
        components?.percentEncodedQuery = query.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    /// Final deltas are concatenated as sent: Cartesia says not to strip or add
    /// whitespace between chunks.
    final class Parser: StreamingParser {
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false

        init(language: String? = nil) { self.language = language }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            switch object["type"] as? String {
            case "transcript":
                if let code = object["language"] as? String, !code.isEmpty { language = code }
                let text = object["text"] as? String ?? ""
                if object["is_final"] as? Bool == true {
                    finalText += text
                    provisional = ""
                } else {
                    provisional = text
                }
            case "done":
                // Acknowledges `close` after the remaining audio was transcribed.
                finished = true
            case "error":
                let message = object["message"] as? String ?? object["title"] as? String ?? "Unknown error"
                throw StreamingError.provider("Cartesia: \(message)")
            default:
                break // flush_done acknowledges a finalize command Airdraft does not send.
            }
        }
    }
}
