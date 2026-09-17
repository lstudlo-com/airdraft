import Darwin
import Foundation
import os

/// Model identifiers and capabilities reported by the installed, signed-in CLI.
/// nil efforts means an older CLI omitted capabilities; [] means no effort control.
public struct CLIModelInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let efforts: [ThinkingEffort]?
    public let isDefault: Bool
    public let hidden: Bool

    /// Ultra is Codex's multi-agent workflow, not a per-inference effort.
    /// Tool-free refinement cannot use it; Codex otherwise silently sends Medium.
    public var dictationEfforts: [ThinkingEffort]? { efforts?.filter { $0 != .ultra } }

    public init(id: String, title: String, efforts: [ThinkingEffort]? = nil, isDefault: Bool = false, hidden: Bool = false) {
        self.id = id
        self.title = title
        self.efforts = efforts
        self.isDefault = isDefault
        self.hidden = hidden
    }

    public static func selected(_ model: String, in models: [Self]) -> Self? {
        model.isEmpty ? models.first(where: \.isDefault) : models.first { $0.id == model }
    }
}

/// Discovery sends only initialization/catalogue requests, never an inference
/// prompt. Cache in memory so dictation does not start a discovery process each time.
public actor CLIModelCatalog {
    public static let shared = CLIModelCatalog()
    private var cache: [String: [CLIModelInfo]] = [:]
    private var failedAt: [String: Date] = [:]

    public func models(tool: CLIRefiner.Tool, executable: String, refresh: Bool = false, timeout: TimeInterval = 10) async throws -> [CLIModelInfo] {
        let key = "\(tool.rawValue)|\(executable)"
        if !refresh, let cached = cache[key] { return cached }
        if !refresh, let failed = failedAt[key], Date().timeIntervalSince(failed) < 30 {
            throw RefinerError.invalidResponse
        }
        do {
            let result = try await Self.discover(tool: tool, executable: executable, timeout: timeout)
            cache[key] = result
            failedAt[key] = nil
            return result
        } catch {
            if !(error is CancellationError) { failedAt[key] = Date() }
            throw error
        }
    }

    static func discover(tool: CLIRefiner.Tool, executable: String, timeout: TimeInterval) async throws -> [CLIModelInfo] {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                let session = try CatalogSession(tool: tool, executable: executable, timeout: timeout, cancelled: cancelled)
                defer { session.close() }
                switch tool {
                case .codex:
                    try session.send([
                        "id": 1, "method": "initialize",
                        "params": ["clientInfo": ["name": "airdraft", "version": "1.0"]],
                    ])
                    _ = try session.codexReply(id: 1)
                    try session.send(["method": "initialized"])
                    var result: [CLIModelInfo] = []
                    var cursor: String?
                    var seenCursors: Set<String> = []
                    var requestID = 2
                    repeat {
                        var params: [String: Any] = ["includeHidden": true, "limit": 100]
                        if let cursor { params["cursor"] = cursor }
                        try session.send(["id": requestID, "method": "model/list", "params": params])
                        let page = try session.codexReply(id: requestID)
                        result += try parseCodex(page)
                        cursor = page["nextCursor"] as? String
                        if let cursor, !seenCursors.insert(cursor).inserted { throw RefinerError.invalidResponse }
                        requestID += 1
                    } while cursor != nil
                    return unique(result)
                case .claudeCode:
                    try session.send([
                        "type": "control_request", "request_id": "models",
                        "request": ["subtype": "initialize"],
                    ])
                    while true {
                        let message = try session.receive()
                        guard message["type"] as? String == "control_response",
                              let response = message["response"] as? [String: Any],
                              response["request_id"] as? String == "models" else { continue }
                        guard response["subtype"] as? String == "success",
                              let body = response["response"] as? [String: Any] else { throw RefinerError.invalidResponse }
                        return try parseClaude(body)
                    }
                }
            }.value
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    static func parseCodex(_ reply: [String: Any]) throws -> [CLIModelInfo] {
        guard let data = reply["data"] as? [[String: Any]] else { throw RefinerError.invalidResponse }
        return data.compactMap { model in
            guard let id = model["model"] as? String, !id.isEmpty else { return nil }
            let levels = (model["supportedReasoningEfforts"] as? [[String: Any]])?.compactMap {
                ($0["reasoningEffort"] as? String).flatMap(ThinkingEffort.cliValue)
            }
            return CLIModelInfo(id: id, title: model["displayName"] as? String ?? id, efforts: levels,
                                isDefault: model["isDefault"] as? Bool ?? false, hidden: model["hidden"] as? Bool ?? false)
        }
    }

    static func parseClaude(_ reply: [String: Any]) throws -> [CLIModelInfo] {
        guard let models = reply["models"] as? [[String: Any]] else { throw RefinerError.invalidResponse }
        var result: [CLIModelInfo] = []
        for model in models {
            guard let id = model["value"] as? String, !id.isEmpty else { continue }
            let levels: [ThinkingEffort]?
            if model["supportsEffort"] as? Bool == false {
                levels = []
            } else if let values = model["supportedEffortLevels"] as? [String] {
                levels = values.compactMap(ThinkingEffort.cliValue)
            } else if model["supportsEffort"] as? Bool == true {
                levels = [.low, .medium, .high]
            } else {
                // Claude omits the capability fields on Haiku and other models
                // without effort support. Old SDK replies omit resolvedModel too.
                levels = model["resolvedModel"] == nil ? nil : []
            }
            result.append(CLIModelInfo(id: id, title: model["displayName"] as? String ?? id,
                                       efforts: levels, isDefault: id == "default"))
            if let resolved = model["resolvedModel"] as? String, resolved != id {
                result.append(CLIModelInfo(id: resolved, title: resolved, efforts: levels))
            }
        }
        return unique(result)
    }

    private static func unique(_ models: [CLIModelInfo]) -> [CLIModelInfo] {
        var seen: Set<String> = []
        return models.filter { seen.insert($0.id).inserted }
    }
}

/// Bounded newline-JSON exchange on a background thread. Polling lets a silent
/// or broken CLI time out, and drains stdout while the child is still running.
private final class CatalogSession {
    private let process = Process()
    private let stdin = Pipe(), stdout = Pipe()
    private let directory: URL
    private let deadline: Date
    private let cancelled: OSAllocatedUnfairLock<Bool>
    private var buffer = Data()

    init(tool: CLIRefiner.Tool, executable: String, timeout: TimeInterval, cancelled: OSAllocatedUnfairLock<Bool>) throws {
        self.cancelled = cancelled
        deadline = Date().addingTimeInterval(timeout)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-models-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = directory
        process.environment = CLIRefiner.Tool.environment
        switch tool {
        case .codex:
            process.arguments = ["app-server"]
        case .claudeCode:
            process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
                + CLIRefiner.Tool.claudeIsolationArguments
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        // Startup output can contain account details. Never surface it in UI/logs.
        process.standardError = FileHandle.nullDevice
        do {
            try checkDeadline()
            try process.run()
        } catch {
            close()
            throw error
        }
    }

    func send(_ object: [String: Any]) throws {
        try checkDeadline()
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }

    func codexReply(id: Int) throws -> [String: Any] {
        while true {
            let object = try receive()
            guard object["id"] as? Int == id else { continue }
            guard object["error"] == nil, let result = object["result"] as? [String: Any] else { throw RefinerError.invalidResponse }
            return result
        }
    }

    func receive() throws -> [String: Any] {
        while true {
            try checkDeadline()
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard !line.isEmpty else { continue }
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw RefinerError.invalidResponse }
                return object
            }
            var descriptor = pollfd(fd: stdout.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 {
                if errno == EINTR { continue }
                throw RefinerError.invalidResponse
            }
            guard ready > 0 else { continue }
            let chunk = stdout.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw RefinerError.invalidResponse }
            buffer.append(chunk)
            guard buffer.count <= 4_194_304 else { throw RefinerError.invalidResponse }
        }
    }

    private func checkDeadline() throws {
        if cancelled.withLock({ $0 }) { throw CancellationError() }
        if Date() >= deadline { throw RefinerError.timeout }
    }

    func close() {
        try? stdin.fileHandleForWriting.close()
        try? stdout.fileHandleForReading.close()
        if process.isRunning {
            process.terminate()
            let process = self.process
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
