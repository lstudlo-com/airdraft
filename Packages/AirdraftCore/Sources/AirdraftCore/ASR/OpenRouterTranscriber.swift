import Foundation

/// OpenRouter's transcription endpoint uses JSON with base64-encoded audio,
/// unlike the multipart OpenAI-compatible transcription endpoint.
public struct OpenRouterTranscriber: Transcriber {
    public let id: String
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP

    public init(model: String = "openai/whisper-1", apiKey: String?, timeout: TimeInterval = 75,
                session: URLSession = .shared) {
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.id = "openRouter:\(model)"
        self.http = TranscriptionHTTP(session: session)
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "OpenRouter")

        var body: [String: Any] = [
            "model": model,
            "input_audio": ["data": WAVEncoder.encode(samples: samples).base64EncodedString(), "format": "wav"]
        ]
        if let language = hints.isoLanguage { body["language"] = language }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        // OpenRouter documents an approximately 60-second upstream limit.
        // Leave time for upload and response delivery before the local deadline.
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable { let text: String }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        return Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines),
                          language: hints.language, engine: id,
                          latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}
