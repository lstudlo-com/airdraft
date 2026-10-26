import CryptoKit
import Foundation
import XCTest
@testable import AirdraftCore

/// Qwen3-ASR and WhisperKit downloads use immutable revisions with every
/// file's size and SHA-256, like the GGUF and Core ML catalogues.
final class PinnedHubModelTests: XCTestCase {
    private let qwenModels = ["aufklarer/Qwen3-ASR-1.7B-MLX-5bit", "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"]

    /// Every downloadable choice is pinned to a commit with sized, hashed files, the pinned
    /// files satisfy the loader completeness checks, and recorded digests match the
    /// measured installations.
    func testEveryChoiceIsPinnedCompleteAndMatchesMeasuredDigests() throws {
        do { // EveryDownloadableQwenAndWhisperChoiceIsPinned
            var artifacts = try qwenModels.map { try XCTUnwrap(PinnedHubModelCatalog.qwen3($0), $0) }
            artifacts += try WhisperModelVariant.allCases.map { try XCTUnwrap(PinnedHubModelCatalog.whisper($0), $0.rawValue) }
            artifacts.append(try XCTUnwrap(PinnedHubModelCatalog.whisperTokenizer))
            let hex = { (value: String, count: Int) in
                value.count == count && value.allSatisfy { "0123456789abcdef".contains($0) }
            }
            for artifact in artifacts {
                XCTAssertTrue(hex(artifact.revision, 40), "\(artifact.id) must use a commit, not a branch")
                XCTAssertFalse(artifact.files.isEmpty, artifact.id)
                XCTAssertEqual(Set(artifact.files.map(\.path)).count, artifact.files.count, artifact.id)
                for file in artifact.files {
                    XCTAssertGreaterThan(file.bytes, 0, "\(artifact.id)/\(file.path)")
                    XCTAssertTrue(hex(file.sha256, 64), "\(artifact.id)/\(file.path)")
                    let url = artifact.url(for: file).absoluteString
                    XCTAssertTrue(url.contains("/resolve/\(artifact.revision)/"), url)
                    XCTAssertFalse(url.contains("/resolve/main/"), url)
                }
            }
            XCTAssertNil(PinnedHubModelCatalog.qwen3("someone/unreviewed-model"))
        }

        do { // PinnedFilesSatisfyTheLoaderCompletenessChecks
            for model in qwenModels {
                let paths = Set(try XCTUnwrap(PinnedHubModelCatalog.qwen3(model)).files.map(\.path))
                XCTAssertTrue(paths.isSuperset(of: ["config.json", "vocab.json", "merges.txt", "tokenizer_config.json"]), model)
                XCTAssertTrue(paths.contains { $0.hasSuffix(".safetensors") }, model)
            }
            for variant in WhisperModelVariant.allCases {
                let artifact = try XCTUnwrap(PinnedHubModelCatalog.whisper(variant))
                XCTAssertEqual(artifact.directory, variant.directoryName)
                let paths = artifact.files.map(\.path)
                XCTAssertTrue(paths.contains("config.json"), variant.rawValue)
                for bundle in ["AudioEncoder.mlmodelc/", "TextDecoder.mlmodelc/", "MelSpectrogram.mlmodelc/"] {
                    XCTAssertTrue(paths.contains { $0.hasPrefix(bundle) }, "\(variant.rawValue) lacks \(bundle)")
                }
                XCTAssertFalse(variant.sizeLabel.isEmpty)
            }
            let tokenizer = try XCTUnwrap(PinnedHubModelCatalog.whisperTokenizer)
            XCTAssertEqual(Set(tokenizer.files.map(\.path)), Set(LocalModels.whisperTokenizerFiles))
        }

        do { // RecordedDigestsMatchTheMeasuredInstallations
            // Recorded in eval/mixed-asr/results/environment.json from the installed copies.
            let large = try XCTUnwrap(PinnedHubModelCatalog.qwen3(qwenModels[0]))
            XCTAssertEqual(large.files.first { $0.path == "model.safetensors" }?.sha256,
                           "4c3dd2e56a6fa3523bc996e728b7011362af317c6b0616c8d78bb1b8d9ff600e")
            let small = try XCTUnwrap(PinnedHubModelCatalog.qwen3(qwenModels[1]))
            XCTAssertEqual(small.files.first { $0.path == "model.safetensors" }?.sha256,
                           "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf")
            let turbo = try XCTUnwrap(PinnedHubModelCatalog.whisper(.turbo))
            XCTAssertEqual(turbo.files.first { $0.path == "AudioEncoder.mlmodelc/weights/weight.bin" }?.sha256,
                           "98daf651a919978e28fe185daf55ce2f70085a8e59fa07fe8a4d08c87d368ae4")
        }
    }

    func testTransfersRejectUnsafePathsKeepMatchingFilesAndInstallOnlyVerifiedBytes() async throws {
        do { // UnsafeManifestPathsNeverBecomeTransfers
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinned-\(UUID().uuidString)")
            for path in ["../escape.bin", "/etc/passwd", "a/../../b", ""] {
                let artifact = try artifact(files: [(path, Data([1]))])
                XCTAssertThrowsError(try artifact.transferFiles(into: folder), path)
            }
        }

        do { // MatchingExistingFilesAreKeptWithoutDownloading
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinned-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            let weights = Data(repeating: 7, count: 4096), vocab = Data("{}".utf8)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try weights.write(to: folder.appendingPathComponent("model.safetensors"))
            try vocab.write(to: folder.appendingPathComponent("vocab.json"))
            let artifact = try artifact(files: [("model.safetensors", weights), ("vocab.json", vocab)])
            try await ModelDownloadTransfer.install(try artifact.transferFiles(into: folder), progress: { _ in }, fetch: { url, _ in
                XCTFail("A file that matches its pinned digest must not download again: \(url)")
                throw URLError(.badURL)
            })
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("model.safetensors")), weights)
        }

        do { // ChangedExistingFileIsReplacedOnlyByVerifiedBytes
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinned-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            let expected = Data(repeating: 7, count: 64)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("model.safetensors")
            try Data(repeating: 9, count: 64).write(to: destination)
            let artifact = try artifact(files: [("model.safetensors", expected)])
            do {
                try await ModelDownloadTransfer.install(try artifact.transferFiles(into: folder), progress: { _ in }, fetch: { _, _ in
                    try PinnedHubModelTests.served(Data(repeating: 8, count: 64))
                })
                XCTFail("Bytes that do not match the pinned digest must be rejected")
            } catch ModelDownloader.DownloadError.checksumMismatch {}
            try await ModelDownloadTransfer.install(try artifact.transferFiles(into: folder), progress: { _ in }, fetch: { url, _ in
                XCTAssertTrue(url.absoluteString.contains("/resolve/0123456789abcdef0123456789abcdef01234567/"))
                return try PinnedHubModelTests.served(expected)
            })
            XCTAssertEqual(try Data(contentsOf: destination), expected)
        }
    }

    func testUnpinnedModelsAndDamagedManifestsFailWithoutNetworkOrCrash() async throws {
        do { // UnreviewedQwenModelIsRefusedBeforeAnyNetworkAccess
            do {
                try await ModelDownloader.shared.downloadQwen3(modelId: "someone/unreviewed-model") { _ in }
                XCTFail("An unpinned model must not download")
            } catch ModelDownloader.DownloadError.unpinned(let model) {
                XCTAssertEqual(model, "someone/unreviewed-model")
            } catch { XCTFail("Unexpected error: \(error)") }
        }

        // AD-074: a missing or malformed bundled manifest must not crash the app at
        // first use. Its downloads fail with an actionable error instead.
        do { // DamagedManifestFailsGracefullyWithActionableError
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            func manifest(_ contents: String?) throws -> PinnedHubModelCatalog.Manifest {
                guard let contents else { return .init(url: directory.appendingPathComponent("missing.json")) }
                let url = directory.appendingPathComponent(UUID().uuidString + ".json")
                try Data(contents.utf8).write(to: url)
                return .init(url: url)
            }
            let entry = #"{"id":"qwen3:a","repository":"r/a","revision":"0123456789abcdef0123456789abcdef01234567","directory":"","files":[]}"#
            let damaged = [try manifest(nil), PinnedHubModelCatalog.Manifest(url: nil), try manifest("{not json"),
                           try manifest("[]"), try manifest("[\(entry),\(entry)]")]
            for catalog in damaged {
                XCTAssertTrue(catalog.artifacts.isEmpty)
                XCTAssertNil(catalog.artifact("qwen3:a"))
                XCTAssertThrowsError(try catalog.require("qwen3:a", model: "a")) { error in
                    XCTAssertTrue(error is PinnedHubManifestError, "\(error)")
                    XCTAssertTrue(error.localizedDescription.contains("Reinstall Airdraft"), error.localizedDescription)
                }
            }
            // A readable manifest still refuses IDs it does not review.
            let valid = try manifest("[\(entry)]")
            XCTAssertNil(valid.error)
            XCTAssertEqual(try valid.require("qwen3:a", model: "a").id, "qwen3:a")
            XCTAssertThrowsError(try valid.require("qwen3:b", model: "b")) { error in
                guard case ModelDownloader.DownloadError.unpinned("b") = error else { return XCTFail("\(error)") }
            }
            XCTAssertNil(PinnedHubModelCatalog.manifestError, "The bundled manifest is valid")
        }
    }

    // MARK: Helpers

    private func artifact(files: [(String, Data)]) throws -> PinnedHubArtifact {
        let entries = files.map { path, data in
            ["path": path, "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()] as [String: Any]
        }
        let json: [String: Any] = ["id": "test", "repository": "example/model", "revision": "0123456789abcdef0123456789abcdef01234567",
                                   "directory": "", "files": entries]
        return try JSONDecoder().decode(PinnedHubArtifact.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private static func served(_ data: Data) throws -> (URL, URLResponse) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("served-\(UUID().uuidString)")
        try data.write(to: file)
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (file, response)
    }
}
