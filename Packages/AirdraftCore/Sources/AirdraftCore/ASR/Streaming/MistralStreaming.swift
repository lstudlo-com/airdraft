import Foundation

/// Mistral real-time transcription
/// (https://docs.mistral.ai/studio/audio/speech-to-text/transcribe-in-realtime,
/// https://docs.mistral.ai/studio/audio/speech-to-text/bias-context-and-vocabulary,
/// https://docs.mistral.ai/studio/audio/speech-to-text/troubleshooting and
/// https://docs.mistral.ai/models/voxtral-mini-transcribe-realtime-3-0, checked
/// 2026-10-28): the model in the URL query, Bearer key header, one `session.update`
/// before the first audio (settings lock once audio starts), base64 PCM16 at 16 kHz
/// in `input_audio.append`, then `input_audio.end` → `transcription.done`.
///
/// Display-only: Voxtral Mini Transcribe Realtime 3 is a separate streaming model
/// from the batch `voxtral-mini-latest` Airdraft transcribes with.
struct MistralStreaming: StreamingSpeechProvider {
    static let model = "voxtral-mini-transcribe-realtime-3"
    static let endpoint = URL(string: "wss://api.mistral.ai/v1/audio/transcriptions/realtime?model=\(model)")!
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { false }

    func request(apiKey: String) async throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] {
        let format: [String: Any] = ["encoding": "pcm_s16le", "sample_rate": sampleRate]
        var session: [String: Any] = ["audio_format": format]
        // The batch request's language; the session takes only a two-letter ISO 639-1 code.
        if let language = Self.language(hints) { session["language"] = language }
        let terms = hints.vocabularyTerms.prefix(100).map { String($0.prefix(100)) }
        if !terms.isEmpty { session["context_bias"] = terms }
        return [.json(["type": "session.update", "session": session])]
    }

    static func language(_ hints: TranscriptionHints) -> String? {
        let config = ASRConfig(kind: .mistral, language: hints.languageCode ?? "auto")
        guard let language = (try? SpeechLanguagePolicy.resolve(config))?.language,
              language.count == 2, language.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return language
    }

    func audioFrame(_ pcm16: Data) -> StreamingFrame {
        .json(["type": "input_audio.append", "audio": pcm16.base64EncodedString()])
    }

    func endFrames() -> [StreamingFrame] { [.json(["type": "input_audio.end"])] }

    func makeParser() -> any StreamingParser { Parser() }

    /// Deltas are final when they arrive and carry their own spacing, so they are
    /// appended as is; `transcription.done` carries the transcript of record.
    final class Parser: StreamingParser {
        private(set) var finalText = ""
        var provisional: String { "" }
        private(set) var language: String?
        private(set) var finished = false
        /// The docs ask clients to wait for `session.created` before configuring the session.
        private(set) var readyForStart = false

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            switch object["type"] as? String {
            case "session.created":
                readyForStart = true
            case "error":
                throw StreamingError.provider("Mistral: \(Self.message(object["error"]))")
            case "transcription.text.delta":
                if let text = object["text"] as? String { finalText += text }
            case "transcription.done":
                if let text = object["text"] as? String, !text.isEmpty { finalText = text }
                if let code = object["language"] as? String, !code.isEmpty { language = code }
                finished = true
            default:
                break
            }
        }

        private static func message(_ error: Any?) -> String {
            guard let error = error as? [String: Any] else { return "Unknown error" }
            if let message = error["message"] as? String, !message.isEmpty { return message }
            if let detail = error["message"], JSONSerialization.isValidJSONObject(detail),
               let data = try? JSONSerialization.data(withJSONObject: detail, options: [.sortedKeys]) {
                return String(decoding: data, as: UTF8.self)
            }
            if let code = error["code"] { return "\(code)" }
            return "Unknown error"
        }
    }
}
