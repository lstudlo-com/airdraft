import Foundation
import Observation

/// Model lifecycle for LM Studio's native REST API (`/api/v1/models`).
/// Other OpenAI-compatible servers are reported as `.unmanaged`.
public actor LMStudioControl {
    public enum ServerKind: Sendable, Equatable { case lmStudio, unmanaged, unreachable }

    /// Context requested when the app loads a model. Honoured by GGUF
    /// (llama.cpp) models, where a huge default context pre-allocates gigabytes
    /// of KV cache. MLX models ignore it and grow their cache on demand.
    public static let dictationContextLength = 8192

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    /// `baseURL` is the OpenAI-compatible one, e.g. http://localhost:1234/v1.
    static func apiRoot(for baseURL: URL) -> URL? {
        guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/api/v1"
        c.query = nil
        return c.url
    }

    public func serverKind(baseURL: URL) async -> ServerKind {
        guard let root = Self.apiRoot(for: baseURL) else { return .unmanaged }
        do {
            let (data, response) = try await session.data(from: root.appendingPathComponent("models"))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["models"] is [Any] else { return .unmanaged }
            return .lmStudio
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut {
            return .unreachable
        } catch {
            return .unmanaged
        }
    }

    /// Ids of the loaded instances of the model with this key (the id used in chat requests).
    public func instances(baseURL: URL, modelKey: String) async throws -> [String] {
        guard let root = Self.apiRoot(for: baseURL) else { return [] }
        let (data, _) = try await session.data(from: root.appendingPathComponent("models"))
        struct Reply: Decodable {
            struct Model: Decodable {
                struct Loaded: Decodable { let id: String }
                let key: String
                let loaded_instances: [Loaded]?
            }
            let models: [Model]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        return reply.models
            .filter { $0.key == modelKey || $0.loaded_instances?.contains(where: { $0.id == modelKey }) == true }
            .flatMap { $0.loaded_instances ?? [] }
            .map(\.id)
    }

    @discardableResult
    public func load(baseURL: URL, modelKey: String) async throws -> String {
        guard let root = Self.apiRoot(for: baseURL) else { throw RefinerError.invalidResponse }
        var req = URLRequest(url: root.appendingPathComponent("models/load"))
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelKey,
            "context_length": Self.dictationContextLength,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RefinerError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(decoding: data, as: UTF8.self))
        }
        struct Reply: Decodable { let instance_id: String }
        return try JSONDecoder().decode(Reply.self, from: data).instance_id
    }

    public func unload(baseURL: URL, instanceID: String) async throws {
        guard let root = Self.apiRoot(for: baseURL) else { return }
        var req = URLRequest(url: root.appendingPathComponent("models/unload"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["instance_id": instanceID])
        _ = try await URLSession.shared.data(for: req)
    }
}

/// Observable state of the refinement model, for the UI.
@MainActor
@Observable
public final class LLMStatus {
    public enum State: Equatable, Sendable {
        case unknown
        case remote            // cloud API, nothing to manage
        case ready(String)     // a local CLI: nothing to load, just report what it is
        case unreachable       // local server not running
        case notLoaded
        case loading
        case loaded(instance: String)
        case failed(String)
    }

    public private(set) var state: State = .unknown
    /// Instances this app loaded or used in this session; unloaded on quit.
    public private(set) var usedInstances: Set<String> = []

    public init() {}

    public func set(_ s: State) { state = s }
    public func markUsed(_ id: String) { usedInstances.insert(id) }
    public func forget(_ id: String) { usedInstances.remove(id) }

    public var label: String {
        switch state {
        case .unknown: return "Checking…"
        case .remote: return "Cloud"
        case .ready(let what): return what
        case .unreachable: return "Server not running"
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .loaded: return "Loaded"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    public var isLoaded: Bool { if case .loaded = state { return true } else { return false } }
}
