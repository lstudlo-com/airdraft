import Foundation
import XCTest
@testable import AirdraftCore

final class CLIModelCatalogTests: XCTestCase {
    func testCodexModelsKeepAllEffortsAndHiddenEntries() throws {
        let models = try CLIModelCatalog.parseCodex([
            "data": [
                ["model": "future-model", "displayName": "Future model", "isDefault": true,
                 "supportedReasoningEfforts": ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].map { ["reasoningEffort": $0] }],
                ["model": "hidden-model", "hidden": true, "supportedReasoningEfforts": []],
            ],
        ])
        XCTAssertEqual(models.map(\.id), ["future-model", "hidden-model"])
        XCTAssertEqual(models[0].efforts, ThinkingEffort.allCases)
        XCTAssertFalse(models[0].dictationEfforts!.contains(.ultra))
        XCTAssertTrue(models[1].hidden)
        XCTAssertEqual(CLIModelInfo.selected("", in: models)?.id, "future-model")
    }

    func testClaudeIncludesResolvedIDsAndDistinguishesUnsupportedFromUnknownEffort() throws {
        let models = try CLIModelCatalog.parseClaude([
            "models": [
                ["value": "default", "resolvedModel": "claude-opus-5", "supportsEffort": true,
                 "supportedEffortLevels": ["low", "medium", "high", "xhigh", "max"]],
                ["value": "opus", "resolvedModel": "claude-opus-5", "supportsEffort": true,
                 "supportedEffortLevels": ["low", "medium", "high", "xhigh", "max"]],
                ["value": "haiku", "resolvedModel": "claude-haiku-4-5"],
                ["value": "older-cli-model"],
            ],
        ])
        XCTAssertEqual(models.map(\.id), ["default", "claude-opus-5", "opus", "haiku", "claude-haiku-4-5", "older-cli-model"])
        XCTAssertEqual(models[1].efforts, [.low, .medium, .high, .xhigh, .max])
        XCTAssertEqual(models[3].efforts, [])
        XCTAssertNil(models.last?.efforts)
    }

    func testCodexDiscoveryInitializesAndFollowsEveryPageWithoutInference() async throws {
        let script = try fakeCLI("""
        IFS= read -r line
        case "$line" in *'"method":"initialize"'*) ;; *) exit 2;; esac
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r line
        case "$line" in *'"method":"initialized"'*) ;; *) exit 3;; esac
        IFS= read -r line
        case "$line" in *'"includeHidden":true'*) ;; *) exit 4;; esac
        printf '%s\n' '{"method":"notification"}' '{"id":2,"result":{"data":[{"model":"first"}],"nextCursor":"page-two"}}'
        IFS= read -r line
        case "$line" in *'"cursor":"page-two"'*) ;; *) exit 5;; esac
        printf '%s\n' '{"id":3,"result":{"data":[{"model":"second","hidden":true}],"nextCursor":null}}'
        """)
        defer { try? FileManager.default.removeItem(at: script) }
        let models = try await CLIModelCatalog.discover(tool: .codex, executable: script.path, timeout: 2)
        XCTAssertEqual(models.map(\.id), ["first", "second"])
    }

    func testClaudeDiscoveryUsesControlRequestWithoutUserPrompt() async throws {
        let script = try fakeCLI("""
        IFS= read -r line
        case "$line" in *'"type":"control_request"'* ) ;; *) exit 2;; esac
        case "$line" in *'"subtype":"initialize"'* ) ;; *) exit 3;; esac
        printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"models","response":{"models":[{"value":"fable","supportsEffort":true,"supportedEffortLevels":["low","max"]}]}}}'
        """)
        defer { try? FileManager.default.removeItem(at: script) }
        let models = try await CLIModelCatalog.discover(tool: .claudeCode, executable: script.path, timeout: 2)
        XCTAssertEqual(models.first?.efforts, [.low, .max])
    }

    func testSilentCLIHasBoundedTimeout() async throws {
        let script = try fakeCLI("exec /bin/sleep 10")
        defer { try? FileManager.default.removeItem(at: script) }
        let started = Date()
        do {
            _ = try await CLIModelCatalog.discover(tool: .claudeCode, executable: script.path, timeout: 0.1)
            XCTFail("A silent CLI must time out")
        } catch RefinerError.timeout {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testCancelledDiscoveryStopsWaiting() async throws {
        let script = try fakeCLI("exec /bin/sleep 10")
        defer { try? FileManager.default.removeItem(at: script) }
        let task = Task { try await CLIModelCatalog.discover(tool: .codex, executable: script.path, timeout: 10) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled discovery must stop")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testMalformedAndFailedRepliesDoNotProduceAFalseSuccess() async throws {
        for reply in ["not json", #"{"id":1,"error":{"message":"do not display account data"}}"#] {
            let script = try fakeCLI("IFS= read -r line\nprintf '%s\\n' '\(reply)'")
            defer { try? FileManager.default.removeItem(at: script) }
            do {
                _ = try await CLIModelCatalog.discover(tool: .codex, executable: script.path, timeout: 1)
                XCTFail("Invalid catalogue must fail")
            } catch {}
        }
    }

    private func fakeCLI(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-fake-cli-\(UUID().uuidString)")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}

final class CLIEffortAndIsolationTests: XCTestCase {
    private let out = URL(fileURLWithPath: "/tmp/last-message.txt")

    func testEffortReachesBothColdAndWarmClaudeSessions() {
        for effort in [ThinkingEffort.low, .medium, .high, .xhigh, .max] {
            let refiner = CLIRefiner(tool: .claudeCode, executable: "/bin/true", model: "custom-model", effort: effort)
            for args in [refiner.arguments(outputFile: out, systemPrompt: "SYSTEM"), refiner.warmArguments(systemPrompt: "SYSTEM")] {
                XCTAssertEqual(args[args.firstIndex(of: "--effort")! + 1], effort.rawValue)
                XCTAssertTrue(args.contains("--safe-mode"))
                XCTAssertFalse(args.contains("--bare"))
            }
        }
    }

    func testCodexEffortsUseNativeValuesWithoutEnablingUltraOrchestration() {
        for effort in ThinkingEffort.allCases {
            let refiner = CLIRefiner(tool: .codex, executable: "/bin/true", model: "future-model", effort: effort, supportedEfforts: ThinkingEffort.allCases)
            XCTAssertTrue(refiner.arguments(outputFile: out, systemPrompt: "S")
                .contains("model_reasoning_effort=\"\(effort == .off ? "none" : effort == .ultra ? "max" : effort.rawValue)\""))
        }
    }

    func testUnsupportedEffortUsesNearestSupportedLevelAndHaikuOmitsFlag() {
        XCTAssertEqual(ThinkingEffort.off.supported(in: [.low, .medium, .high]), .low)
        XCTAssertEqual(ThinkingEffort.ultra.supported(in: [.low, .medium, .high, .xhigh]), .xhigh)
        XCTAssertEqual(ThinkingEffort.xhigh.supported(in: [.low, .high, .max]), .high)
        let refiner = CLIRefiner(tool: .claudeCode, executable: "/bin/true", model: "haiku", effort: .max, supportedEfforts: [])
        XCTAssertFalse(refiner.arguments(outputFile: out, systemPrompt: "S").contains("--effort"))
        XCTAssertFalse(refiner.warmArguments(systemPrompt: "S").contains("--effort"))
    }

    func testWarmPoolKeyChangesWhenEffectiveEffortChanges() {
        let low = CLIRefiner(tool: .claudeCode, executable: "/bin/true", model: "sonnet", effort: .low)
        let max = CLIRefiner(tool: .claudeCode, executable: "/bin/true", model: "sonnet", effort: .max)
        XCTAssertNotEqual(low.warmKey(systemPrompt: "S"), max.warmKey(systemPrompt: "S"))
    }

    func testProviderSwitchAndSettingsRoundTripKeepCLIChoices() throws {
        var config = LLMConfig(kind: .codex, model: "", thinkingEffort: .ultra)
        config.select(.claudeCode)
        XCTAssertEqual(config.thinkingEffort, .off)
        config.model = "claude-fable-5-1[1m]"
        config.thinkingEffort = .max
        config.select(.openAI)
        XCTAssertEqual(config.thinkingEffort, .off)
        config = try JSONDecoder().decode(LLMConfig.self, from: JSONEncoder().encode(config))
        config.select(.codex)
        XCTAssertEqual(config.model, "")
        XCTAssertEqual(config.thinkingEffort, .ultra)
        config.select(.claudeCode)
        XCTAssertEqual(config.model, "claude-fable-5-1[1m]")
        XCTAssertEqual(config.thinkingEffort, .max)
        let old = try JSONDecoder().decode(LLMConfig.self, from: Data(#"{"kind":"codex","model":"old-model","disableThinking":true}"#.utf8))
        XCTAssertEqual(old.thinkingEffort, .off)
        XCTAssertEqual(old.effortByProvider, [:])
    }

    func testCodexReplacesCodingInstructionsAndDisablesToolsForArbitraryModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let out = directory.appendingPathComponent("result.txt")
        let refiner = CLIRefiner(tool: .codex, executable: "/bin/true", model: "future-model", effort: .max)
        try refiner.prepareCodexFiles(outputFile: out, systemPrompt: "ONLY THE DICTATION RULES")
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("instructions.txt")), "ONLY THE DICTATION RULES")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("model.json"))) as? [String: Any])
        let model = try XCTUnwrap((catalog["models"] as? [[String: Any]])?.first)
        XCTAssertEqual(model["slug"] as? String, "future-model")
        XCTAssertEqual(model["tool_mode"] as? String, "direct")
        XCTAssertEqual(model["shell_type"] as? String, "disabled")
        XCTAssertEqual(model["base_instructions"] as? String, "ONLY THE DICTATION RULES")
        XCTAssertTrue(model["multi_agent_version"] is NSNull)
        let args = refiner.arguments(outputFile: out, systemPrompt: "ONLY THE DICTATION RULES")
        XCTAssertTrue(args.contains("--ignore-user-config"))
        XCTAssertTrue(args.contains("skills.include_instructions=false"))
        XCTAssertTrue(args.contains("features.plugins=false"))
        XCTAssertTrue(args.contains("features.hooks=false"))
        XCTAssertTrue(args.contains { $0.hasPrefix("model_instructions_file=") })
        XCTAssertTrue(args.contains { $0.hasPrefix("model_catalog_json=") })
        XCTAssertFalse(args.contains { $0.contains("\\/") }, "TOML paths must not contain JSON slash escapes")
    }

    func testInstalledCLICataloguesWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AIRDRAFT_TEST_INSTALLED_CLIS"] == "1" else {
            throw XCTSkip("Opt-in local CLI discovery smoke test")
        }
        for tool in CLIRefiner.Tool.allCases {
            let executable = try XCTUnwrap(tool.locate())
            let models = try await CLIModelCatalog.discover(tool: tool, executable: executable, timeout: 15)
            XCTAssertGreaterThan(models.count, 1)
            print("\(tool.rawValue) catalogue: \(models.map { "\($0.id):\($0.efforts?.map(\.rawValue).joined(separator: ",") ?? "unknown")" }.joined(separator: " | "))")
        }
    }

    func testInstalledCLIRequestsContainNoCodingPromptOrTools() async throws {
        guard let harness = ProcessInfo.processInfo.environment["AIRDRAFT_CLI_WIRE_HARNESS"] else {
            throw XCTSkip("Opt-in wire capture against installed CLIs")
        }
        let request = RefineRequest(transcript: "嗯 這是一個測試", profile: RefinementProfile.defaults[0], context: .empty, family: .general, dictionary: [])
        for (tool, model, effort) in [(CLIRefiner.Tool.claudeCode, "sonnet", ThinkingEffort.xhigh), (.codex, "gpt-5.6-luna", .xhigh), (.codex, "gpt-6-astra", .ultra)] {
            let executable = try XCTUnwrap(tool.locate())
            let wrapper = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-wire-wrapper-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: wrapper) }
            func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            try "#!/bin/sh\nexec \(quote(harness)) \(tool.rawValue) \(quote(executable)) \"$@\"\n"
                .write(to: wrapper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
            let refiner = CLIRefiner(tool: tool, executable: wrapper.path, model: model, effort: effort)
            let result = try await refiner.refine(request)
            XCTAssertEqual(result.text, "這是一個測試。")
        }
    }

    @MainActor
    func testLiveCLIRefinementWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AIRDRAFT_TEST_LIVE_CLI"] == "1" else {
            throw XCTSkip("Opt-in inference using the user's CLI subscriptions")
        }
        let factory = EngineFactory(status: EngineStatus())
        for (kind, model) in [(LLMProviderKind.claudeCode, "sonnet"), (.codex, "gpt-5.6-luna")] {
            let config = LLMConfig(kind: kind, model: model, thinkingEffort: .low)
            let candidate = await factory.refiner(for: config)
            let refiner = try XCTUnwrap(candidate)
            let request = RefineRequest(transcript: "嗯 這是一個測試 今天下午三點開會", profile: RefinementProfile.defaults[0], context: .empty, family: .general, dictionary: [])
            let result: RefineResult
            if var cli = refiner as? CLIRefiner, cli.supportsWarmStart {
                cli.warmSystemPrompt = PromptBuilder.systemPrompt(for: request)
                await cli.prewarm()
                result = try await cli.refine(request)
            } else {
                result = try await refiner.refine(request)
            }
            XCTAssertFalse(result.text.isEmpty)
            XCTAssertTrue(result.text.contains("測試"))
            print("Live refinement \(kind.rawValue): \(result.latencyMs) ms, \(result.text)")
        }
    }
}
