import Darwin
import XCTest
@testable import AirdraftCore

final class LocalModelCompletenessTests: XCTestCase {
    func testCancellingArchiveExtractionInterruptsBlockedTar() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-archive-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("blocked.tar.bz2")
        XCTAssertEqual(mkfifo(archive.path, 0o600), 0)
        let operation = Task { try await ModelDownloader.unpack(archive, into: folder) }
        try await Task.sleep(for: .milliseconds(100))
        let started = Date()
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("A cancelled extraction must not wait for the archive")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testQwenRejectsEmptyWeightsAndDirectoriesMasqueradingAsFiles() throws {
        try withFolder { folder in
            try write(["vocab.json", "merges.txt"], in: folder)
            XCTAssertFalse(LocalModels.hasQwen3(at: folder))
            let weights = folder.appendingPathComponent("model.safetensors")
            try Data().write(to: weights)
            XCTAssertFalse(LocalModels.hasQwen3(at: folder))
            try FileManager.default.removeItem(at: weights)
            try FileManager.default.createDirectory(at: weights, withIntermediateDirectories: false)
            XCTAssertFalse(LocalModels.hasQwen3(at: folder))
            try FileManager.default.removeItem(at: weights)
            try Data([1]).write(to: weights)
            XCTAssertTrue(LocalModels.hasQwen3(at: folder))
            try Data().write(to: folder.appendingPathComponent("merges.txt"))
            XCTAssertFalse(LocalModels.hasQwen3(at: folder))
        }
    }

    func testCohereRequiresConfigAndBothTokenizerFiles() throws {
        try withFolder { folder in
            try write(["model.safetensors", "tokenizer_config.json"], in: folder)
            XCTAssertFalse(LocalModels.hasCohere(at: folder))
            try write(["tokenizer.model"], in: folder)
            XCTAssertFalse(LocalModels.hasCohere(at: folder))
            try write(["config.json"], in: folder)
            XCTAssertTrue(LocalModels.hasCohere(at: folder))
            try Data().write(to: folder.appendingPathComponent("model-00002.safetensors"))
            XCTAssertFalse(LocalModels.hasCohere(at: folder), "Every discovered shard must be nonempty")
        }
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-model-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func write(_ names: [String], in folder: URL) throws {
        for name in names { try Data([1]).write(to: folder.appendingPathComponent(name)) }
    }
}
