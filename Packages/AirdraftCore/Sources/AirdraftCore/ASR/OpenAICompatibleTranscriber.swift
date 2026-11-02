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

    public init(baseURL: URL, model: String, apiKey: String?, timeout: TimeInterval = 30, id: String? = nil, requiresKey: Bool = false, session: URLSession? = nil) {
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

        let format = filtersNonSpeech ? "verbose_json" : "json"
        var fields: [(String, String)] = [("model", model), ("response_format", format)]
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

    /// AD-143: Groq's Whisper reports each segment's no-speech probability in
    /// `verbose_json`; plain `json` drops it, so silence came back as invented
    /// subtitle lines. Custom servers keep the plain shape they already accept.
    var filtersNonSpeech: Bool {
        baseURL.host == "api.groq.com" && model.lowercased().contains("whisper")
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let started = Date()
        struct Reply: Decodable {
            let text: String
            let language: String?
            let segments: [WhisperSegment]?
        }
        let reply = try await http.decode(Reply.self, from: makeRequest(samples: samples, hints: hints))
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let text = reply.segments.map { WhisperSegment.speech($0, prompt: hints.promptText) } ?? reply.text
        // verbose_json names the language ("chinese"); only a code is a usable hint.
        let language = reply.language.flatMap { $0.count <= 3 ? $0 : nil }
        return Transcript(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language ?? hints.language,
            engine: id,
            latencyMs: ms
        )
    }
}

/// One segment of a Whisper `verbose_json` reply.
struct WhisperSegment: Decodable, Equatable {
    let text: String
    let noSpeechProb: Double?
    let avgLogprob: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case noSpeechProb = "no_speech_prob"
        case avgLogprob = "avg_logprob"
    }

    /// Whisper's own skip rule (no-speech probability above 0.6 with an average
    /// log probability below -1), plus a no-speech probability above 0.8 alone:
    /// with our script prompt, silence decodes confidently into text that
    /// continues the prompt.
    var isNonSpeech: Bool {
        guard let noSpeechProb else { return false }
        if noSpeechProb > 0.8 { return true }
        return noSpeechProb > 0.6 && (avgLogprob ?? 0) < -1
    }

    /// The kept segments' text, joined as Whisper joined them. A first segment
    /// that only restates the script prompt is dropped too.
    static func speech(_ segments: [WhisperSegment], prompt: String?) -> String {
        segments.enumerated()
            .filter { !$1.isNonSpeech && !($0 == 0 && echoesPrompt($1.text, prompt: prompt)) }
            .map(\.element.text).joined()
    }

    /// "以下是繁體中文的內容。" came back as "現在是中文的內容。" on silence. An
    /// opening segment shaped like the prompt (a short "…是" lead-in, an optional
    /// script name, then the prompt's last five characters) continues the prompt,
    /// not the speech.
    static func echoesPrompt(_ text: String, prompt: String?) -> Bool {
        guard let prompt else { return false }
        func core(_ value: String) -> String {
            String(value.unicodeScalars.filter { !CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).contains($0) })
        }
        let tail = String(core(prompt).suffix(5))
        var segment = core(text)
        guard !tail.isEmpty, segment.hasSuffix(tail) else { return false }
        segment.removeLast(tail.count)
        for script in ["繁體", "繁体", "简体", "簡體"] where segment.hasSuffix(script) {
            segment.removeLast(script.count)
        }
        return segment.count <= 3 && segment.hasSuffix("是")
    }
}
