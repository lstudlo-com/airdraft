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

    public init(
        baseURL: URL,
        model: String,
        apiKey: String?,
        temperature: Double = 0.2,
        timeout: TimeInterval = 20,
        effort: ThinkingEffort = .off
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.timeout = timeout
        self.effort = effort
        self.id = "openai-compatible:\(baseURL.host ?? "?")/\(model)"
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let started = Date()
        let system = PromptBuilder.systemPrompt(for: request)
        let user = PromptBuilder.userMessage(for: request)

        let minimalPayload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let basePayload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        // Reasoning models spend seconds "thinking" before a one-line cleanup.
        // These extras switch that off on LM Studio (Gemma 4: reasoning_effort),
        // vLLM / llama-server (Qwen3: chat_template_kwargs). Providers that
        // reject unknown parameters answer 400, so we retry once without them.
        var extras: [String: Any] = ["reasoning_effort": effort == .off ? "none" : effort.rawValue]
        if effort == .off {
            extras["chat_template_kwargs"] = ["enable_thinking": false]
        }


        var (data, http) = try await post(basePayload.merging(extras) { $1 })
        if http.statusCode == 400 {
            // A provider that rejects an optional field (reasoning_effort, temperature)
            // must not cost the user the dictation: retry with the bare request.
            (data, http) = try await post(minimalPayload)
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

    private func post(_ payload: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let error as URLError where error.code == .timedOut {
            throw RefinerError.timeout
        }
        guard let http = response as? HTTPURLResponse else { throw RefinerError.invalidResponse }
        return (data, http)
    }
}
