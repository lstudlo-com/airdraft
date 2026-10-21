import Foundation
import Observation

public enum EngineLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case ready
    case failed(String)

    public var label: String {
        switch self {
        case .notLoaded: return String(localized: "Not loaded", bundle: .module)
        case .loading: return String(localized: "Loading…", bundle: .module)
        case .ready: return String(localized: "Loaded", bundle: .module)
        case .failed(let m): return String(localized: "Failed: \(m)", bundle: .module)
        }
    }
}

/// Visible system status for every speech engine: what is in memory right now.
@MainActor
@Observable
public final class EngineStatus {
    public private(set) var states: [String: EngineLoadState] = [:]
    public private(set) var lastUsedAt: [String: Date] = [:]
    private var retiringLoads: Set<String> = []

    public init() {}

    public func state(for engineID: String) -> EngineLoadState { states[engineID] ?? .notLoaded }

    /// Cancelled native preparation may still be reading model files.
    public func hasPendingLoad(for engineID: String) -> Bool {
        state(for: engineID) == .loading || retiringLoads.contains(engineID)
    }

    func setRetiring(_ id: String, _ retiring: Bool) {
        if retiring { retiringLoads.insert(id) }
        else { retiringLoads.remove(id) }
    }

    #if DEBUG
    public func setPreviewState(_ id: String, _ state: EngineLoadState) { set(id, state) }
    #endif

    func set(_ id: String, _ state: EngineLoadState, at date: Date = Date()) {
        states[id] = state
        if state == .ready { lastUsedAt[id] = date }
    }

    func touch(_ id: String, at date: Date = Date()) { lastUsedAt[id] = date }
}
