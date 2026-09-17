import Foundation

/// GET {baseURL}/models. Works for LM Studio, Ollama, OpenAI, Groq,
/// OpenRouter, Gemini's OpenAI-compatible endpoint, and vLLM.
public enum ModelCatalog {
    /// Models the configured refinement provider serves, in its own API shape.
    public static func refinementModels(for config: LLMConfig, timeout: TimeInterval = 10) async throws -> [String] {
        if let tool = config.kind.cliTool {
            guard let executable = config.cliExecutable else { throw RefinerError.invalidResponse }
            return try await CLIModelCatalog.shared.models(tool: tool, executable: executable, refresh: true, timeout: timeout).map(\.id)
        }
        guard let base = config.endpoint else { return [] }
        let key = Keychain.get(config.keyRef)
        switch config.kind.wire {
        case .openAIChat:
            return try await fetch(baseURL: base, apiKey: key, timeout: timeout)
        case .anthropicMessages:
            var req = URLRequest(url: base.appendingPathComponent("models"))
            req.timeoutInterval = timeout
            req.setValue(AnthropicRefiner.version, forHTTPHeaderField: "anthropic-version")
            if let key, !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-api-key") }
            struct Reply: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            return try await decode(req, as: Reply.self).data.map(\.id)
        case .cli:
            return config.kind.cliTool?.modelSuggestions ?? []
        case .geminiGenerateContent:
            var req = URLRequest(url: base.appendingPathComponent("models"))
            req.timeoutInterval = timeout
            if let key, !key.isEmpty { req.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
            struct Reply: Decodable {
                struct Model: Decodable { let name: String; let supportedGenerationMethods: [String]? }
                let models: [Model]
            }
            return try await decode(req, as: Reply.self).models
                .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? true }
                .map { $0.name.replacingOccurrences(of: "models/", with: "") }
                .sorted()
        }
    }

    public static func fetch(baseURL: URL, apiKey: String?, timeout: TimeInterval = 8) async throws -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.timeoutInterval = timeout
        if let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        struct Reply: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return try await decode(req, as: Reply.self).data.map(\.id).sorted()
    }

    private static func decode<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RefinerError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Model ids that look like speech models, for the ASR picker.
    public static func speechModels(in ids: [String]) -> [String] {
        let hits = ids.filter { id in
            let l = id.lowercased()
            return l.contains("transcribe") || l.contains("whisper") || l.contains("voxtral") || l.contains("asr") || l.contains("speech")
        }
        return hits.isEmpty ? ids : hits
    }
}
