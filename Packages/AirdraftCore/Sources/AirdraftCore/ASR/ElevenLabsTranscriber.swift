import Foundation

/// ElevenLabs Scribe v2 file transcription. Paid keyterm prompting is opt-in
/// upstream and deliberately omitted; dictionary correction still runs last.
public struct ElevenLabsTranscriber: Transcriber {
    public let id: String
    public let modelId: String
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP

    public init(modelId: String = "scribe_v2", apiKey: String?, timeout: TimeInterval = 60, id: String? = nil, session: URLSession = .shared) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.timeout = timeout
        self.http = TranscriptionHTTP(session: session)
        self.id = id ?? "elevenlabs:\(modelId)"
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let apiKey = try TranscriptionHTTP.requireKey(apiKey, provider: "ElevenLabs")

        var fields: [(String, String)] = [("model_id", modelId), ("tag_audio_events", "false"), ("diarize", "false")]
        if let lang = hints.isoLanguage { fields.append(("language_code", lang)) }
        let form = MultipartForm()

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = form.body(fields: fields, wav: WAVEncoder.encode(samples: samples))

        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable { let text: String; let language_code: String? }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines), language: reply.language_code ?? hints.language, engine: id, latencyMs: ms)
    }
}
