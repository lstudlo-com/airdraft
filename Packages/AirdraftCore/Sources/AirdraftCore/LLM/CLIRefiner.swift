import Foundation
import os

/// Refinement through a coding-agent CLI already installed and logged in on this
/// Mac (Claude Code, Codex). The user's own subscription pays for it, so there
/// is no API key and no per-token bill. Each call is a one-shot, non-interactive
/// run in a temporary directory: no session files, no project context, no tools.
public struct CLIRefiner: Refiner {
    public enum Tool: String, Codable, Sendable, CaseIterable {
        case claudeCode
        case codex

        public var executableName: String {
            switch self {
            case .claudeCode: return "claude"
            case .codex: return "codex"
            }
        }

        /// Offline suggestions only. The picker normally discovers models from the CLI.
        public var modelSuggestions: [String] {
            switch self {
            case .claudeCode: return ["default", "best", "fable", "sonnet", "opus", "haiku", "sonnet[1m]", "opus[1m]", "opusplan"]
            case .codex: return ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]
            }
        }

        public var effortSuggestions: [ThinkingEffort] {
            switch self {
            case .claudeCode: return [.low, .medium, .high, .xhigh, .max]
            case .codex: return [.low, .medium, .high, .xhigh, .max]
            }
        }

        static let claudeIsolationArguments = [
            "--tools", "", "--restricted", "--strict-mcp-config",
            "--disable-slash-commands", "--no-session-persistence", "--safe-mode",
        ]

        static var environment: [String: String] {
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (searchPaths + ["/bin", "/usr/sbin"]).joined(separator: ":")
            env["HOME"] = NSHomeDirectory()
            return env
        }

        /// Directories a GUI app has to look in itself: it does not inherit the shell's PATH.
        static let searchPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.bun/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
            "/usr/bin",
        ]

        /// Absolute path of the installed CLI, or nil when it is not on this Mac.
        public func locate() -> String? {
            for dir in Self.searchPaths {
                let path = dir + "/" + executableName
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
            return nil
        }
    }

    public let id: String
    public let tool: Tool
    public let executable: String
    /// Empty means the CLI's own default model.
    public let model: String
    public let effort: ThinkingEffort
    public let supportedEfforts: [ThinkingEffort]?
    public let timeout: TimeInterval

    public init(tool: Tool, executable: String, model: String, effort: ThinkingEffort = .off, timeout: TimeInterval = 60, supportedEfforts: [ThinkingEffort]? = nil) {
        self.tool = tool
        self.executable = executable
        self.model = model
        self.effort = effort
        self.supportedEfforts = supportedEfforts
        self.timeout = timeout
        self.id = "\(tool.rawValue):\(model.isEmpty ? "default" : model)"
    }

    /// `off` means the least thinking the selected model permits. In particular,
    /// current Codex models reject `none`; an unavailable catalogue uses Low.
    var effectiveEffort: ThinkingEffort? {
        if let supportedEfforts { return effort.supported(in: supportedEfforts.filter { $0 != .ultra }) }
        if effort == .off { return .low }
        return effort.supported(in: tool.effortSuggestions)
    }

    /// Identifies a warm session: anything that changes these has to be a new process.
    func warmKey(systemPrompt: String) -> String {
        "\(tool.rawValue)|\(executable)|\(model)|\(effectiveEffort?.rawValue ?? "default")|\(systemPrompt.hashValue)"
    }

    /// Claude Code can wait on stdin, so the process can be started while the user
    /// is still speaking. Codex `exec` has no such mode and always runs cold.
    public var supportsWarmStart: Bool { tool == .claudeCode }

    /// Arguments for a session that receives its prompt on stdin later.
    func warmArguments(systemPrompt: String) -> [String] {
        var args = arguments(outputFile: URL(fileURLWithPath: "/dev/null"), systemPrompt: systemPrompt)
        args += ["--input-format", "stream-json", "--verbose"]
        // Streaming input needs streaming output.
        if let index = args.firstIndex(of: "--output-format") { args[index + 1] = "stream-json" }
        return args
    }

    /// Starts a session now so the next dictation only pays for inference.
    public func prewarm() async {
        guard supportsWarmStart else { return }
        let systemPrompt = warmSystemPrompt
        let arguments = warmArguments(systemPrompt: systemPrompt)
        let key = warmKey(systemPrompt: systemPrompt)
        let environment = self.environment
        let executable = self.executable
        await CLIWarmPool.shared.prewarm(key: key) {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("airdraft-cli-warm")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return try CLISession(key: key, executable: executable, arguments: arguments, environment: environment, workDir: dir)
        }
    }

    /// System prompt the warm session is started with; refine falls back to a cold
    /// run when the real request produces a different one.
    public var warmSystemPrompt: String = ""

    /// Arguments for one non-interactive run. `outputFile` is only used by Codex,
    /// which writes its final message there instead of to stdout.
    func arguments(outputFile: URL, systemPrompt: String) -> [String] {
        switch tool {
        case .claudeCode:
            var args = [
                "-p",
                "--output-format", "json",
                // Replaces Claude Code's coding-agent prompt with the dictation rules.
                "--system-prompt", systemPrompt,
                // Without these the CLI ships its tool schemas, skills and settings on every
                // call: 15k tokens of subscription usage per dictation instead of ~400.
            ] + Tool.claudeIsolationArguments
            if !model.isEmpty { args += ["--model", model] }
            if let effectiveEffort { args += ["--effort", effectiveEffort.levelName] }
            return args
        case .codex:
            var args = [
                "exec",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--ephemeral",
                // Skip the user's own config: their hooks and default model must not
                // fire on every dictation.
                "--ignore-user-config",
                "-o", outputFile.path,
            ]
            if let effectiveEffort {
                args += ["-c", "model_reasoning_effort=\"\(effectiveEffort == .off ? "none" : effectiveEffort.rawValue)\""]
            }
            args += codexIsolationArguments(outputFile: outputFile)
            args += ["--model", codexModel]
            args.append("-")  // prompt on stdin
            return args
        }
    }

    /// Both CLIs receive only the transcript as input. Their coding-agent
    /// instructions are replaced separately with the refinement system prompt.
    func input(for request: RefineRequest) -> String {
        PromptBuilder.userMessage(for: request)
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        let started = Date()
        let systemPrompt = PromptBuilder.systemPrompt(for: request)
        if supportsWarmStart, let session = await CLIWarmPool.shared.take(key: warmKey(systemPrompt: systemPrompt)) {
            let raw = try session.send(PromptBuilder.userMessage(for: request), timeout: timeout)
            let text = PromptBuilder.sanitize(raw)
            guard !text.isEmpty else { throw RefinerError.emptyOutput }
            return RefineResult(
                text: text, engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                promptVersion: PromptBuilder.version, servedBy: model.isEmpty ? tool.executableName : model
            )
        }
        let workDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("airdraft-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let outputFile = workDir.appendingPathComponent("last-message.txt")
        if tool == .codex { try prepareCodexFiles(outputFile: outputFile, systemPrompt: systemPrompt) }

        let output = try await run(
            arguments: arguments(outputFile: outputFile, systemPrompt: PromptBuilder.systemPrompt(for: request)),
            input: input(for: request),
            workDir: workDir
        )

        let raw: String
        switch tool {
        case .claudeCode:
            struct Reply: Decodable { let result: String?; let is_error: Bool? }
            guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(output.utf8)), reply.is_error != true,
                  let result = reply.result else {
                throw RefinerError.http(status: 0, body: String(output.prefix(300)))
            }
            raw = result
        case .codex:
            raw = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? ""
        }

        let text = PromptBuilder.sanitize(raw)
        guard !text.isEmpty else { throw RefinerError.emptyOutput }
        return RefineResult(
            text: text, engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000),
            promptVersion: PromptBuilder.version, servedBy: model.isEmpty ? tool.executableName : model
        )
    }

    /// A GUI app's environment has no usable PATH; the CLIs need one plus HOME for their login.
    var environment: [String: String] {
        var env = Tool.environment
        if tool == .claudeCode {
            // These inherited variables take precedence over --effort, so a
            // shell setting must not silently override the app's selection.
            env.removeValue(forKey: "CLAUDE_CODE_EFFORT_LEVEL")
            env.removeValue(forKey: "CLAUDE_CODE_DISABLE_THINKING")
            env.removeValue(forKey: "MAX_THINKING_TOKENS")
        }
        return env
    }

    private func run(arguments: [String], input: String, workDir: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workDir
        process.environment = environment

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { continuation in
            let finished = OSAllocatedUnfairLock(initialState: false)
            func finish(_ result: Result<String, Error>) {
                let alreadyDone = finished.withLock { done -> Bool in
                    if done { return true }
                    done = true
                    return false
                }
                guard !alreadyDone else { return }
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if proc.terminationStatus == 0 {
                    finish(.success(out))
                } else {
                    finish(.failure(RefinerError.http(status: Int(proc.terminationStatus), body: String((err + out).prefix(400)))))
                }
            }

            do {
                try process.run()
            } catch {
                finish(.failure(RefinerError.http(status: 127, body: "Could not run \(executable): \(error.localizedDescription)")))
                return
            }

            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                finish(.failure(RefinerError.timeout))
            }
        }
    }
}
