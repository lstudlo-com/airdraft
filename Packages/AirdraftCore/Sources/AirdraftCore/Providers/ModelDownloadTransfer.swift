import Foundation

/// Reports bytes while URLSession writes to disk, without buffering model weights in memory.
enum ModelDownloadTransfer {
    struct File: Sendable {
        let url: URL
        let destination: URL
        let size: Int64?
    }

    /// One byte budget includes model files and tokenizer assets. Cached files count only
    /// after matching their manifest size; partial files never become installed assets.
    static func install(_ files: [File], progress: @escaping ModelDownloader.ProgressHandler) async throws {
        let total: Int64? = files.allSatisfy { ($0.size ?? 0) > 0 }
            ? files.reduce(0) { $0 + ($1.size ?? 0) } : nil
        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let name = file.destination.lastPathComponent
            let values = try? file.destination.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if let size = file.size, size > 0, values?.isRegularFile == true, values?.fileSize == Int(size) {
                completed += size
                progress(.init(fraction: total.map { Double(completed) / Double($0) }, currentFile: name,
                               receivedBytes: completed, totalBytes: total))
                continue
            }
            progress(.init(fraction: completed > 0 ? total.map { Double(completed) / Double($0) } : nil,
                           currentFile: "Connecting…", receivedBytes: completed, totalBytes: total))
            let before = completed
            let (temporary, response) = try await download(from: file.url) { received, _ in
                progress(.init(fraction: total.map { Double(before + received) / Double($0) }, currentFile: name,
                               receivedBytes: before + received, totalBytes: total))
            }
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw ModelDownloader.DownloadError.download(file: name, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            let size = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size > 0, file.size == nil || size == file.size else { throw ModelDownloader.DownloadError.incomplete }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: file.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.destination.path) {
                _ = try FileManager.default.replaceItemAt(file.destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: file.destination)
            }
            completed += size
            progress(.init(fraction: total.map { Double(completed) / Double($0) }, currentFile: name,
                           receivedBytes: completed, totalBytes: total))
        }
    }

    static func download(
        from url: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> (URL, URLResponse) {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                delegate.start(session.downloadTask(with: url), continuation: continuation)
            }
        } onCancel: { delegate.cancel() }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: @Sendable (Int64, Int64?) -> Void
        // The lock bridges Swift task cancellation and URLSession's serial delegate queue.
        private let lock = NSLock()
        private var task: URLSessionDownloadTask?
        private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        private var cancelled = false
        // These fields are used only by the serial delegate queue.
        private var lastReport = Date.distantPast
        private var result: (URL, URLResponse)?
        private var fileError: Error?

        init(progress: @escaping @Sendable (Int64, Int64?) -> Void) { self.progress = progress }

        func start(_ task: URLSessionDownloadTask, continuation: CheckedContinuation<(URL, URLResponse), Error>) {
            lock.lock()
            self.task = task
            self.continuation = continuation
            let wasCancelled = cancelled
            lock.unlock()
            if wasCancelled { task.cancel() } else { task.resume() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.1 || totalBytesWritten == totalBytesExpectedToWrite else { return }
            lastReport = now
            progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            // URLSession deletes its temporary file after this callback returns.
            let owned = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-download-\(UUID().uuidString)")
            do {
                guard let response = downloadTask.response else { throw URLError(.badServerResponse) }
                try FileManager.default.moveItem(at: location, to: owned)
                result = (owned, response)
            } catch { fileError = error }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            self.task = nil
            let wasCancelled = cancelled
            lock.unlock()
            if let failure: Error = wasCancelled ? CancellationError() : (error ?? fileError) {
                if let result { try? FileManager.default.removeItem(at: result.0) }
                continuation?.resume(throwing: failure)
            } else if let result {
                continuation?.resume(returning: result)
            } else {
                continuation?.resume(throwing: URLError(.badServerResponse))
            }
        }
    }
}
