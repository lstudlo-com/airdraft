import Foundation

/// Deepgram live streaming (https://developers.deepgram.com/reference/speech-to-text/listen-streaming,
/// https://developers.deepgram.com/docs/close-stream and
/// https://developers.deepgram.com/docs/language-detection, checked 2026-10-28).
/// `Authorization: Token`, options in the query, raw linear16 binary frames.
/// Results with `is_final` are finished segments; `CloseStream` makes the server
/// process the remaining audio, send its last Results and then a summary
/// Metadata message before it closes.
///
/// The batch request's model, `smart_format` and wire language are mirrored
/// exactly, and like the batch request no keyterms are sent. Streaming has no
/// language detection, so automatic detection streams `language=multi` instead,
/// which is a different language set: that live text is display only.
struct DeepgramStreaming: StreamingSpeechProvider {
    static let endpoint = "wss://api.deepgram.com/v1/listen"
    /// `nova-3` or `nova-3-multilingual`; Deepgram's Whisper has no streaming API.
    let model: String
    let hints: TranscriptionHints
    let engineID: String

    /// The batch request's `language`, or nil when it detects the language.
    private var batchLanguage: String? {
        try? DeepgramTranscriber.requestLanguage(model: model, hints: hints)
    }

    /// Same Nova-3 model and options as the batch request whenever the batch
    /// request names a language (including `multi` for Nova-3 Multilingual).
    /// Batch dominant-language detection has no streaming equivalent.
    var matchesBatchModel: Bool { batchLanguage != nil }

    func request(apiKey: String) async throws -> URLRequest {
        // Unsupported languages fail here exactly as the batch request would.
        let language = try DeepgramTranscriber.requestLanguage(model: model, hints: hints) ?? "multi"
        let query: [(String, String)] = [
            ("model", "nova-3"), ("language", language), ("smart_format", "true"),
            ("encoding", "linear16"), ("sample_rate", "\(sampleRate)"), ("channels", "1"),
            ("interim_results", "true"),
        ]
        var request = URLRequest(url: try Self.url(Self.endpoint, query))
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] { [] }

    func audioFrame(_ pcm16: Data) -> StreamingFrame { .data(pcm16) }

    /// The server finalizes buffered audio, sends the last Results, then Metadata.
    func endFrames() -> [StreamingFrame] { [.json(["type": "CloseStream"])] }

    func makeParser() -> any StreamingParser {
        let language = batchLanguage
        return Parser(language: language == "multi" ? nil : language)
    }

    /// Query values are encoded strictly so a `+` or `&` stays literal.
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

    /// Each final Results message is a new segment without leading spacing; the
    /// batch transcript separates them with a space, except next to CJK text.
    final class Parser: StreamingParser {
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false

        init(language: String? = nil) { self.language = language }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            switch object["type"] as? String {
            case "Results":
                let channel = object["channel"] as? [String: Any]
                let alternative = (channel?["alternatives"] as? [[String: Any]])?.first
                let text = alternative?["transcript"] as? String ?? ""
                if language == nil, let detected = (alternative?["languages"] as? [String])?.first {
                    language = detected
                }
                if object["is_final"] as? Bool == true {
                    finalText = ModelSpeechPreview.join(finalText, text)
                    provisional = ""
                } else {
                    provisional = text
                }
            case "Metadata":
                // The summary Deepgram sends after the last Results of a closed stream.
                finished = true
            case "Error":
                let message = object["description"] as? String ?? object["message"] as? String
                    ?? object["variant"] as? String ?? "Unknown error"
                throw StreamingError.provider("Deepgram: \(message)")
            default:
                // Older error replies use err_code/err_msg without a type.
                if let message = object["err_msg"] as? String {
                    throw StreamingError.provider("Deepgram: \(message)")
                }
            }
        }
    }
}
