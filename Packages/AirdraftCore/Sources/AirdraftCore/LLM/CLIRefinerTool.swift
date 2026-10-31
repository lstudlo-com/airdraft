import Foundation

#if !os(macOS)
/// iOS has no subprocesses and so no CLI refiner; the namespace keeps saved
/// refinement configs that name a CLI tool readable.
public enum CLIRefiner {}
#endif

extension CLIRefiner {
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
}
