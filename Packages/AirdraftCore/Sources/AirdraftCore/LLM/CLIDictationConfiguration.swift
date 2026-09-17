import Foundation

extension CLIRefiner {
    /// Codex has no --tools "" flag. Feature switches alone are insufficient:
    /// newer model catalogues force Code Mode and multi-agent tool schemas back
    /// on. A per-invocation catalogue selects direct, text-only inference.
    static let codexDisabledFeatures = [
        "shell_tool", "unified_exec", "view_image", "apps", "plugins", "tool_suggest",
        "browser_use", "in_app_browser", "computer_use", "image_generation",
        "multi_agent", "multi_agent_v2", "goals", "sleep_tool", "code_mode", "code_mode_host",
        "memories", "hooks", "skill_search", "workspace_dependencies",
    ]

    static let codexIsolationOverrides = [
        "developer_instructions=\"\"", "personality=\"none\"", "project_doc_max_bytes=0",
        "skills.include_instructions=false", "skills.bundled.enabled=false",
        "include_apps_instructions=false", "include_collaboration_mode_instructions=false",
        "include_permissions_instructions=false", "include_environment_context=false",
        "tools.update_plan.enabled=false", "tools.experimental_request_user_input.enabled=false",
        "web_search=\"disabled\"",
    ] + codexDisabledFeatures.map { "features.\($0)=false" }

    var codexModel: String { model.isEmpty ? Tool.codex.modelSuggestions[0] : model }

    func codexIsolationArguments(outputFile: URL) -> [String] {
        let directory = outputFile.deletingLastPathComponent()
        let overrides = Self.codexIsolationOverrides + [
            "model_instructions_file=\(Self.tomlString(directory.appendingPathComponent("instructions.txt").path))",
            "model_catalog_json=\(Self.tomlString(directory.appendingPathComponent("model.json").path))",
        ]
        return ["--ignore-rules"] + overrides.flatMap { ["-c", $0] }
    }

    /// The model ID is unrestricted. This changes the CLI's local tool setup,
    /// never the account's model access or the effort sent to the provider.
    func prepareCodexFiles(outputFile: URL, systemPrompt: String) throws {
        let directory = outputFile.deletingLastPathComponent()
        try systemPrompt.write(to: directory.appendingPathComponent("instructions.txt"), atomically: true, encoding: .utf8)
        let levels = supportedEfforts?.filter { $0 != .ultra } ?? [effectiveEffort].compactMap { $0 }
        let entry: [String: Any] = [
            "slug": codexModel, "display_name": codexModel, "description": "Dictation refinement",
            "supported_reasoning_levels": levels.map { ["effort": $0 == .off ? "none" : $0.rawValue, "description": $0.title] },
            "default_reasoning_level": effectiveEffort.map { $0 == .off ? "none" : $0.rawValue } ?? "low",
            "visibility": "list", "supported_in_api": true, "priority": 0,
            "tool_mode": "direct", "shell_type": "disabled", "apply_patch_tool_type": NSNull(),
            "multi_agent_version": NSNull(), "experimental_supported_tools": [],
            "supports_search_tool": false, "input_modalities": ["text"],
            "support_verbosity": false, "truncation_policy": ["mode": "tokens", "limit": 10000],
            "base_instructions": systemPrompt, "model_messages": NSNull(),
            "include_skills_usage_instructions": false, "include_plugin_usage_instructions": false,
            "include_apps_usage_instructions": false,
        ]
        try JSONSerialization.data(withJSONObject: ["models": [entry]])
            .write(to: directory.appendingPathComponent("model.json"))
    }

    private static func tomlString(_ value: String) -> String {
        // TOML does not accept JSON's optional \/ escape.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
}
