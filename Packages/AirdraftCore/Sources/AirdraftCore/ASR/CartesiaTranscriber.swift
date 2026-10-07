import Foundation

/// Cartesia's file endpoint accepts Ink-Whisper and an explicit language.
public struct CartesiaTranscriber: Transcriber {
    public let id = "cartesia:ink-whisper"
    public let apiKey: String?
    public let timeout: TimeInterval
    static let apiVersion = "2026-08-14"
    private let http: TranscriptionHTTP

    public init(apiKey: String?, timeout: TimeInterval = 180, session: URLSession = .shared) {
        self.apiKey = apiKey; self.timeout = timeout; http = TranscriptionHTTP(session: session)
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Cartesia")
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .cartesia, language: hints.languageCode ?? "auto")).language
        guard let language else { throw SpeechLanguageError.automaticUnavailable(model: "Ink-Whisper") }
        let form = MultipartForm()
        var request = URLRequest(url: URL(string: "https://api.cartesia.ai/stt")!)
        request.httpMethod = "POST"; request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Cartesia-Version")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body(fields: [("model", "ink-whisper"), ("language", language)], wav: WAVEncoder.encode(samples: samples))
        return request
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable { let type: String; let text: String; let language: String? }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        guard reply.type == "transcript" else { throw TranscriberError.invalidResponse }
        return Transcript(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines), language: reply.language ?? hints.isoLanguage,
                          engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}
