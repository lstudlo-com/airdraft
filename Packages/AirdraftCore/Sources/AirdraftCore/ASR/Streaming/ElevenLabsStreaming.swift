import Foundation

/// ElevenLabs Scribe realtime
/// (https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime,
/// https://elevenlabs.io/docs/eleven-api/guides/cookbooks/speech-to-text/realtime/transcripts-and-commit-strategies,
/// checked 2026-10-28). Realtime runs `scribe_v2_realtime`, a different model from
/// the batch `scribe_v2`, so live text is display-only and the batch request still
/// produces the transcript. Voice activity commits segments at pauses (the
/// documented choice for microphone audio), so a long dictation keeps showing
/// settled text; release commits the rest. Keyterms are a paid add-on that the
/// batch request omits, so they are omitted here too.
struct ElevenLabsStreaming: StreamingSpeechProvider {
    static let endpoint = URL(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { false }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
                     URLQueryItem(name: "audio_format", value: "pcm_\(sampleRate)"),
                     URLQueryItem(name: "commit_strategy", value: "vad")]
        if let language = hints.isoLanguage { items.append(URLQueryItem(name: "language_code", value: language)) }
        return items
    }

    func request(apiKey: String) async throws -> URLRequest {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw StreamingError.invalidMessage }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        return request
    }

    func startFrames() -> [StreamingFrame] { [] }

    func audioFrame(_ pcm16: Data) -> StreamingFrame { chunk(pcm16, commit: false) }

    /// An empty chunk that commits the uncommitted audio.
    func endFrames() -> [StreamingFrame] { [chunk(Data(), commit: true)] }

    func makeParser() -> any StreamingParser { Parser(language: hints.isoLanguage) }

    private func chunk(_ pcm16: Data, commit: Bool) -> StreamingFrame {
        .json(["message_type": "input_audio_chunk", "audio_base_64": pcm16.base64EncodedString(),
               "commit": commit, "sample_rate": sampleRate])
    }

    /// Partial transcripts cover the uncommitted audio and replace each other;
    /// each committed transcript is one settled segment. ElevenLabs sends no
    /// end-of-input acknowledgement, so `finished` stays false: the text is
    /// display-only and release never waits for it.
    final class Parser: StreamingParser {
        static let errorTypes: Set<String> = [
            "error", "auth_error", "quota_exceeded", "commit_throttled", "unaccepted_terms", "rate_limited",
            "queue_overflow", "resource_exhausted", "session_time_limit_exceeded", "input_error",
            "invalid_request", "chunk_size_exceeded", "insufficient_audio_activity", "transcriber_error",
        ]
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false

        init(language: String?) { self.language = language }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            let type = object["message_type"] as? String ?? ""
            if Self.errorTypes.contains(type) {
                let message = object["error"] as? String ?? type
                throw StreamingError.provider("ElevenLabs: \(message)")
            }
            switch type {
            case "partial_transcript":
                provisional = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            case "committed_transcript":
                let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { finalText = ModelSpeechPreview.join(finalText, text) }
                provisional = ""
            default:
                // session_started, warning, and the timestamp or entity variants
                // of a commit, which are not requested.
                break
            }
        }
    }
}
