import Foundation
import Synchronization

/// Gemini Live transcription
/// (https://ai.google.dev/gemini-api/docs/live-api/live-transcribe,
/// https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens and
/// https://ai.google.dev/api/live, checked 2026-10-28): `gemini-3.5-transcribe-live`
/// over `BidiGenerateContent`, a `setup` message first, base64 PCM16 at 16 kHz in
/// `realtimeInput.audio`, `interimInputTranscription` while speaking and
/// `inputTranscription` per finalized segment, `realtimeInput.audioStreamEnd` at release.
///
/// The documented API-key route puts the key in the URL (`?key=`), so the key only
/// mints a single-use ephemeral token over REST (`x-goog-api-key` header); the
/// socket connects to `BidiGenerateContentConstrained` with `Authorization: Token …`,
/// leaving both key and token out of the URL. Sessions stream for at most 10 minutes,
/// the same as Airdraft's 600-second recording limit.
///
/// Display-only: `gemini-3.5-transcribe-live` is the Live API version of the model;
/// Airdraft's transcript comes from the unary `gemini-3.5-transcribe` request.
struct GeminiStreaming: StreamingSpeechProvider {
    typealias TokenMinter = @Sendable (_ apiKey: String) async throws -> String
    static let endpoint = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained")!
    static let tokenEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/auth_tokens")!
    static let model = "gemini-3.5-transcribe-live"
    let hints: TranscriptionHints
    let engineID: String
    var matchesBatchModel: Bool { false }
    private let mintToken: TokenMinter
    private let inputEnd = InputEnd()

    /// `mintToken` is injected by tests so no network is used.
    init(hints: TranscriptionHints, engineID: String,
         mintToken: @escaping TokenMinter = { try await GeminiStreaming.mintEphemeralToken(apiKey: $0) }) {
        self.hints = hints
        self.engineID = engineID
        self.mintToken = mintToken
    }

    func request(apiKey: String) async throws -> URLRequest {
        let token = try await mintToken(apiKey)
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func startFrames() -> [StreamingFrame] {
        inputEnd.reset()
        var transcription: [String: Any] = ["mode": "VERBATIM"]
        // The batch request's language and vocabulary; an empty list detects the language.
        let config = ASRConfig(kind: .gemini, language: hints.languageCode ?? "auto")
        let language = (try? SpeechLanguagePolicy.resolve(config))?.language
        transcription["languageCodes"] = language.map { [$0] } ?? []
        let terms = Array(hints.vocabularyTerms.prefix(100))
        if !terms.isEmpty { transcription["customVocabulary"] = terms }
        let generation: [String: Any] = ["responseModalities": ["TEXT"]]
        let setup: [String: Any] = ["model": "models/\(Self.model)", "generationConfig": generation,
                                    "inputAudioTranscription": transcription]
        return [.json(["setup": setup])]
    }

    func audioFrame(_ pcm16: Data) -> StreamingFrame {
        let audio: [String: Any] = ["data": pcm16.base64EncodedString(), "mimeType": "audio/pcm;rate=\(sampleRate)"]
        return .json(["realtimeInput": ["audio": audio]])
    }

    /// Finalizes the last turn at once instead of waiting for the server's silence detection.
    func endFrames() -> [StreamingFrame] {
        inputEnd.mark()
        return [.json(["realtimeInput": ["audioStreamEnd": true]])]
    }

    func makeParser() -> any StreamingParser { Parser(inputEnd: inputEnd) }

    // MARK: Ephemeral token

    /// A single-use token: one minute to open the session, fifteen to stream
    /// (the 10-minute session plus release).
    static func tokenRequest(apiKey: String, now: Date = Date()) throws -> URLRequest {
        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = ["uses": 1,
                                   "expireTime": formatter.string(from: now.addingTimeInterval(15 * 60)),
                                   "newSessionExpireTime": formatter.string(from: now.addingTimeInterval(60))]
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The token in a create-token reply, or the provider's error.
    static func token(from data: Data, status: Int) throws -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            var message = "HTTP \(status)"
            if let detail = (object?["error"] as? [String: Any])?["message"] as? String, !detail.isEmpty { message = detail }
            throw StreamingError.provider("Gemini: \(message)")
        }
        // The token goes into a header: refuse anything that is not one printable line.
        guard let name = object?["name"] as? String, !name.isEmpty, name.count <= 4096,
              name.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else {
            throw StreamingError.invalidMessage
        }
        return name
    }

    static func mintEphemeralToken(apiKey: String) async throws -> String {
        let (data, response) = try await ProviderTransport.shared.data(for: tokenRequest(apiKey: apiKey))
        guard let http = response as? HTTPURLResponse else { throw StreamingError.invalidMessage }
        return try token(from: data, status: http.statusCode)
    }

    // MARK: Parsing

    /// Set when the input ends, so a turn finalized mid-recording is not taken for the end.
    final class InputEnd: Sendable {
        private let ended = Mutex(false)
        var isMarked: Bool { ended.withLock { $0 } }
        func mark() { ended.withLock { $0 = true } }
        func reset() { ended.withLock { $0 = false } }
    }

    /// Finalized segments are joined; the interim hypothesis replaces the provisional text.
    /// After the input ends, the next finalized segment or completed turn finishes it.
    final class Parser: StreamingParser {
        private let inputEnd: InputEnd
        private(set) var finalText = ""
        private(set) var provisional = ""
        private(set) var language: String?
        private(set) var finished = false
        /// Nothing follows the setup message until the server sends `setupComplete`.
        private(set) var readyForAudio = false

        init(inputEnd: InputEnd) { self.inputEnd = inputEnd }

        func consume(_ frame: StreamingFrame) throws {
            guard let object = frame.jsonObject else { throw StreamingError.invalidMessage }
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? error["status"] as? String ?? "Unknown error"
                throw StreamingError.provider("Gemini: \(message)")
            }
            if object["setupComplete"] != nil { readyForAudio = true }
            guard let content = object["serverContent"] as? [String: Any] else { return }
            var ending = content["turnComplete"] as? Bool == true
            if let interim = content["interimInputTranscription"] as? [String: Any] {
                provisional = (interim["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                note(interim)
            }
            if let finalized = content["inputTranscription"] as? [String: Any] {
                finalText = ModelSpeechPreview.join(finalText, finalized["text"] as? String ?? "")
                provisional = ""
                note(finalized)
                ending = true
            }
            if ending, inputEnd.isMarked { finished = true }
        }

        private func note(_ transcription: [String: Any]) {
            guard language == nil, let code = transcription["languageCode"] as? String,
                  let base = code.split(separator: "-").first, !base.isEmpty else { return }
            language = base.lowercased()
        }
    }
}
