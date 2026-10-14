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
    public let openRouterRouting: OpenRouterRouting
    private let session: URLSession
    var compatibility = RefinerCompatibility.shared

    public init(
        baseURL: URL,
        model: String,
        apiKey: String?,
        temperature: Double = 0.2,
        timeout: TimeInterval = 20,
        effort: ThinkingEffort = .off,
        provider: LLMProviderKind = .openAICompatible,
        openRouterRouting: OpenRouterRouting = OpenRouterRouting(),
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.timeout = timeout
        self.effort = effort
        self.provider = provider
        self.openRouterRouting = openRouterRouting
        self.session = session ?? ProviderTransport.shared
        self.id = "openai-compatible:\(baseURL.host ?? "?")/\(model)"
    }

    /// LM Studio reuses the unchanged prompt prefix on the real request. Compute
    /// it while recording with one discarded token, preserving all inference
    /// options and the eventual full request's output budget.
    public func prewarmPrompt(_ request: RefineRequest, backend: RefinementPreparationBackend) async throws {
        try Task.checkCancellation()
        let host = (baseURL.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard backend == .lmStudio, provider == .openAICompatible, request.transcript.isEmpty,
              ["localhost", "127.0.0.1", "::1"].contains(host) else { return }
        var warmPayload = payload(for: request)
        warmPayload["max_tokens"] = 1
        do {
            _ = try await post(warmPayload)
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // Speculative preparation is optional. Unsupported requests, network
            // failures and timeouts cannot prevent normal refinement.
        }
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let started = ProcessInfo.processInfo.systemUptime
        let full = payload(for: request)
        let minimal = full.filter { ["model", "stream", "messages", "provider"].contains($0.key) }
        let key = try RefinerCompatibility.Key(endpoint: baseURL, wire: "openai-chat:\(provider.rawValue)", model: model,
            options: full.filter { $0.key != "messages" }, apiKey: apiKey)
        let useMinimal = await compatibility.prefersMinimal(key)
        do {
            var (data, http) = try await post(useMinimal ? minimal : full)
            var negotiated = false
            if http.statusCode == 400, !useMinimal {
                // A provider that rejects an optional field (reasoning_effort, temperature)
                // must not cost the user the dictation: retry with the bare request.
                (data, http) = try await post(minimal)
                negotiated = true
            } else if useMinimal, !(200..<300).contains(http.statusCode) {
                await compatibility.forget(key)
                if http.statusCode == 400 { (data, http) = try await post(full) }
            }
            guard (200..<300).contains(http.statusCode) else {
                throw RefinerError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }

            struct Reply: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String? }
                    let message: Message
                    let finish_reason: String?
                }
                struct RoutingMetadata: Decodable {
                    struct Endpoints: Decodable {
                        struct Endpoint: Decodable {
                            let provider: String?
                            let selected: Bool?
                        }
                        let available: [Endpoint]?
                    }
                    let endpoints: Endpoints?

                    var selectedProvider: String? {
                        endpoints?.available?.first { $0.selected == true }?.provider
                    }
                }
                let choices: [Choice]
                let model: String?
                let openrouterMetadata: RoutingMetadata?

                enum CodingKeys: String, CodingKey {
                    case choices, model
                    case openrouterMetadata = "openrouter_metadata"
                }
            }
            guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
                  let content = reply.choices.first?.message.content else {
                throw RefinerError.invalidResponse
            }
            try CompletionReason.validate(reply.choices.first?.finish_reason, allowed: ["stop"])
            let text = PromptBuilder.sanitize(content)
            guard !text.isEmpty else { throw RefinerError.emptyOutput }
            try Task.checkCancellation()
            if negotiated { await compatibility.recordSuccess(key) }
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            let servedBy = provider == .openRouter ? reply.openrouterMetadata?.selectedProvider : reply.model
            return RefineResult(text: text, engine: id, latencyMs: ms, promptVersion: PromptBuilder.version, servedBy: servedBy)
        } catch {
            if useMinimal { await compatibility.forget(key) }
            throw error
        }
    }

    func payload(for request: RefineRequest, minimal: Bool = false) -> [String: Any] {
        var body: [String: Any] = [
            "model": model, "stream": false,
            "messages": [
                ["role": "system", "content": PromptBuilder.systemPrompt(for: request)],
                ["role": "user", "content": PromptBuilder.userMessage(for: request)],
            ],
        ]
        // Provider restrictions are user intent, not optional compatibility fields.
        // Keep them on the 400 retry so it cannot silently change hosts.
        if provider == .openRouter { body["provider"] = openRouterRouting.preferences }
        guard !minimal else { return body }
        body["temperature"] = temperature
        if provider == .openRouter {
            body["reasoning"] = effort == .off
                ? ["enabled": false]
                : ["effort": effort.rawValue, "exclude": true]
        } else if provider == .cerebras || provider == .groq {
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
        if provider == .openRouter {
            req.setValue("enabled", forHTTPHeaderField: "X-OpenRouter-Metadata")
        }
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    private func post(_ payload: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        try await HTTPDeadline.data(for: makeRequest(payload), session: session, timeoutError: RefinerError.timeout, invalidResponse: RefinerError.invalidResponse)
    }
}
