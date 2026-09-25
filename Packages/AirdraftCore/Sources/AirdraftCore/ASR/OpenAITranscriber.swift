import Foundation

/// GPT-Transcribe uses languages[] and keywords[], unlike the legacy Whisper wire.
public struct OpenAITranscriber: Transcriber {
    public var id: String { "openAI:\(model)" }
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP

    public init(model: String = "gpt-transcribe", apiKey: String?, timeout: TimeInterval = 60, session: URLSession = .shared) {
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.http = TranscriptionHTTP(session: session)
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "OpenAI")
        var fields = [("model", model), ("response_format", "json")]
        if model == "gpt-transcribe" {
            if let language = hints.isoLanguage { fields.append(("languages[]", language)) }
            // These characters cause the entire request to be rejected by OpenAI.
            let forbidden = CharacterSet(charactersIn: "<>\r\n")
            for term in hints.vocabularyTerms.filter({ $0.rangeOfCharacter(from: forbidden) == nil }).prefix(100) {
                fields.append(("keywords[]", String(term.prefix(100))))
            }
        } else {
            if let language = hints.isoLanguage { fields.append(("language", language)) }
            if let prompt = hints.promptText { fields.append(("prompt", prompt)) }
        }
        let form = MultipartForm()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body(fields: fields, wav: WAVEncoder.encode(samples: samples))
        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable {
            struct Language: Decodable { let code: String }
            let text: String
            let languages: [Language]?
        }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        return Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines),
                          language: reply.languages?.first?.code ?? hints.isoLanguage,
                          engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}
