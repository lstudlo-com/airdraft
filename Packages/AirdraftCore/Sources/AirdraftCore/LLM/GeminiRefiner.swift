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
    public let timeout: TimeInterval
    public let effort: ThinkingEffort

    public init(baseURL: URL, model: String, apiKey: String?, temperature: Double = 0.2, timeout: TimeInterval = 20, effort: ThinkingEffort = .off) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.timeout = timeout
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
        let started = Date()
        var (data, http) = try await send(makeRequest(payload(for: request, thinkingDisabled: effort == .off)))
        if http.statusCode == 400 {
            (data, http) = try await send(makeRequest(payload(for: request, thinkingDisabled: false, minimal: true)))
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
            }
            let candidates: [Candidate]?
            let modelVersion: String?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefinerError.invalidResponse }
        let parts = reply.candidates?.first?.content?.parts?.compactMap(\.text) ?? []
        let text = PromptBuilder.sanitize(parts.joined())
        guard !text.isEmpty else { throw RefinerError.emptyOutput }
        return RefineResult(
            text: text, engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
            promptVersion: PromptBuilder.version, servedBy: reply.modelVersion
        )
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw RefinerError.invalidResponse }
            return (data, http)
        } catch let error as URLError where error.code == .timedOut {
            throw RefinerError.timeout
        }
    }
}
