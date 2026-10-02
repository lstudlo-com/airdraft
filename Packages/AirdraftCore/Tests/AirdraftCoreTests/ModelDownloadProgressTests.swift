import Foundation
import Network
import XCTest
@testable import AirdraftCore

final class ModelDownloadProgressTests: XCTestCase {
    func testReportsBytesBeforeFileCompletes() async throws {
        let server = try await SlowModelServer.start()
        defer { server.stop() }
        let updates = DownloadUpdates()
        let (file, _) = try await ModelDownloadTransfer.download(from: server.url("weights")) { received, total in
            updates.append(.init(fraction: total.map { Double(received) / Double($0) },
                                 currentFile: "weights", receivedBytes: received, totalBytes: total))
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let partial = updates.values.filter { ($0.fraction ?? 0) > 0 && ($0.fraction ?? 1) < 1 }
        XCTAssertGreaterThan(partial.count, 2, "Progress must arrive during a single large file, not only at completion")
        XCTAssertEqual(partial.first?.totalBytes, Int64(SlowModelServer.size))
        XCTAssertEqual(updates.values.compactMap(\.receivedBytes), updates.values.compactMap(\.receivedBytes).sorted())
        XCTAssertEqual(try Data(contentsOf: file).count, SlowModelServer.size)
    }

    func testUnknownLengthReportsReceivedBytesWithoutInventingPercentage() async throws {
        let server = try await SlowModelServer.start()
        defer { server.stop() }
        let updates = DownloadUpdates()
        let (file, _) = try await ModelDownloadTransfer.download(from: server.url("unknown")) { received, total in
            updates.append(.init(fraction: total.map { Double(received) / Double($0) },
                                 currentFile: "weights", receivedBytes: received, totalBytes: total))
        }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertGreaterThan(updates.values.count, 2)
        XCTAssertTrue(updates.values.allSatisfy { $0.fraction == nil && $0.totalBytes == nil })
        XCTAssertTrue(updates.values.allSatisfy { ($0.receivedBytes ?? 0) > 0 })
    }

    func testAggregateIncludesTokenizerAndCachedBytes() async throws {
        let server = try await SlowModelServer.start()
        defer { server.stop() }
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let cached = root.appendingPathComponent("cached")
        try Data(repeating: 3, count: 32).write(to: cached)
        let updates = DownloadUpdates()
        try await ModelDownloadTransfer.install([
            .init(url: server.url("missing"), destination: cached, size: 32),
            .init(url: server.url("weights"), destination: root.appendingPathComponent("weights"), size: Int64(SlowModelServer.size)),
            .init(url: server.url("tokenizer"), destination: root.appendingPathComponent("tokenizer"), size: Int64(SlowModelServer.size))
        ], progress: { updates.append($0) })
        let values = updates.values
        XCTAssertTrue(values.filter { $0.currentFile == "weights" }.allSatisfy { ($0.fraction ?? 1) < 1 })
        XCTAssertTrue(values.filter { $0.currentFile == "tokenizer" }.contains { ($0.fraction ?? 1) < 1 })
        XCTAssertEqual(values.last?.fraction, 1)
        XCTAssertEqual(values.last?.receivedBytes, Int64(32 + 2 * SlowModelServer.size))
        let fractions = values.compactMap(\.fraction)
        XCTAssertEqual(fractions, fractions.sorted())
    }

    func testFailedAndWrongSizeDownloadsNeverInstall() async throws {
        let server = try await SlowModelServer.start()
        defer { server.stop() }
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, size) in [("missing", SlowModelServer.size), ("weights", 7)] {
            let destination = root.appendingPathComponent(path)
            do {
                try await ModelDownloadTransfer.install([
                    .init(url: server.url(path), destination: destination, size: Int64(size))
                ], progress: { _ in })
                XCTFail("Must reject HTTP errors and incomplete manifest sizes")
            } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path)) }
        }
    }

    @MainActor
    func testStorePublishesLiveBytesAndCancellationCannotInstall() async throws {
        let server = try await SlowModelServer.start()
        defer { server.stop() }
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("weights")
        let store = ModelDownloadStore(download: { _, progress in
            try await ModelDownloadTransfer.install([
                .init(url: server.url("weights"), destination: destination, size: Int64(SlowModelServer.size))
            ], progress: progress)
        }, installed: { _ in FileManager.default.fileExists(atPath: destination.path) })
        let config = ASRConfig(kind: .whisperKit)
        var completed = false
        store.start(config) { completed = true }
        for _ in 0..<200 {
            if (store.jobs[config.engineID]?.progress?.receivedBytes ?? 0) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let live = try XCTUnwrap(store.jobs[config.engineID]?.progress)
        XCTAssertGreaterThan(live.receivedBytes ?? 0, 0)
        XCTAssertLessThan(live.fraction ?? 1, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        store.cancel(config)
        for _ in 0..<200 {
            if !store.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(store.isBusy)
        XCTAssertFalse(completed)
        XCTAssertNil(store.jobs[config.engineID]?.progress)
        XCTAssertTrue(store.jobs[config.engineID]?.error?.contains("cancelled") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnknownStagesAndNearCompletionLabels() {
        XCTAssertEqual(ModelDownloader.Progress(fraction: nil, currentFile: "Unpacking…").detail, "")
        XCTAssertTrue(ModelDownloader.Progress(fraction: 0.99999, currentFile: "weights").detail.hasPrefix("99.9%"))
        XCTAssertTrue(ModelDownloader.Progress(fraction: 0.001, currentFile: "weights").detail.hasPrefix("0.1%"))
        XCTAssertNil(ModelDownloader.Progress(fraction: .nan, currentFile: "weights").fraction)
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-transfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class DownloadUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ModelDownloader.Progress] = []
    func append(_ item: ModelDownloader.Progress) { lock.lock(); defer { lock.unlock() }; items.append(item) }
    var values: [ModelDownloader.Progress] { lock.lock(); defer { lock.unlock() }; return items }
}

/// Real loopback HTTP, deliberately sending a file over several delegate callback intervals.
/// Does not use URLProtocol, whose synthetic responses can bypass URLSession's disk writer.
private final class SlowModelServer: @unchecked Sendable {
    static let size = 1_048_576
    private let listener: NWListener
    private let queue = DispatchQueue(label: "airdraft.test.download-server")
    private var connections: [NWConnection] = []
    private var started = false
    private init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    static func start() async throws -> SlowModelServer {
        let server = try SlowModelServer()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.listener.stateUpdateHandler = { state in
                guard !server.started else { return }
                if case .ready = state { server.started = true; continuation.resume() }
                if case .failed(let error) = state { server.started = true; continuation.resume(throwing: error) }
            }
            server.listener.newConnectionHandler = { connection in
                server.connections.append(connection)
                connection.start(queue: server.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let request = String(decoding: data ?? Data(), as: UTF8.self)
                    if request.contains("/missing") {
                        connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                                        completion: .contentProcessed { _ in connection.cancel() })
                        return
                    }
                    let length = request.contains("/unknown") ? "" : "Content-Length: \(size)\r\n"
                    let headers = "HTTP/1.1 200 OK\r\n\(length)Connection: close\r\nContent-Type: application/octet-stream\r\n\r\n"
                    connection.send(content: Data(headers.utf8), completion: .contentProcessed { error in
                        if error == nil { server.sendChunk(connection, remaining: 8) }
                    })
                }
            }
            server.listener.start(queue: server.queue)
        }
        return server
    }
    private func sendChunk(_ connection: NWConnection, remaining: Int) {
        guard remaining > 0 else { connection.cancel(); return }
        queue.asyncAfter(deadline: .now() + 0.15) {
            connection.send(content: Data(repeating: 42, count: Self.size / 8), completion: .contentProcessed { error in
                if error == nil { self.sendChunk(connection, remaining: remaining - 1) }
            })
        }
    }
    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/\(path)")! }
    func stop() {
        queue.async { self.listener.cancel(); self.connections.forEach { $0.cancel() }; self.connections.removeAll() }
    }
}
