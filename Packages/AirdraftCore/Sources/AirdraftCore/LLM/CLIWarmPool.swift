import Foundation
import os

/// A Claude Code process started while the user is still speaking, waiting on
/// stdin for the transcript. Session setup and auth (~1.3 s) then overlap with
/// recording and transcription instead of being paid after them.
final class CLISession: @unchecked Sendable {
    let key: String
    private let process = Process()
    private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    private let log = Logger(subsystem: "com.lightiichen.airdraft", category: "cli")

    init(key: String, executable: String, arguments: [String], environment: [String: String], workDir: URL) throws {
        self.key = key
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workDir
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
    }

    var isAlive: Bool { process.isRunning }

    /// Sends one user message and reads stream-json lines until the result arrives.
    func send(_ text: String, timeout: TimeInterval) throws -> String {
        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
        ]
        var line = try JSONSerialization.data(withJSONObject: message)
        line.append(0x0A)
        stdin.fileHandleForWriting.write(line)

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty {
                guard process.isRunning else { break }
                continue
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      object["type"] as? String == "result" else { continue }
                stop()
                if let result = object["result"] as? String { return result }
                throw RefinerError.http(status: 0, body: String(describing: object).prefix(300).description)
            }
        }
        stop()
        throw RefinerError.timeout
    }

    func stop() {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    deinit { stop() }
}

/// Holds at most one warm session, for the engine the next dictation will use.
public actor CLIWarmPool {
    public static let shared = CLIWarmPool()
    private var session: CLISession?
    private var startedAt = Date.distantPast
    /// A session waiting this long is stale (the user started recording and walked away).
    private let maxIdle: TimeInterval = 180

    private let log = Logger(subsystem: "com.lightiichen.airdraft", category: "cli")

    func prewarm(key: String, make: () throws -> CLISession) {
        discardIfStale()
        guard session == nil else { return }
        do {
            session = try make()
            startedAt = Date()
            log.notice("warm: session started key=\(key, privacy: .public)")
        } catch {
            log.error("warm: could not start session: \(error.localizedDescription, privacy: .public)")
        }
    }

    func take(key: String) -> CLISession? {
        discardIfStale()
        guard let current = session, current.key == key, current.isAlive else {
            log.notice("warm: miss (have=\(self.session?.key ?? "none", privacy: .public) alive=\(self.session?.isAlive ?? false, privacy: .public) want=\(key, privacy: .public))")
            return nil
        }
        log.notice("warm: hit")
        session = nil
        return current
    }

    public func shutdown() {
        session?.stop()
        session = nil
    }

    private func discardIfStale() {
        guard let current = session else { return }
        if !current.isAlive || Date().timeIntervalSince(startedAt) > maxIdle {
            current.stop()
            session = nil
        }
    }
}
