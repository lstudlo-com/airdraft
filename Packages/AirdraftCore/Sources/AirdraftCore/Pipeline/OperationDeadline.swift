import Foundation
import Synchronization

/// Bounds a whole operation, including dependencies that ignore cancellation.
/// Late results are discarded; the losing task is cancelled, never awaited.
public enum OperationDeadline {
    public static func run<Value: Sendable>(seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let race = DeadlineRace<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.attach(continuation)
                let work = Task {
                    do {
                        try Task.checkCancellation()
                        race.finish(.success(try await operation()))
                    } catch { race.finish(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await Task.sleep(for: .seconds(max(0, seconds)))
                        race.finish(.failure(RefinerError.timeout))
                    } catch {}
                }
                race.own([work, timer])
            }
        } onCancel: { race.finish(.failure(CancellationError())) }
    }
}

private final class DeadlineRace<Value: Sendable>: Sendable {
    private struct State {
        var result: Result<Value, Error>?
        var continuation: CheckedContinuation<Value, Error>?
        var tasks: [Task<Void, Never>] = []
    }
    private let state = Mutex(State())

    func attach(_ value: CheckedContinuation<Value, Error>) {
        let finished = state.withLock { state -> Result<Value, Error>? in
            if let result = state.result { return result }
            state.continuation = value
            return nil
        }
        if let finished { value.resume(with: finished) }
    }

    func own(_ work: [Task<Void, Never>]) {
        let finished = state.withLock { state in
            if state.result != nil { return true }
            state.tasks = work
            return false
        }
        if finished { work.forEach { $0.cancel() } }
    }

    func finish(_ value: Result<Value, Error>) {
        let pending = state.withLock { state -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>]) in
            guard state.result == nil else { return (nil, []) }
            state.result = value
            defer { state.continuation = nil; state.tasks = [] }
            return (state.continuation, state.tasks)
        }
        pending.1.forEach { $0.cancel() }
        pending.0?.resume(with: value)
    }
}
