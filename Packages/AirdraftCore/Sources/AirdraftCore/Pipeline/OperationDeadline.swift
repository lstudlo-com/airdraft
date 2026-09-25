import Foundation
import os

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

private final class DeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func attach(_ value: CheckedContinuation<Value, Error>) {
        let finished = lock.withLock { () -> Result<Value, Error>? in
            if let result { return result }
            continuation = value
            return nil
        }
        if let finished { value.resume(with: finished) }
    }

    func own(_ work: [Task<Void, Never>]) {
        let finished = lock.withLock {
            if result != nil { return true }
            tasks = work
            return false
        }
        if finished { work.forEach { $0.cancel() } }
    }

    func finish(_ value: Result<Value, Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Value, Error>?, [Task<Void, Never>]) in
            guard result == nil else { return (nil, []) }
            result = value
            defer { continuation = nil; tasks = [] }
            return (continuation, tasks)
        }
        pending.1.forEach { $0.cancel() }
        pending.0?.resume(with: value)
    }
}
