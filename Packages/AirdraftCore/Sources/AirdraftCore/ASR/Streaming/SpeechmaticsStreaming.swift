import Foundation
import Synchronization

/// Speechmatics real-time v2
/// (https://docs.speechmatics.com/api-ref/realtime-transcription-websocket,
/// https://docs.speechmatics.com/introduction/supported-languages, checked 2026-10-28),
/// on the EU endpoint that matches Airdraft's EU batch region. Speechmatics runs
/// "the same models for both batch and real-time"; this sends the batch request's
/// Enhanced model, language and additional vocabulary, and leaves `max_delay` at
/// its most accurate default (4 s). Automatic language identification is batch
/// only, so a recording under Auto shows no live text here.
struct SpeechmaticsStreaming: StreamingSpeechProvider {
    static let endpoint = URL(string: "wss://eu.rt.speechmatics.com/v2/")!
    /// The wire language code (Mandarin as `cmn`, as in the batch request).
    let wireLanguage: String
    /// The ISO language recorded on the transcript, as the batch transcriber does.
    let isoLanguage: String
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { true }
    /// `EndOfStream.last_seq_no` is the number of audio chunks sent; the server
    /// numbers each `AudioAdded` from 1.
    private let audioFrames = AudioFrameCounter()

    /// Nil when the effective language is Auto or one Enhanced does not support.
    init?(config: ASRConfig, hints: TranscriptionHints) {
        let requested = hints.languageCode ?? config.language
        guard let resolved = try? SpeechLanguagePolicy.resolve(ASRConfig(kind: .speechmatics, language: requested)),
              let language = resolved.language else { return nil }
        wireLanguage = language == "zh" ? "cmn" : language
        isoLanguage = hints.isoLanguage ?? language
        self.hints = hints
        engineID = config.engineID
    }

    func request(apiKey: String) async throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] {
        var config: [String: Any] = ["language": wireLanguage, "model": "enhanced", "enable_partials": true]
        let terms = hints.vocabularyTerms.prefix(100).map { ["content": String($0.prefix(100))] }
        if !terms.isEmpty { config["additional_vocab"] = terms }
        let format: [String: Any] = ["type": "raw", "encoding": "pcm_s16le", "sample_rate": sampleRate]
        return [.json(["message": "StartRecognition", "audio_format": format, "transcription_config": config])]
    }

    func audioFrame(_ pcm16: Data) -> StreamingFrame {
        audioFrames.increment()
        return .data(pcm16)
    }

    /// The server sends every remaining AddTranscript, then EndOfTranscript.
    func endFrames() -> [StreamingFrame] {
        [.json(["message": "EndOfStream", "last_seq_no": audioFrames.count])]
    }

    func makeParser() -> any StreamingParser { Parser(language: isoLanguage) }

    final class AudioFrameCounter: Sendable {
        private let value = Mutex(0)
        var count: Int { value.withLock { $0 } }
        func increment() { value.withLock { $0 += 1 } }
    }

    /// Each AddTranscript is a finalized segment; each AddPartialTranscript
    /// replaces the text after the last final one.
    final class Parser: StreamingParser {
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false
        /// Audio is sent once the server confirms `RecognitionStarted`.
        private(set) var readyForAudio = false

        init(language: String?) { self.language = language }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            switch object["message"] as? String {
            case "Error":
                let reason = object["reason"] as? String ?? object["type"] as? String ?? "Unknown error"
                throw StreamingError.provider("Speechmatics: \(reason)")
            case "AddTranscript":
                let text = Self.text(of: object)
                if !text.isEmpty { finalText = ModelSpeechPreview.join(finalText, text) }
                provisional = ""
            case "AddPartialTranscript":
                provisional = Self.text(of: object)
            case "RecognitionStarted":
                readyForAudio = true
            case "EndOfTranscript":
                provisional = ""
                finished = true
            default:
                // RecognitionStarted, AudioAdded, Info, Warning.
                break
            }
        }

        /// `metadata.transcript`, or the words themselves when it is missing.
        private static func text(of object: [String: Any]) -> String {
            if let transcript = (object["metadata"] as? [String: Any])?["transcript"] as? String {
                return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let words = (object["results"] as? [[String: Any]] ?? []).compactMap { result -> String? in
                ((result["alternatives"] as? [[String: Any]])?.first?["content"] as? String)
            }
            return words.reduce("") { ModelSpeechPreview.join($0, $1) }
        }
    }
}
