import Foundation

/// POST {baseURL}/models/{model}:generateContent — Gemini's native API. The
/// system prompt is `systemInstruction`, and thinking is switched off with a
/// zero thinking budget (models that cannot disable it answer 400, so the call
/// is retried without that field).
public struct GeminiRefiner: Refiner {
    public let id: String
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let temperature: Double
    private let session: URLSession
    var compatibility = RefinerCompatibility.shared
    public let timeout: TimeInterval
    public let effort: ThinkingEffort

    public init(baseURL: URL, model: String, apiKey: String?, temperature: Double = 0.2, timeout: TimeInterval = 20, effort: ThinkingEffort = .off, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.timeout = timeout
        self.session = session ?? ProviderTransport.shared
        self.effort = effort
        self.id = "gemini:\(model)"
    }

    /// `minimal` leaves only the fields generateContent requires, so a model that
    /// rejects an optional one (a thinking budget it cannot disable, say) still answers.
    func payload(for request: RefineRequest, thinkingDisabled: Bool, minimal: Bool = false) -> [String: Any] {
        var payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": PromptBuilder.systemPrompt(for: request)]]],
            "contents": [["role": "user", "parts": [["text": PromptBuilder.userMessage(for: request)]]]],
        ]
        guard !minimal else { return payload }
        var generationConfig: [String: Any] = ["temperature": temperature]
        if thinkingDisabled { generationConfig["thinkingConfig"] = ["thinkingBudget": 0] }
        payload["generationConfig"] = generationConfig
        return payload
    }

    func makeRequest(_ payload: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("models/\(model):generateContent"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key") }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw RefinerError.http(status: 401, body: "Gemini API key is missing. Add it under Models ▸ Refinement.")
        }
        let started = ProcessInfo.processInfo.systemUptime
        let full = payload(for: request, thinkingDisabled: effort == .off)
        let minimal = full.filter { ["systemInstruction", "contents"].contains($0.key) }
        let key = try RefinerCompatibility.Key(endpoint: baseURL, wire: "gemini-generate-content", model: model,
            options: full.filter { !["contents", "systemInstruction"].contains($0.key) }, apiKey: apiKey)
        let useMinimal = await compatibility.prefersMinimal(key)
        do {
            var (data, http) = try await send(makeRequest(useMinimal ? minimal : full))
            var negotiated = false
            if http.statusCode == 400, !useMinimal {
                (data, http) = try await send(makeRequest(minimal))
                negotiated = true
            } else if useMinimal, !(200..<300).contains(http.statusCode) {
                await compatibility.forget(key)
                if http.statusCode == 400 { (data, http) = try await send(makeRequest(full)) }
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RefinerError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
            struct Reply: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String? }
                        let parts: [Part]?
                    }
                    let content: Content?
                    let finishReason: String?
                }
                let candidates: [Candidate]?
                let modelVersion: String?
            }
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefinerError.invalidResponse }
            try CompletionReason.validate(reply.candidates?.first?.finishReason, allowed: ["STOP"])
            let parts = reply.candidates?.first?.content?.parts?.compactMap(\.text) ?? []
            let text = PromptBuilder.sanitize(parts.joined())
            guard !text.isEmpty else { throw RefinerError.emptyOutput }
            try Task.checkCancellation()
            if negotiated { await compatibility.recordSuccess(key) }
            return RefineResult(
                text: text, engine: id, latencyMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                promptVersion: PromptBuilder.version, servedBy: reply.modelVersion
            )
        } catch {
            if useMinimal { await compatibility.forget(key) }
            throw error
        }
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await HTTPDeadline.data(for: req, session: session, timeoutError: RefinerError.timeout, invalidResponse: RefinerError.invalidResponse)
    }
}
