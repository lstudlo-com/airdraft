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

/// Debounces memory-pressure events into bounded model-unload passes.
/// - One pass runs at a time; events during a pass coalesce into a single
///   follow-up only when they escalate past the running pass's level.
/// - After a pass, the same or a lower level is ignored for `debounceSeconds`.
@MainActor
public final class MemoryPressureResponder {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "models")
    public static let defaultDebounceSeconds: TimeInterval = 60

    private let source: any MemoryPressureSource
    private let debounceSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private let respond: @MainActor (MemoryPressureLevel) async -> Void
    private var running: (level: MemoryPressureLevel, task: Task<Void, Never>)?
    private var pending: MemoryPressureLevel?
    private var lastHandled: (level: MemoryPressureLevel, at: Date)?
    private var started = false

    public init(source: any MemoryPressureSource = DispatchMemoryPressureSource(),
                debounceSeconds: TimeInterval = MemoryPressureResponder.defaultDebounceSeconds,
                now: @escaping @Sendable () -> Date = { Date() },
                respond: @escaping @MainActor (MemoryPressureLevel) async -> Void) {
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
        lastHandled = (level, now())
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.respond(level)
            self.finish()
        }
        running = (level, task)
    }

    private func finish() {
        running = nil
        guard let next = pending else { return }
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
