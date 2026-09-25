import Foundation

/// POST {baseURL}/audio/transcriptions. Works with OpenAI (gpt-4o-transcribe,
/// whisper-1), Groq (whisper-large-v3-turbo), and any self-hosted server that
/// speaks the same shape.
public struct OpenAICompatibleTranscriber: Transcriber {
    public let id: String
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP
    private let requiresKey: Bool

    public init(baseURL: URL, model: String, apiKey: String?, timeout: TimeInterval = 30, id: String? = nil, requiresKey: Bool = false, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.http = TranscriptionHTTP(session: session)
        self.requiresKey = requiresKey
        self.id = id ?? "openai-compatible:\(baseURL.host ?? "?")/\(model)"
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        if requiresKey { _ = try TranscriptionHTTP.requireKey(apiKey, provider: "Groq") }
        if baseURL.host == "api.groq.com" { try SpeechInputLimits.validate(sampleCount: samples.count, for: .groq) }

        var fields: [(String, String)] = [("model", model), ("response_format", "json")]
        if let lang = hints.isoLanguage { fields.append(("language", lang)) }
        if let prompt = hints.promptText { fields.append(("prompt", prompt)) }
        let form = MultipartForm()

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = form.body(fields: fields, wav: WAVEncoder.encode(samples: samples))

        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable { let text: String; let language: String? }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(
            text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: reply.language ?? hints.language,
            engine: id,
            latencyMs: ms
        )
    }
}
