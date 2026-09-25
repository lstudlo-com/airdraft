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
        let stdoutTruncated: Bool
        let stderrTruncated: Bool
    }

    enum Failure: Error, LocalizedError {
        case launchFailed(String)
        case pipeFailure
        case incompleteInput

        var errorDescription: String? {
            switch self {
            case .launchFailed(let reason): return "Could not run the executable: \(reason.prefix(300))"
            case .pipeFailure: return "Could not communicate with the executable."
            case .incompleteInput: return "The executable closed its input before all text was delivered."
            }
        }
    }

    /// Retain a prefix of each stream while still draining every byte from the child.
    static let outputLimit = 1_048_576

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
        guard timeout.isFinite, timeout > 0 else { throw RefinerError.timeout }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let control = RunCancellation()
        return try await withTaskCancellationHandler {
            try await blocking {
                let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                let handles = [stdin.fileHandleForReading, stdin.fileHandleForWriting,
                               stdout.fileHandleForReading, stdout.fileHandleForWriting,
                               stderr.fileHandleForReading, stderr.fileHandleForWriting]
                defer { handles.forEach { try? $0.close() } }
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = stderr
                // Keep the child's ends blocking. Only our three endpoints are nonblocking.
                let inputFD = stdin.fileHandleForWriting.fileDescriptor
                let outputFD = stdout.fileHandleForReading.fileDescriptor
                let errorFD = stderr.fileHandleForReading.fileDescriptor
                for descriptor in [inputFD, outputFD, errorFD] {
                    let flags = fcntl(descriptor, F_GETFL)
                    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
                        throw Failure.pipeFailure
                    }
                }
                // Per-descriptor suppression avoids a process-wide SIGPIPE handler change.
                guard fcntl(inputFD, F_SETNOSIGPIPE, 1) != -1 else { throw Failure.pipeFailure }
                try checkDeadline(deadline, control: control)
                do {
                    try control.start(process)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw Failure.launchFailed(error.localizedDescription)
                }
                do {
                    return try pump(process, stdin: stdin.fileHandleForWriting,
                                    stdout: outputFD, stderr: errorFD, input: Data(input.utf8),
                                    deadline: deadline, control: control)
                } catch {
                    stop(process)
                    throw error
                }
            }
        } onCancel: {
            control.cancel()
        }
    }

    /// A prewarmed process shares the same bounded, simultaneous input/output pump.
    /// Finish as soon as its terminal JSON line arrives, even if it waits for more input.
    static func exchange(_ process: Process, stdin: FileHandle, stdout: FileHandle,
                         input: Data, timeout: TimeInterval, control: RunCancellation,
                         consumeLine: @escaping (Data) throws -> Bool) throws {
        guard timeout.isFinite, timeout > 0 else { throw RefinerError.timeout }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        for descriptor in [stdin.fileDescriptor, stdout.fileDescriptor] {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
                throw Failure.pipeFailure
            }
        }
        guard fcntl(stdin.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw Failure.pipeFailure }
        _ = try pump(process, stdin: stdin, stdout: stdout.fileDescriptor, stderr: -1,
                     input: input, deadline: deadline, control: control, consumeLine: consumeLine)
    }

    private static func checkDeadline(_ deadline: TimeInterval, control: RunCancellation) throws {
        try control.checkCancellation()
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw RefinerError.timeout }
    }

    /// One owner for all file descriptors. A bounded poll loop avoids parked reader
    /// threads when an exited child leaves its pipes open in a descendant.
    private static func pump(_ process: Process, stdin: FileHandle, stdout: Int32, stderr: Int32,
                             input: Data, deadline: TimeInterval, control: RunCancellation,
                             consumeLine: ((Data) throws -> Bool)? = nil) throws -> Output {
        var inputOpen = true, outputOpen = true, errorOpen = stderr >= 0
        var sent = 0
        var lineStart = 0
        var lineScan = 0
        var out = BoundedOutput(), err = BoundedOutput()
        while true {
            try checkDeadline(deadline, control: control)
            let running = process.isRunning
            if inputOpen && (sent == input.count || !running) {
                try? stdin.close()
                inputOpen = false
            }
            if !running && !outputOpen && !errorOpen {
                if sent != input.count && process.terminationStatus == 0 { throw Failure.incompleteInput }
                return Output(status: process.terminationStatus,
                              stdout: String(decoding: out.data, as: UTF8.self),
                              stderr: String(decoding: err.data, as: UTF8.self),
                              stdoutTruncated: out.truncated, stderrTruncated: err.truncated)
            }

            var descriptors = [
                pollfd(fd: outputOpen ? stdout : -1, events: Int16(POLLIN), revents: 0),
                pollfd(fd: errorOpen ? stderr : -1, events: Int16(POLLIN), revents: 0),
                pollfd(fd: inputOpen ? stdin.fileDescriptor : -1, events: Int16(POLLOUT), revents: 0),
            ]
            let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            let milliseconds = Int32(min(50, ceil(remaining * 1_000)))
            let ready = poll(&descriptors, nfds_t(descriptors.count), milliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw Failure.pipeFailure
            }
            try checkDeadline(deadline, control: control)
            if descriptors[0].revents != 0 { outputOpen = try drain(stdout, into: &out) }
            if descriptors[1].revents != 0 { errorOpen = try drain(stderr, into: &err) }
            if inputOpen && descriptors[2].revents != 0 {
                let count = input.withUnsafeBytes { bytes in
                    Darwin.write(stdin.fileDescriptor, bytes.baseAddress!.advanced(by: sent), min(16_384, input.count - sent))
                }
                if count > 0 { sent += count }
                else if count < 0 && errno == EPIPE {
                    try? stdin.close()
                    inputOpen = false
                } else if count < 0 && errno != EAGAIN && errno != EINTR {
                    throw Failure.pipeFailure
                }
            }
            if let consumeLine {
                guard !out.truncated else { throw RefinerError.invalidResponse }
                while lineScan < out.data.count {
                    let index = lineScan
                    lineScan += 1
                    guard out.data[index] == 0x0A else { continue }
                    let line = out.data.subdata(in: lineStart..<index)
                    lineStart = lineScan
                    if try consumeLine(line) {
                        guard sent == input.count else { throw Failure.incompleteInput }
                        try checkDeadline(deadline, control: control)
                        return Output(status: 0, stdout: "", stderr: "", stdoutTruncated: false, stderrTruncated: false)
                    }
                }
            }
        }
    }

    /// Limit work per iteration too: endless output must not starve cancellation or stdin.
    private static func drain(_ descriptor: Int32, into output: inout BoundedOutput) throws -> Bool {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        for _ in 0..<16 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return false }
            if count > 0 { output.append(buffer.prefix(count)); continue }
            if errno == EAGAIN { return true }
            if errno == EINTR { continue }
            throw Failure.pipeFailure
        }
        return true
    }

    /// Runs blocking pipe reads on a GCD thread instead of Swift's cooperative pool.
    static func blocking<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result { try work() }) }
        }
    }
}

/// Cancellation and launch share one lock, so an already cancelled run cannot start a child.
final class RunCancellation: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }

    func checkCancellation() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
        }
    }

    func start(_ process: Process) throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
        }
    }
}

private struct BoundedOutput {
    var data = Data()
    var truncated = false

    mutating func append(_ bytes: ArraySlice<UInt8>) {
        let available = max(0, CLIProcess.outputLimit - data.count)
        data.append(contentsOf: bytes.prefix(available))
        if bytes.count > available { truncated = true }
    }
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
