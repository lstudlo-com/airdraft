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

    public init(baseURL: URL, model: String, apiKey: String?, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.id = "openai-compatible:\(baseURL.host ?? "?")/\(model)"
    }

    public func prepare() async throws {}

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let started = Date()

        var fields: [(String, String)] = [("model", model), ("response_format", "json")]
        if let lang = hints.language { fields.append(("language", lang)) }
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriberError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriberError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        struct Reply: Decodable { let text: String; let language: String? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw TranscriberError.invalidResponse
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(
            text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: reply.language ?? hints.language,
            engine: id,
            latencyMs: ms
        )
    }
}
