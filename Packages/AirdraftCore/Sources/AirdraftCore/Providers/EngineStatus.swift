import Foundation
import Observation

public enum EngineLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case ready
    case failed(String)

    public var label: String {
        switch self {
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .ready: return "Loaded"
        case .failed(let m): return "Failed: \(m)"
        }
    }
}

/// Visible system status for every speech engine: what is in memory right now.
@MainActor
@Observable
public final class EngineStatus {
    public private(set) var states: [String: EngineLoadState] = [:]
    public private(set) var lastUsedAt: [String: Date] = [:]

    public init() {}

    public func state(for engineID: String) -> EngineLoadState { states[engineID] ?? .notLoaded }

    func set(_ id: String, _ state: EngineLoadState) {
        states[id] = state
        if state == .ready { lastUsedAt[id] = Date() }
    }

    func touch(_ id: String) { lastUsedAt[id] = Date() }
}
