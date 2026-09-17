import Foundation

/// ElevenLabs Scribe (v2 by default): strongest commercial multilingual
/// model in 2026 benchmarks, including Mandarin. Audio leaves the machine.
public struct ElevenLabsTranscriber: Transcriber {
    public let id: String
    public let modelId: String
    public let apiKey: String?
    public let timeout: TimeInterval

    public init(modelId: String = "scribe_v2", apiKey: String?, timeout: TimeInterval = 60) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.timeout = timeout
        self.id = "elevenlabs:\(modelId)"
    }

    public func prepare() async throws {}

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        guard let apiKey, !apiKey.isEmpty else { throw TranscriberError.http(status: 401, body: "ElevenLabs API key is missing. Add it on the Models page.") }
        let started = Date()

        var fields: [(String, String)] = [("model_id", modelId), ("tag_audio_events", "false"), ("diarize", "false")]
        if let lang = hints.language { fields.append(("language_code", lang)) }
        let form = MultipartForm()

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = form.body(fields: fields, wav: WAVEncoder.encode(samples: samples))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriberError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriberError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        struct Reply: Decodable { let text: String; let language_code: String? }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw TranscriberError.invalidResponse }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines), language: reply.language_code ?? hints.language, engine: id, latencyMs: ms)
    }
}
