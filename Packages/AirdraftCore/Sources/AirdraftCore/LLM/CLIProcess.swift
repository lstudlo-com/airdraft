import Darwin
import Foundation
import os

/// Process plumbing shared by CLI refinement, warm sessions and model discovery.
/// Output is drained while the child runs (a full pipe cannot stall it), deadlines
/// are wall-clock, and a stopped child that lingers is killed.
enum CLIProcess {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// SIGTERM now, SIGKILL one second later if the process is still running.
    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Runs `process` to completion with `input` on stdin. Cancelling the calling
    /// task, or reaching `timeout`, stops the process and throws.
    static func run(_ process: Process, input: String, timeout: TimeInterval) async throws -> Output {
        try Task.checkCancellation()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let run = PendingRun()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                run.attach(continuation)
                do {
                    guard try run.start(process) else { return }
                } catch {
                    run.finish(.failure(RefinerError.http(status: 127, body: "Could not run \(process.executableURL?.path ?? "CLI"): \(error.localizedDescription)")))
                    return
                }
                DispatchQueue.global().async {
                    let group = DispatchGroup()
                    let out = LockedData(), err = LockedData()
                    DispatchQueue.global().async(group: group) { out.set(stdout.fileHandleForReading.readDataToEndOfFile()) }
                    DispatchQueue.global().async(group: group) { err.set(stderr.fileHandleForReading.readDataToEndOfFile()) }
                    stdin.fileHandleForWriting.write(Data(input.utf8))
                    try? stdin.fileHandleForWriting.close()
                    group.wait()
                    process.waitUntilExit()
                    run.finish(.success(Output(status: process.terminationStatus,
                                               stdout: String(decoding: out.value, as: UTF8.self),
                                               stderr: String(decoding: err.value, as: UTF8.self))))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    run.finish(.failure(RefinerError.timeout))
                    stop(process)
                }
            }
        } onCancel: {
            run.finish(.failure(CancellationError()))
            stop(process)
        }
    }

    /// Runs blocking pipe reads on a GCD thread instead of Swift's cooperative pool.
    static func blocking<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result { try work() }) }
        }
    }
}

/// Resumes its continuation exactly once, whichever of exit, timeout or cancellation comes first.
private final class PendingRun: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var result: Result<CLIProcess.Output, Error>?
    private var stored: CheckedContinuation<CLIProcess.Output, Error>?

    func attach(_ continuation: CheckedContinuation<CLIProcess.Output, Error>) {
        let completed = lock.withLock { () -> Result<CLIProcess.Output, Error>? in
            if let result { return result }
            stored = continuation
            return nil
        }
        if let completed { continuation.resume(with: completed) }
    }

    func start(_ process: Process) throws -> Bool {
        try lock.withLock {
            guard result == nil else { return false }
            try process.run()
            return true
        }
    }

    func finish(_ value: Result<CLIProcess.Output, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<CLIProcess.Output, Error>? in
            guard result == nil else { return nil }
            result = value
            defer { stored = nil }
            return stored
        }
        continuation?.resume(with: value)
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var data = Data()
    func set(_ new: Data) { lock.withLock { data = new } }
    var value: Data { lock.withLock { data } }
}

/// Newline-delimited reads that never block past a deadline.
struct PipeLineReader {
    let handle: FileHandle
    private var buffer = Data()
    private let limit = 4_194_304

    init(handle: FileHandle) { self.handle = handle }

    /// The next line without its newline, or nil at end of file.
    mutating func nextLine(until deadline: Date, cancelled: () -> Bool = { false }) throws -> Data? {
        while true {
            if cancelled() { throw CancellationError() }
            if Date() >= deadline { throw RefinerError.timeout }
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0 {
                if errno == EINTR { continue }
                throw RefinerError.invalidResponse
            }
            guard ready > 0 else { continue }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
            guard buffer.count <= limit else { throw RefinerError.invalidResponse }
        }
    }
}
