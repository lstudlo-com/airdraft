import Foundation

public struct MistralTranscriber: Transcriber {
    public let id = "mistral:voxtral-mini-latest"
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP

    public init(apiKey: String?, timeout: TimeInterval = 180, session: URLSession = .shared) {
        self.apiKey = apiKey; self.timeout = timeout; http = TranscriptionHTTP(session: session)
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Mistral")
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .mistral, language: hints.languageCode ?? "auto")).language
        var fields = [("model", "voxtral-mini-latest"), ("stream", "false")]
        if let language { fields.append(("language", language)) }
        let form = MultipartForm()
        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"; request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body(fields: fields, wav: WAVEncoder.encode(samples: samples))
        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable { let text: String; let language: String? }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        return Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines), language: reply.language ?? hints.isoLanguage,
                          engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}
