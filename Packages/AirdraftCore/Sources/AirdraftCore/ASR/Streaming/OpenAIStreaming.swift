import Foundation

/// OpenAI real-time transcription
/// (https://developers.openai.com/api/docs/guides/realtime-transcription,
/// https://developers.openai.com/api/docs/guides/voice-websockets and
/// https://developers.openai.com/api/reference/resources/realtime/server-events,
/// checked 2026-10-28): a `transcription` session on
/// `wss://api.openai.com/v1/realtime?intent=transcription`, Bearer key header,
/// 24 kHz PCM16 sent as base64 `input_audio_buffer.append`, no turn detection and
/// one `input_audio_buffer.commit` at release.
///
/// Display-only: live text needs `gpt-live-transcribe`, which streams deltas while
/// audio arrives. The batch models (`gpt-transcribe`, `gpt-4o-transcribe`,
/// `gpt-4o-mini-transcribe`) are different models; `gpt-transcribe` runs in a
/// Realtime session only after a committed turn, so it cannot show live text.
struct OpenAIStreaming: StreamingSpeechProvider {
    static let endpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
    static let model = "gpt-live-transcribe"
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { false }
    var sampleRate: Int { 24_000 }

    func request(apiKey: String) async throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] {
        var transcription: [String: Any] = ["model": Self.model, "delay": "low"]
        if let language = hints.isoLanguage { transcription["languages"] = [language] }
        // The same keyword rules as the batch request: these characters reject the whole update.
        let forbidden = CharacterSet(charactersIn: "<>\r\n")
        let keywords = hints.vocabularyTerms.filter { $0.rangeOfCharacter(from: forbidden) == nil }
            .prefix(100).map { String($0.prefix(100)) }
        if !keywords.isEmpty { transcription["keywords"] = keywords }
        // Only the Chinese script sentence; it describes the recording, as `prompt` expects.
        if let prompt = hints.promptText { transcription["prompt"] = prompt }
        let input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": sampleRate] as [String: Any],
            "transcription": transcription,
            // gpt-live-transcribe supports neither server_vad nor semantic_vad.
            "turn_detection": NSNull(),
        ]
        let session: [String: Any] = ["type": "transcription", "audio": ["input": input]]
        return [.json(["type": "session.update", "session": session])]
    }

    func audioFrame(_ pcm16: Data) -> StreamingFrame {
        .json(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
    }

    /// Without turn detection this is the session's only commit, so its item is the last one.
    func endFrames() -> [StreamingFrame] { [.json(["type": "input_audio_buffer.commit"])] }

    func makeParser() -> any StreamingParser { Parser() }

    /// Deltas are appended per item; a completed item's transcript replaces them.
    /// Items are kept in first-seen order because completions may arrive out of order.
    final class Parser: StreamingParser {
        private var order: [String] = []
        private var deltas: [String: String] = [:]
        private var completed: [String: String] = [:]
        private var committed: [String] = []
        private var endedEmpty = false
        private(set) var language: String?

        var finalText: String {
            order.compactMap { completed[$0] }.reduce("") { ModelSpeechPreview.join($0, $1) }
        }

        var provisional: String {
            order.filter { completed[$0] == nil }.compactMap { deltas[$0] }.reduce("") { ModelSpeechPreview.join($0, $1) }
        }

        /// Every committed item has its final transcript (or failed), or the commit had no audio.
        var finished: Bool {
            endedEmpty || (!committed.isEmpty && committed.allSatisfy { completed[$0] != nil })
        }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            let item = object["item_id"] as? String ?? ""
            switch object["type"] as? String {
            case "error":
                let error = object["error"] as? [String: Any] ?? [:]
                // A release before any audio was sent: nothing is left to transcribe.
                if error["code"] as? String == "input_audio_buffer_commit_empty" {
                    endedEmpty = true
                    return
                }
                throw StreamingError.provider("OpenAI: \(Self.message(error))")
            case "input_audio_buffer.committed":
                note(item)
                if !committed.contains(item) { committed.append(item) }
            case "conversation.item.input_audio_transcription.delta":
                note(item)
                if let delta = object["delta"] as? String { deltas[item, default: ""] += delta }
            case "conversation.item.input_audio_transcription.completed":
                note(item)
                completed[item] = (object["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                deltas[item] = nil
                if language == nil, let languages = object["languages"] as? [[String: Any]],
                   let code = languages.first?["code"] as? String, !code.isEmpty {
                    language = code
                }
            case "conversation.item.input_audio_transcription.failed":
                throw StreamingError.provider("OpenAI: \(Self.message(object["error"] as? [String: Any] ?? [:]))")
            default:
                break
            }
        }

        private func note(_ item: String) {
            if !order.contains(item) { order.append(item) }
        }

        private static func message(_ error: [String: Any]) -> String {
            if let message = error["message"] as? String, !message.isEmpty { return message }
            if let code = error["code"] as? String, !code.isEmpty { return code }
            return error["type"] as? String ?? "Unknown error"
        }
    }
}
