import Foundation

/// Nova-3 pre-recorded recognition: raw WAV body, query options, Token auth.
public struct DeepgramTranscriber: Transcriber {
    public var id: String { "deepgram:\(model)" }
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP

    public init(model: String = "nova-3", apiKey: String?, timeout: TimeInterval = 60, session: URLSession? = nil) {
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.http = TranscriptionHTTP(session: session)
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        try preparedRequest(samples: samples, hints: hints).request
    }

    private func preparedRequest(samples: [Float], hints: TranscriptionHints) throws -> (request: URLRequest, language: String?) {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let language = try Self.requestLanguage(model: model, hints: hints)
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Deepgram")
        var url = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        let multilingual = model == "nova-3-multilingual"
        let whisper = model == "whisper-large"
        var query = [URLQueryItem(name: "model", value: multilingual ? "nova-3" : model)]
        if !whisper { query.append(URLQueryItem(name: "smart_format", value: "true")) }
        if let language {
            query.append(URLQueryItem(name: "language", value: language))
        } else {
            // Dominant-language detection supports Mandarin. language=multi has
            // a different language set and price and must not be substituted.
            query.append(URLQueryItem(name: "detect_language", value: "true"))
        }
        url.queryItems = query
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = WAVEncoder.encode(samples: samples)
        return (request, language == "multi" ? nil : language)
    }

    static func requestLanguage(model: String, hints: TranscriptionHints) throws -> String? {
        let resolved = try SpeechLanguagePolicy.resolve(ASRConfig(
            kind: .deepgram, model: model, language: hints.language ?? ""
        ))
        if model == "nova-3-multilingual" { return "multi" }
        guard let language = resolved.language else { return nil }
        // Deepgram identifies Cantonese separately from Mandarin.
        if language == "yue" { return "zh-HK" }
        if language == "zh", model != "whisper-large", hints.chineseScript == .traditional { return "zh-TW" }
        return language
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable {
            struct Results: Decodable {
                struct Channel: Decodable {
                    struct Alternative: Decodable { let transcript: String }
                    let alternatives: [Alternative]
                    let detected_language: String?
                }
                let channels: [Channel]
            }
            let results: Results
        }
        let prepared = try preparedRequest(samples: samples, hints: hints)
        let reply = try await http.decode(Reply.self, from: prepared.request)
        guard let channel = reply.results.channels.first, let text = channel.alternatives.first?.transcript else {
            throw TranscriberError.invalidResponse
        }
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                          language: channel.detected_language ?? prepared.language,
                          engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}
