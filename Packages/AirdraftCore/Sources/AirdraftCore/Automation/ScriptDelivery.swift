import Foundation

/// Sends final text once to a user-selected executable, as literal UTF-8 stdin.
public enum ScriptDelivery {
    public enum Failure: Error, LocalizedError {
        case unavailable(String)
        case execution(String)
        case exited(status: Int32, detail: String)
        case timeout

        public var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .execution(let reason): return "Script delivery failed: \(reason.prefix(300))"
            case .exited(let status, let detail):
                return "Script exited with status \(status)." + (detail.isEmpty ? "" : " \(detail.prefix(300))")
            case .timeout: return "Script delivery timed out. The script may have already acted on the text; it was not retried."
            }
        }
    }

    public static func unavailableReason(path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return "Choose a script using its absolute file path." }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return "The selected script could not be found or read." }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return "Choose a regular executable file." }
        guard FileManager.default.isExecutableFile(atPath: path) else { return "The selected script is not executable. Enable its execute permission." }
        return nil
    }

    public static func send(text: String, to path: String, timeout: TimeInterval = 10) async throws {
        try Task.checkCancellation()
        if let reason = unavailableReason(path: path) { throw Failure.unavailable(reason) }
        let executable = URL(fileURLWithPath: path)
        let process = Process()
        process.executableURL = executable
        process.arguments = []
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        let output: CLIProcess.Output
        do {
            output = try await CLIProcess.run(process, input: text, timeout: timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch RefinerError.timeout {
            throw Failure.timeout
        } catch {
            throw Failure.execution(error.localizedDescription)
        }
        guard output.status == 0 else {
            throw Failure.exited(status: output.status,
                                 detail: String(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
        }
    }
}
