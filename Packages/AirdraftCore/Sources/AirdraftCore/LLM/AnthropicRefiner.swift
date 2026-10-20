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
    private let session: URLSession
    var compatibility = RefinerCompatibility.shared
    public let timeout: TimeInterval

    public init(baseURL: URL, model: String, apiKey: String?, effort: ThinkingEffort = .off, timeout: TimeInterval = 20, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.effort = effort
        self.timeout = timeout
        self.session = session ?? ProviderTransport.shared
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
            throw RefinerError.http(status: 401, body: String(localized: "Anthropic API key is missing. Add it under Models ▸ Refinement.", bundle: .module))
        }
        let started = ProcessInfo.processInfo.systemUptime
        let full = payload(for: request)
        let minimal = full.filter { ["model", "max_tokens", "system", "messages"].contains($0.key) }
        let key = try RefinerCompatibility.Key(endpoint: baseURL, wire: "anthropic-messages", model: model,
            options: full.filter { !["messages", "system"].contains($0.key) }, apiKey: apiKey)
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
                struct Block: Decodable { let type: String; let text: String? }
                let content: [Block]
                let model: String?
                let stop_reason: String?
            }
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefinerError.invalidResponse }
            try CompletionReason.validate(reply.stop_reason, allowed: ["end_turn", "stop_sequence"])
            let text = PromptBuilder.sanitize(reply.content.compactMap { $0.type == "text" ? $0.text : nil }.joined())
            guard !text.isEmpty else { throw RefinerError.emptyOutput }
            try Task.checkCancellation()
            if negotiated { await compatibility.recordSuccess(key) }
            return RefineResult(
                text: text, engine: id, latencyMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                promptVersion: PromptBuilder.version, servedBy: reply.model
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
