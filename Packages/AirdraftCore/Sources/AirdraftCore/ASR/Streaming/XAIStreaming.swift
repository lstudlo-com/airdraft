import Foundation

/// xAI streaming speech to text
/// (https://docs.x.ai/developers/model-capabilities/audio/speech-to-text and
/// https://docs.x.ai/developers/rest-api-reference/inference/speech-to-text, checked 2026-10-28).
/// Bearer auth on the handshake, settings in the query, raw PCM16 binary frames.
/// `transcript.partial` with `is_final=false` is interim text, `is_final=true`
/// locks a chunk, and `speech_final=true` restates the whole stitched utterance.
/// `{"type":"audio.done"}` makes the server flush, send its last events and
/// `transcript.done`, then close. Errors are `{"type":"error","message":…}`.
///
/// Mirrors the batch request: `grok-voice-transcribe-2.0`, the resolved language,
/// formatting and the same keyterms.
struct XAIStreaming: StreamingSpeechProvider {
    static let endpoint = "wss://api.x.ai/v1/stt"
    static let model = "grok-voice-transcribe-2.0"
    let hints: TranscriptionHints
    let engineID: String

    /// The streaming endpoint serves the batch model ID, `grok-voice-transcribe-2.0`.
    var matchesBatchModel: Bool { true }

    func request(apiKey: String) async throws -> URLRequest {
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .xAI, language: hints.languageCode ?? "auto")).language
        var query: [(String, String)] = [
            ("model", Self.model), ("encoding", "pcm"), ("sample_rate", "\(sampleRate)"),
            ("interim_results", "true"),
        ]
        if let language {
            // The batch request always asks for formatting, which xAI applies
            // only with a language; streaming documents it as requiring one.
            query += [("language", language), ("format", "true")]
        }
        query += hints.vocabularyTerms.prefix(100).map { ("keyterm", String($0.prefix(100))) }
        var request = URLRequest(url: try Self.url(Self.endpoint, query))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] { [] }

    func audioFrame(_ pcm16: Data) -> StreamingFrame { .data(pcm16) }

    func endFrames() -> [StreamingFrame] { [.json(["type": "audio.done"])] }

    func makeParser() -> any StreamingParser { Parser(language: hints.isoLanguage) }

    /// Query values are encoded strictly so a `+` or `&` in a keyterm stays literal.
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

    /// Finished utterances (`speech_final`) are kept whole; locked chunks of the
    /// current utterance are held until its utterance final replaces them.
    final class Parser: StreamingParser {
        private var utterances = ""
        private var chunks = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false
        /// The docs ask clients to wait for `transcript.created` before sending audio.
        private(set) var readyForAudio = false

        init(language: String? = nil) { self.language = language }

        var finalText: String { ModelSpeechPreview.join(utterances, chunks) }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            if let code = object["language"] as? String, !code.isEmpty { language = code }
            let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch object["type"] as? String {
            case "transcript.partial":
                if object["speech_final"] as? Bool == true {
                    // The utterance final restates every earlier chunk of the utterance.
                    utterances = ModelSpeechPreview.join(utterances, text)
                    chunks = ""
                    provisional = ""
                } else if object["is_final"] as? Bool == true {
                    chunks = ModelSpeechPreview.join(chunks, text)
                    provisional = ""
                } else {
                    provisional = text
                }
            case "transcript.done":
                finish(with: text)
            case "error":
                let message = object["message"] as? String ?? "Unknown error"
                throw StreamingError.provider("xAI: \(message)")
            case "transcript.created":
                readyForAudio = true
            default:
                break // Other session events.
            }
        }

        /// `transcript.done` carries the final text: either the whole session or
        /// the last utterance's restatement, which the docs leave unspecified.
        private func finish(with text: String) {
            defer {
                provisional = ""
                finished = true
            }
            guard !text.isEmpty, text != finalText else { return }
            if utterances.isEmpty || (text.hasPrefix(utterances) && text.count >= finalText.count) {
                // The whole session's transcript.
                utterances = text
                chunks = ""
            } else if !chunks.isEmpty {
                // The last utterance, whose speech_final never arrived.
                utterances = ModelSpeechPreview.join(utterances, text)
                chunks = ""
            }
        }
    }
}
