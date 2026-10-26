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

    func testIncompleteEmptyOrInterruptedModelFilesAreNeverInstalled() throws {
        // Qwen rejects empty weights and directories masquerading as files.
        do {
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

        // Cohere requires its config and both tokenizer files.
        do {
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

        // AD-074: transfers follow manifest order, so cancelling between config.json and
        // generation_config.json used to leave a Whisper choice that counted as installed.
        do {
            for variant in [WhisperModelVariant.turbo, .largeV3] {
                let artifact = try XCTUnwrap(PinnedHubModelCatalog.whisper(variant))
                let cut = try XCTUnwrap(artifact.files.firstIndex { $0.path == "generation_config.json" })
                XCTAssertTrue(artifact.files[..<cut].contains { $0.path == "config.json" })
                try withFolder { folder in
                    try write(artifact.files[..<cut].map(\.path), in: folder)
                    for key in ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"] {
                        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(key).path),
                                      "the loader's key files are already present at the cut: \(key)")
                    }
                    XCTAssertFalse(LocalModels.hasWhisper(variant.rawValue, at: folder), variant.rawValue)
                    try write(artifact.files[cut...].map(\.path), in: folder)
                    XCTAssertTrue(LocalModels.hasWhisper(variant.rawValue, at: folder), variant.rawValue)
                    try Data().write(to: folder.appendingPathComponent(artifact.files[cut].path))
                    XCTAssertFalse(LocalModels.hasWhisper(variant.rawValue, at: folder), "an empty pinned file is incomplete")
                }
            }
        }

        // An interrupted pinned Qwen download is not installed.
        do {
            for model in ["aufklarer/Qwen3-ASR-1.7B-MLX-5bit", "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"] {
                let artifact = try XCTUnwrap(PinnedHubModelCatalog.qwen3(model))
                let cut = try XCTUnwrap(artifact.files.firstIndex { $0.path == "tokenizer_config.json" })
                try withFolder { folder in
                    // Weights, vocab and merges arrive before tokenizer_config.json.
                    try write(artifact.files.map(\.path).filter { $0 != "tokenizer_config.json" }, in: folder)
                    XCTAssertTrue(LocalModels.hasQwen3(at: folder), "the generic MLX check alone passes")
                    XCTAssertFalse(LocalModels.hasQwen3(model, at: folder), model)
                    try write([artifact.files[cut].path], in: folder)
                    XCTAssertTrue(LocalModels.hasQwen3(model, at: folder), model)
                }
            }
            try withFolder { folder in
                try write(["model.safetensors", "vocab.json", "merges.txt"], in: folder)
                XCTAssertTrue(LocalModels.hasQwen3("someone/unpinned", at: folder), "unpinned folders keep the generic check")
            }
        }
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-model-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func write(_ names: [String], in folder: URL) throws {
        for name in names {
            let file = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: file)
        }
    }
}
