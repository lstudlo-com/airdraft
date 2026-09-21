import XCTest
@testable import AirdraftCore

/// Each provider speaks its own API: these lock the request shapes down, since
/// a wrong field name only shows up as a 400 at dictation time.
final class RefinerWireTests: XCTestCase {
    private func sampleRequest() -> RefineRequest {
        RefineRequest(
            transcript: "嗯 這是測試",
            profile: RefinementProfile.defaults[0],
            context: .empty,
            family: .general,
            dictionary: []
        )
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testAnthropicMessagesShape() throws {
        let refiner = AnthropicRefiner(baseURL: URL(string: "https://api.anthropic.com/v1")!, model: "claude-haiku-4-5-20251001", apiKey: "sk-test")
        let request = try refiner.makeRequest(refiner.payload(for: sampleRequest()))

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), AnthropicRefiner.version)

        let body = try json(request)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(body["max_tokens"] as? Int, AnthropicRefiner.maxTokens)
        // The system prompt is a top-level field here, never a message.
        XCTAssertTrue((body["system"] as? String ?? "").contains("FIDELITY"))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertTrue((messages[0]["content"] as? String ?? "").contains("<transcription>"))
    }

    func testGeminiGenerateContentShape() throws {
        let refiner = GeminiRefiner(baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!, model: "gemini-2.5-flash", apiKey: "key-test")
        let request = try refiner.makeRequest(refiner.payload(for: sampleRequest(), thinkingDisabled: true))

        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "key-test")

        let body = try json(request)
        let system = try XCTUnwrap(body["systemInstruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(system["parts"] as? [[String: Any]])
        XCTAssertTrue((systemParts[0]["text"] as? String ?? "").contains("FIDELITY"))
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents[0]["role"] as? String, "user")
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual((generation["thinkingConfig"] as? [String: Any])?["thinkingBudget"] as? Int, 0)

        // Models that cannot disable thinking answer 400; the retry drops the field.
        let retry = try refiner.makeRequest(refiner.payload(for: sampleRequest(), thinkingDisabled: false))
        let retryGeneration = try XCTUnwrap(try json(retry)["generationConfig"] as? [String: Any])
        XCTAssertNil(retryGeneration["thinkingConfig"])
    }

    @MainActor
    func testFactoryPicksTheProviderWire() async {
        let factory = EngineFactory(status: EngineStatus())
        var config = LLMConfig()
        for (kind, expected) in [
            (LLMProviderKind.openAICompatible, "OpenAICompatibleRefiner"),
            (.openAI, "OpenAICompatibleRefiner"),
            (.openRouter, "OpenAICompatibleRefiner"),
            (.cerebras, "OpenAICompatibleRefiner"),
            (.groq, "OpenAICompatibleRefiner"),
            (.anthropic, "AnthropicRefiner"),
            (.gemini, "GeminiRefiner"),
        ] {
            config.select(kind)
            let refiner = await factory.refiner(for: config)
            XCTAssertEqual(String(describing: Swift.type(of: refiner!)), expected, "\(kind)")
            if let chat = refiner as? OpenAICompatibleRefiner {
                XCTAssertEqual(chat.provider, kind)
                XCTAssertEqual(chat.baseURL, config.endpoint)
            }
        }
        config.select(.none)
        let off = await factory.refiner(for: config)
        XCTAssertNil(off)
    }

    func testSwitchingProvidersKeepsEachModelChoice() {
        var config = LLMConfig()
        config.model = "google/gemma-4-26b-a4b-qat"
        config.select(.anthropic)
        XCTAssertEqual(config.model, LLMProviderKind.anthropic.defaultModel)
        config.model = "claude-opus-5"
        config.select(.openAICompatible)
        XCTAssertEqual(config.model, "google/gemma-4-26b-a4b-qat")
        config.select(.anthropic)
        XCTAssertEqual(config.model, "claude-opus-5")
        // Cloud providers use their own endpoint, the editable one stays local.
        XCTAssertEqual(config.endpoint?.host, "api.anthropic.com")
        XCTAssertEqual(config.keyRef, "llm.anthropic")
    }
}

/// The CLI providers spend the user's subscription, so the flags that keep a call
/// cheap and side-effect free are part of the contract, not an implementation detail.
final class CLIRefinerTests: XCTestCase {
    private let out = URL(fileURLWithPath: "/tmp/last-message.txt")

    func testClaudeCodeRunsWithoutToolsOrUserConfig() {
        let refiner = CLIRefiner(tool: .claudeCode, executable: "/usr/local/bin/claude", model: "sonnet")
        let args = refiner.arguments(outputFile: out, systemPrompt: "SYSTEM")

        XCTAssertEqual(args.first, "-p")
        XCTAssertEqual(args[args.firstIndex(of: "--system-prompt")! + 1], "SYSTEM")
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "sonnet")
        // Without an empty tool set the CLI ships ~15k tokens of schemas per call.
        XCTAssertEqual(args[args.firstIndex(of: "--tools")! + 1], "")
        for flag in ["--restricted", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence", "--safe-mode"] {
            XCTAssertTrue(args.contains(flag), flag)
        }
        XCTAssertEqual(args[args.firstIndex(of: "--output-format")! + 1], "json")
    }

    func testCodexRunsOneShotInATemporaryDirectory() {
        let refiner = CLIRefiner(tool: .codex, executable: "/usr/local/bin/codex", model: "gpt-6-astra")
        let args = refiner.arguments(outputFile: out, systemPrompt: "SYSTEM")

        XCTAssertEqual(args.first, "exec")
        XCTAssertEqual(args.last, "-")  // prompt arrives on stdin
        XCTAssertEqual(args[args.firstIndex(of: "-o")! + 1], out.path)
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "gpt-6-astra")
        for flag in ["--ephemeral", "--ignore-user-config", "--skip-git-repo-check"] {
            XCTAssertTrue(args.contains(flag), flag)
        }
        XCTAssertEqual(args[args.firstIndex(of: "--sandbox")! + 1], "read-only")
    }

    func testWarmStartSwitchesClaudeCodeToStreamingIO() {
        let refiner = CLIRefiner(tool: .claudeCode, executable: "/usr/local/bin/claude", model: "sonnet", effort: .low)
        let args = refiner.warmArguments(systemPrompt: "SYSTEM")
        // The process is started before the transcript exists, so it has to read stdin
        // as a stream and answer as a stream.
        XCTAssertEqual(args[args.firstIndex(of: "--input-format")! + 1], "stream-json")
        XCTAssertEqual(args[args.firstIndex(of: "--output-format")! + 1], "stream-json")
        XCTAssertTrue(args.contains("--verbose"))  // required with streaming output
        XCTAssertEqual(args[args.firstIndex(of: "--effort")! + 1], "low")
        XCTAssertTrue(refiner.supportsWarmStart)
        XCTAssertFalse(CLIRefiner(tool: .codex, executable: "/usr/local/bin/codex", model: "").supportsWarmStart)
    }

    func testEffortReachesEachProvider() {
        let claude = CLIRefiner(tool: .claudeCode, executable: "/bin/true", model: "", effort: .medium)
        XCTAssertEqual(claude.arguments(outputFile: out, systemPrompt: "S")[claude.arguments(outputFile: out, systemPrompt: "S").firstIndex(of: "--effort")! + 1], "medium")
        let codex = CLIRefiner(tool: .codex, executable: "/bin/true", model: "", effort: .off)
        XCTAssertTrue(codex.arguments(outputFile: out, systemPrompt: "S").contains("model_reasoning_effort=\"low\""))

        // Claude 4.7+ reject `temperature`; depth is set through output_config.effort.
        let anthropic = AnthropicRefiner(baseURL: URL(string: "https://api.anthropic.com/v1")!, model: "claude-sonnet-5", apiKey: "k", effort: .low)
        let request = RefineRequest(transcript: "測試", profile: RefinementProfile.defaults[0], context: .empty, family: .general, dictionary: [])
        let payload = anthropic.payload(for: request)
        XCTAssertNil(payload["temperature"])
        XCTAssertEqual((payload["output_config"] as? [String: Any])?["effort"] as? String, "low")
        // The 400 retry falls back to the bare spec body.
        let minimal = anthropic.payload(for: request, minimal: true)
        XCTAssertNil(minimal["output_config"])
        XCTAssertNil(minimal["thinking"])
        XCTAssertNotNil(minimal["messages"])
    }

    func testBothCLIsReceiveOnlyTheTranscriptOnStdin() {
        let request = RefineRequest(transcript: "測試", profile: RefinementProfile.defaults[0], context: .empty, family: .general, dictionary: [])
        let claude = CLIRefiner(tool: .claudeCode, executable: "/bin/true", model: "")
        let codex = CLIRefiner(tool: .codex, executable: "/bin/true", model: "")
        XCTAssertFalse(claude.input(for: request).contains("FIDELITY"))
        XCTAssertFalse(codex.input(for: request).contains("FIDELITY"))
        XCTAssertEqual(codex.input(for: request), PromptBuilder.userMessage(for: request))
        // An empty model means "whatever the CLI is set to", so no --model flag.
        XCTAssertFalse(claude.arguments(outputFile: out, systemPrompt: "S").contains("--model"))
    }
}
