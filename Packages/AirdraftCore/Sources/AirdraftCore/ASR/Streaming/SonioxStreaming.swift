import Foundation

/// Soniox real-time v5 (https://soniox.com/docs/stt/api-reference/websocket-api,
/// checked 2026-10-28). The same v5 model family and accuracy as `stt-async-v5`
/// ("Both run the same model with the same accuracy and features", pricing page),
/// with the batch request's language hints, language identification and terms.
struct SonioxStreaming: StreamingSpeechProvider {
    static let endpoint = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { true }

    func request(apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] {
        var config: [String: Any] = ["model": "stt-rt-v5", "audio_format": "pcm_s16le", "sample_rate": 16_000,
                                     "num_channels": 1, "enable_language_identification": true]
        if let language = hints.isoLanguage { config["language_hints"] = [language] }
        let terms = hints.vocabularyTerms.prefix(100).map { String($0.prefix(100)) }
        if !terms.isEmpty { config["context"] = ["terms": terms] }
        return [.json(config)]
    }

    func audioFrame(_ pcm16: Data) -> StreamingFrame { .data(pcm16) }

    /// An empty text frame ends the stream; every token then becomes final.
    func endFrames() -> [StreamingFrame] { [.text("")] }

    func makeParser() -> any StreamingParser { Parser() }

    /// Tokens carry their own spacing, so text is their concatenation, as in the
    /// batch transcript. Non-final tokens are replaced by each response.
    final class Parser: StreamingParser {
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            if let code = object["error_code"] {
                let message = object["error_message"] as? String ?? "\(code)"
                throw StreamingError.provider("Soniox: \(message)")
            }
            var pending = ""
            for token in object["tokens"] as? [[String: Any]] ?? [] {
                guard let text = token["text"] as? String else { continue }
                // Control markers such as <fin> and <end> are not speech.
                if text.hasPrefix("<"), text.hasSuffix(">") { continue }
                if language == nil, let code = token["language"] as? String { language = code }
                if token["is_final"] as? Bool == true { finalText += text } else { pending += text }
            }
            provisional = pending
            if object["finished"] as? Bool == true { finished = true }
        }
    }
}
