import Foundation

/// POST {baseURL}/messages — Anthropic's native Messages API. The system prompt
/// is a top-level field, not a message, and `max_tokens` is required.
public struct AnthropicRefiner: Refiner {
    public static let version = "2023-06-01"

    public let id: String
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let effort: ThinkingEffort
    public let timeout: TimeInterval

    public init(baseURL: URL, model: String, apiKey: String?, effort: ThinkingEffort = .off, timeout: TimeInterval = 20) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.effort = effort
        self.timeout = timeout
        self.id = "anthropic:\(model)"
    }

    /// Dictation output is never long; this only caps runaway replies.
    static let maxTokens = 2048

    /// No `temperature`: Claude 4.7 and later reject it. Depth is controlled by
    /// `output_config.effort`, which defaults to `high` — seconds of thinking for
    /// what is a one-line cleanup.
    /// `minimal` drops every optional field, leaving only what the Messages API
    /// requires. Used to retry a 400: a provider that rejects an optional field
    /// must not cost the user their dictation.
    func payload(for request: RefineRequest, minimal: Bool = false) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": Self.maxTokens,
            "system": PromptBuilder.systemPrompt(for: request),
            "messages": [["role": "user", "content": PromptBuilder.userMessage(for: request)]],
        ]
        guard !minimal else { return payload }
        payload["output_config"] = ["effort": effort.levelName]
        if effort == .off { payload["thinking"] = ["type": "disabled"] }
        return payload
    }

    func makeRequest(_ payload: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("messages"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        if let apiKey, !apiKey.isEmpty { req.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw RefinerError.http(status: 401, body: "Anthropic API key is missing. Add it under Models ▸ Refinement.")
        }
        let started = Date()
        var (data, http) = try await send(makeRequest(payload(for: request)))
        if http.statusCode == 400 {
            (data, http) = try await send(makeRequest(payload(for: request, minimal: true)))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RefinerError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        struct Reply: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let model: String?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefinerError.invalidResponse }
        let text = PromptBuilder.sanitize(reply.content.compactMap { $0.type == "text" ? $0.text : nil }.joined())
        guard !text.isEmpty else { throw RefinerError.emptyOutput }
        return RefineResult(
            text: text, engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
            promptVersion: PromptBuilder.version, servedBy: reply.model
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
