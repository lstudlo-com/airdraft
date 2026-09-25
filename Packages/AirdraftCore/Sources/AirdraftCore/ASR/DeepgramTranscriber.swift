import Foundation

/// Nova-3 pre-recorded recognition: raw WAV body, query options, Token auth.
public struct DeepgramTranscriber: Transcriber {
    public var id: String { "deepgram:\(model)" }
    public let model: String
    public let apiKey: String?
    public let timeout: TimeInterval
    private let http: TranscriptionHTTP

    public init(model: String = "nova-3", apiKey: String?, timeout: TimeInterval = 60, session: URLSession = .shared) {
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.http = TranscriptionHTTP(session: session)
    }

    public func prepare() async throws {}

    func makeRequest(samples: [Float], hints: TranscriptionHints) throws -> URLRequest {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let key = try TranscriptionHTTP.requireKey(apiKey, provider: "Deepgram")
        var url = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        let multilingual = model == "nova-3-multilingual"
        let whisper = model == "whisper-large"
        var query = [URLQueryItem(name: "model", value: multilingual ? "nova-3" : model)]
        if !whisper { query.append(URLQueryItem(name: "smart_format", value: "true")) }
        if multilingual {
            query.append(URLQueryItem(name: "language", value: "multi"))
        } else if let language = hints.languageCode {
            let code = whisper ? hints.isoLanguage! : (hints.isoLanguage == "zh" && hints.chineseScript == .traditional ? "zh-TW" : language)
            query.append(URLQueryItem(name: "language", value: code))
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
        return request
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
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        guard let channel = reply.results.channels.first, let text = channel.alternatives.first?.transcript else {
            throw TranscriberError.invalidResponse
        }
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                          language: channel.detected_language ?? hints.languageCode,
                          engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}
