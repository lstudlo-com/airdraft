import Foundation

/// POST {baseURL}/chat/completions. Covers LM Studio, Ollama, OpenAI, Groq,
/// OpenRouter, Gemini's OpenAI-compatible endpoint, and vLLM/llama-server.
public struct OpenAICompatibleRefiner: Refiner {
    public let id: String
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let temperature: Double
    public let timeout: TimeInterval
    public let effort: ThinkingEffort
    public let provider: LLMProviderKind
    private let session: URLSession

    public init(
        baseURL: URL,
        model: String,
        apiKey: String?,
        temperature: Double = 0.2,
        timeout: TimeInterval = 20,
        effort: ThinkingEffort = .off,
        provider: LLMProviderKind = .openAICompatible,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.timeout = timeout
        self.effort = effort
        self.provider = provider
        self.session = session
        self.id = "openai-compatible:\(baseURL.host ?? "?")/\(model)"
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let started = Date()
        var (data, http) = try await post(payload(for: request))
        if http.statusCode == 400 {
            // A provider that rejects an optional field (reasoning_effort, temperature)
            // must not cost the user the dictation: retry with the bare request.
            (data, http) = try await post(payload(for: request, minimal: true))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RefinerError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
            let model: String?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let content = reply.choices.first?.message.content else {
            throw RefinerError.invalidResponse
        }
        let text = PromptBuilder.sanitize(content)
        guard !text.isEmpty else { throw RefinerError.emptyOutput }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return RefineResult(text: text, engine: id, latencyMs: ms, promptVersion: PromptBuilder.version, servedBy: reply.model)
    }

    func payload(for request: RefineRequest, minimal: Bool = false) -> [String: Any] {
        var body: [String: Any] = [
            "model": model, "stream": false,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt(for: request)],
                ["role": "user", "content": PromptBuilder.userMessage(for: request)],
            ],
        ]
        guard !minimal else { return body }
        body["temperature"] = temperature
        if provider == .cerebras || provider == .groq {
            // These APIs do not accept local-server chat_template_kwargs.
            // Unknown models get the spec-core request and temperature only.
            let isOSS = provider == .cerebras ? model == "gpt-oss-120b"
                : ["openai/gpt-oss-20b", "openai/gpt-oss-120b"].contains(model)
            let supportsOff = provider == .cerebras
                ? ["qwen-3.8-27b", "gemma-4-31b"].contains(model)
                : model == "qwen/qwen3.8-27b"
            if isOSS || supportsOff {
                let levels: [ThinkingEffort] = isOSS ? [.low, .medium, .high] : ThinkingEffort.standard
                let effective = effort.supported(in: levels) ?? .low
                body["reasoning_effort"] = effective == .off ? "none" : effective.rawValue
                if provider == .groq {
                    if isOSS { body["include_reasoning"] = false }
                    else { body["reasoning_format"] = "hidden" }
                }
            }
        } else {
            // Preserve existing LM Studio/vLLM behaviour and the one-shot 400 fallback.
            body["reasoning_effort"] = effort == .off ? "none" : effort.rawValue
            if effort == .off { body["chat_template_kwargs"] = ["enable_thinking": false] }
        }
        return body
    }

    func makeRequest(_ payload: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    private func post(_ payload: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        let req = try makeRequest(payload)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError where error.code == .timedOut {
            throw RefinerError.timeout
        }
        guard let http = response as? HTTPURLResponse else { throw RefinerError.invalidResponse }
        return (data, http)
    }
}
