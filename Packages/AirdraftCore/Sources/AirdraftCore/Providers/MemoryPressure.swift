import Dispatch
import Foundation
import os

/// System memory-pressure levels the app responds to. `normal` is not delivered:
/// recovering memory does not reload anything; the next dictation does that.
public enum MemoryPressureLevel: Int, Comparable, Sendable, CustomStringConvertible {
    case warning = 1
    case critical = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { self == .critical ? "critical" : "warning" }

    /// Models used more recently than this survive the pass. A warning leaves a
    /// model the user is still dictating with; critical pressure frees almost
    /// everything idle, but not a model that finished loading moments ago.
    public var minimumIdleSeconds: TimeInterval { self == .critical ? 15 : 120 }
}

/// Delivers memory-pressure events. Injected in tests; production uses the
/// kernel's dispatch source.
public protocol MemoryPressureSource: AnyObject, Sendable {
    func start(_ handler: @escaping @Sendable (MemoryPressureLevel) -> Void)
    func cancel()
}

/// `DispatchSource.makeMemoryPressureSource` for warning and critical events.
/// `@unchecked Sendable`: `source` is created, read and cancelled only on `queue`.
public final class DispatchMemoryPressureSource: MemoryPressureSource, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lstudlo.app.airdraft.memory-pressure")
    private var source: DispatchSourceMemoryPressure?

    public init() {}

    public func start(_ handler: @escaping @Sendable (MemoryPressureLevel) -> Void) {
        queue.async { [self] in
            guard source == nil else { return }
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
            source.setEventHandler { [weak source] in
                guard let event = source?.data else { return }
                if event.contains(.critical) { handler(.critical) }
                else if event.contains(.warning) { handler(.warning) }
            }
            self.source = source
            source.activate()
        }
    }

    public func cancel() {
        queue.async { [self] in
            source?.cancel()
            source = nil
        }
    }
}

/// Whether a memory-pressure pass freed what it could or had to stand aside.
public enum MemoryPressurePassResult: Sendable, Equatable {
    /// The pass ran; models still in use or within their grace period stayed.
    case completed
    /// Busy work (dictation, media, a meeting, cleanup or a factory lease) made
    /// the pass touch nothing. Its level waits for `resumeDeferred()`.
    case deferred
}

/// Debounces memory-pressure events into bounded model-unload passes.
/// - One pass runs at a time; events during a pass coalesce into a single
///   follow-up only when they escalate past the running pass's level.
/// - After a completed pass, the same or a lower level is ignored for
///   `debounceSeconds`. A deferred pass is not stamped: its highest level waits
///   until `resumeDeferred()` (called when busy work ends) runs it again, with
///   the level's usual grace periods measured from then.
@MainActor
public final class MemoryPressureResponder {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "models")
    public static let defaultDebounceSeconds: TimeInterval = 60

    private let source: any MemoryPressureSource
    private let debounceSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private let respond: @MainActor (MemoryPressureLevel) async -> MemoryPressurePassResult
    private var running: (level: MemoryPressureLevel, task: Task<Void, Never>)?
    private var pending: MemoryPressureLevel?
    private var lastHandled: (level: MemoryPressureLevel, at: Date)?
    /// The highest level whose pass was deferred by busy work.
    public private(set) var deferredLevel: MemoryPressureLevel?
    private var started = false

    public init(source: any MemoryPressureSource = DispatchMemoryPressureSource(),
                debounceSeconds: TimeInterval = MemoryPressureResponder.defaultDebounceSeconds,
                now: @escaping @Sendable () -> Date = { Date() },
                respond: @escaping @MainActor (MemoryPressureLevel) async -> MemoryPressurePassResult) {
        self.source = source
        self.debounceSeconds = debounceSeconds
        self.now = now
        self.respond = respond
    }

    public func start() {
        guard !started else { return }
        started = true
        source.start { level in
            Task { @MainActor [weak self] in self?.receive(level) }
        }
    }

    public func stop() {
        guard started else { return }
        started = false
        source.cancel()
        pending = nil
        deferredLevel = nil
    }

    /// Runs a pass deferred by busy work, now that the work has ended. Does
    /// nothing when no pass waits, after `stop()`, or while a pass is running
    /// (that pass's completion runs the waiting level).
    public func resumeDeferred() {
        guard started, running == nil, let level = deferredLevel else { return }
        deferredLevel = nil
        Self.log.debug("memory pressure \(level.description, privacy: .public) resumed after busy work")
        run(level)
    }

    /// The running pass, for tests that must observe its completion.
    var currentPass: Task<Void, Never>? { running?.task }

    /// Internal for tests; production events arrive from `source`.
    func receive(_ level: MemoryPressureLevel) {
        if let running {
            if level > running.level { pending = max(pending ?? level, level) }
            return
        }
        if let lastHandled, level <= lastHandled.level,
           now().timeIntervalSince(lastHandled.at) < debounceSeconds {
            Self.log.debug("memory pressure \(level.description, privacy: .public) debounced")
            return
        }
        run(level)
    }

    private func run(_ level: MemoryPressureLevel) {
        let startedAt = now()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.respond(level)
            self.finish(level, startedAt: startedAt, result: result)
        }
        running = (level, task)
    }

    private func finish(_ level: MemoryPressureLevel, startedAt: Date, result: MemoryPressurePassResult) {
        running = nil
        switch result {
        case .completed:
            lastHandled = (level, startedAt)
            // A completed pass at this level or higher covers a deferred one.
            if let deferred = deferredLevel, deferred <= level { deferredLevel = nil }
        case .deferred:
            deferredLevel = max(deferredLevel ?? level, level)
        }
        guard started, let next = pending else { return }
        pending = nil
        run(next)
    }
}

/// What one memory-pressure pass did to resident speech engines.
public struct MemoryPressureUnload: Equatable, Sendable {
    /// Engine IDs whose models were unloaded.
    public var unloaded: [String] = []
    /// Engines kept because an active dictation pinned them.
    public var keptPinned: [String] = []
    /// Engines kept because they were used within the level's grace period.
    public var keptRecent: [String] = []
    /// The factory lease was held or queued (a load or inference), so the pass
    /// touched nothing rather than waiting behind it.
    public var skippedBusy = false

    public init(unloaded: [String] = [], keptPinned: [String] = [], keptRecent: [String] = [], skippedBusy: Bool = false) {
        self.unloaded = unloaded
        self.keptPinned = keptPinned
        self.keptRecent = keptRecent
        self.skippedBusy = skippedBusy
    }
}
