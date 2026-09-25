import XCTest
@testable import AirdraftCore

final class RefinementProviderTests: XCTestCase {
    private let request = RefineRequest(transcript: "嗯 今天下午開會", profile: RefinementProfile.defaults[0],
                                        context: .empty, family: .general, dictionary: [])

    private func refiner(_ kind: LLMProviderKind, model: String? = nil,
                         effort: ThinkingEffort = .off, session: URLSession = .shared) -> OpenAICompatibleRefiner {
        OpenAICompatibleRefiner(baseURL: URL(string: kind.defaultBaseURL)!,
                                model: model ?? kind.defaultModel, apiKey: "test-only-key",
                                effort: effort, provider: kind, session: session)
    }

    func testCloudContractsUseSeparateEndpointsKeysAndValidParameters() throws {
        for (kind, url, model, key, effort) in [
            (LLMProviderKind.cerebras, "https://api.cerebras.ai/v1/chat/completions", "qwen-3.8-27b", "llm.cerebras", "none"),
            (.groq, "https://api.groq.com/openai/v1/chat/completions", "openai/gpt-oss-20b", "llm.groq", "low"),
        ] {
            var config = LLMConfig()
            config.select(kind)
            XCTAssertTrue(kind.isCloud && kind.requiresKey)
            XCTAssertEqual(config.keyRef, key)
            XCTAssertNotNil(kind.keyConsoleURL)
            let engine = refiner(kind)
            let body = engine.payload(for: request)
            let wire = try engine.makeRequest(body)
            XCTAssertEqual(wire.url?.absoluteString, url)
            XCTAssertEqual(wire.httpMethod, "POST")
            XCTAssertEqual(wire.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-key")
            XCTAssertEqual(body["model"] as? String, model)
            XCTAssertEqual(body["reasoning_effort"] as? String, effort)
            XCTAssertNil(body["chat_template_kwargs"])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.map { $0["role"]! }, ["system", "user"])
            XCTAssertTrue(messages[0]["content"]!.contains("FIDELITY"))
            XCTAssertTrue(messages[1]["content"]!.contains("<transcription>"))
        }
    }

    func testReasoningMapsToSupportedLevelsAndKeepsReasoningOutOfText() {
        let groqOSS = refiner(.groq).payload(for: request)
        XCTAssertEqual(groqOSS["include_reasoning"] as? Bool, false)
        XCTAssertNil(groqOSS["reasoning_format"])
        let qwen = refiner(.groq, model: "qwen/qwen3.8-27b", effort: .high).payload(for: request)
        XCTAssertEqual(qwen["reasoning_effort"] as? String, "high")
        XCTAssertEqual(qwen["reasoning_format"] as? String, "hidden")
        XCTAssertNil(qwen["include_reasoning"])
        let cerebrasOSS = refiner(.cerebras, model: "gpt-oss-120b", effort: .off).payload(for: request)
        XCTAssertEqual(cerebrasOSS["reasoning_effort"] as? String, "low")
        let extended = refiner(.cerebras, effort: .max).payload(for: request)
        XCTAssertEqual(extended["reasoning_effort"] as? String, "high")
        for kind in [LLMProviderKind.cerebras, .groq] {
            let unknown = refiner(kind, model: "future-chat-model").payload(for: request)
            XCTAssertNil(unknown["reasoning_effort"])
            XCTAssertNil(unknown["chat_template_kwargs"])
        }
    }

    func testLocalThinkingControlsRemainAvailable() {
        let body = refiner(.openAICompatible).payload(for: request)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertEqual((body["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"], false)
    }

    func testProviderChoicesSurviveSwitchingAndPersistence() throws {
        var config = LLMConfig()
        config.select(.cerebras)
        config.model = "gpt-oss-120b"
        config.thinkingEffort = .medium
        config.select(.groq)
        config.model = "openai/gpt-oss-120b"
        config.thinkingEffort = .high
        config = try JSONDecoder().decode(LLMConfig.self, from: JSONEncoder().encode(config))
        config.select(.cerebras)
        XCTAssertEqual(config.model, "gpt-oss-120b")
        XCTAssertEqual(config.thinkingEffort, .medium)
        XCTAssertEqual(config.keyRef, "llm.cerebras")
        config.select(.groq)
        XCTAssertEqual(config.model, "openai/gpt-oss-120b")
        XCTAssertEqual(config.thinkingEffort, .high)
        XCTAssertEqual(config.keyRef, "llm.groq")
    }

    func testLegacyGroqPresetMigrationPreservesModelEffortAndKey() throws {
        let old = LLMConfig(baseURL: LLMProviderKind.groq.defaultBaseURL, model: "llama-3.3-70b-versatile",
                            apiKeyRef: "llm.groq", thinkingEffort: .medium)
        var migrated = try JSONDecoder().decode(LLMConfig.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(migrated.kind, .groq)
        XCTAssertEqual(migrated.model, old.model)
        XCTAssertEqual(migrated.thinkingEffort, .medium)
        XCTAssertEqual(migrated.keyRef, old.keyRef)
        XCTAssertEqual(migrated.endpoint, old.endpoint)
        migrated.select(.openAICompatible)
        XCTAssertEqual(migrated.endpoint?.host, "localhost")
        XCTAssertEqual(migrated.keyRef, "llm.lmstudio")
        XCTAssertFalse(EndpointPreset.llm.contains { $0.name == "Groq" })
    }

    func testMigrationLeavesCustomServersAndKeyReferencesAlone() throws {
        for original in [
            LLMConfig(baseURL: "https://proxy.example/v1", model: "custom", apiKeyRef: "llm.groq"),
            LLMConfig(baseURL: LLMProviderKind.groq.defaultBaseURL, model: "custom", apiKeyRef: "llm.custom"),
        ] {
            let restored = try JSONDecoder().decode(LLMConfig.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(restored, original)
        }
    }

    func testGroqModelPickerExcludesNonRefinementModels() {
        let ids = ["whisper-large-v3-turbo", "canopylabs/orpheus-v1-english", "meta-llama/llama-prompt-guard-2-22m",
                   "openai/gpt-oss-safeguard-20b", "groq/compound", "openai/gpt-oss-20b", "qwen/qwen3.8-27b", "future-chat"]
        XCTAssertEqual(ModelCatalog.refinementModels(in: ids, for: .groq), Array(ids.suffix(3)))
        XCTAssertEqual(ModelCatalog.refinementModels(in: ids, for: .openAICompatible), ids)
    }

    func test400RetriesExactlyOnceWithMinimalRequest() async throws {
        for kind in [LLMProviderKind.cerebras, .groq] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [RefinementURLProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            RefinementURLProtocol.requests = []
            RefinementURLProtocol.statuses = [400, 200]
            let result = try await refiner(kind, session: session).refine(request)
            XCTAssertEqual(result.text, "今天下午開會。")
            XCTAssertEqual(RefinementURLProtocol.requests.count, 2)
            let retry = try XCTUnwrap(RefinementURLProtocol.requests.last)
            XCTAssertEqual(Set(retry.keys), ["model", "messages", "stream"])
        }
    }

    func testAuthenticationErrorIsNotRetried() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RefinementURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        RefinementURLProtocol.requests = []
        RefinementURLProtocol.statuses = [401]
        do {
            _ = try await refiner(.cerebras, session: session).refine(request)
            XCTFail("Expected authentication error")
        } catch RefinerError.http(let status, _) { XCTAssertEqual(status, 401) }
        XCTAssertEqual(RefinementURLProtocol.requests.count, 1)
    }
}

private final class RefinementURLProtocol: URLProtocol {
    static var requests: [[String: Any]] = []
    static var statuses: [Int] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: Data
        if let data = request.httpBody { body = data }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        } else { body = Data() }
        Self.requests.append((try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:])
        let status = Self.statuses.isEmpty ? 500 : Self.statuses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let reply = status == 200 ? #"{"choices":[{"finish_reason":"stop","message":{"content":"今天下午開會。","reasoning":"not the answer"}}]}"# : #"{"error":{"message":"test rejection"}}"#
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
