import CryptoKit
import Foundation
import XCTest
@testable import AirdraftCore

final class ModelArchiveIntegrityTests: XCTestCase {
    func testEveryFixedSherpaArchiveHasAPublishedDigest() throws {
        for model in SherpaTranscriber.Model.allCases {
            let digest = try XCTUnwrap(model.archiveSHA256)
            XCTAssertEqual(digest.count, 64)
            XCTAssertTrue(digest.allSatisfy { "0123456789abcdef".contains($0) })
        }
        XCTAssertEqual(Set(SherpaTranscriber.Model.allCases.compactMap(\.archiveSHA256)).count, 3)
    }

    func testArchiveVerificationAcceptsExactBytesAndRejectsChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-integrity-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("candidate")
        let bytes = Data("harmless model archive fixture".utf8)
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try bytes.write(to: archive)
        XCTAssertNoThrow(try ModelDownloader.verifySHA256(of: archive, expected: expected))
        try Data("changed model archive fixture".utf8).write(to: archive)
        XCTAssertThrowsError(try ModelDownloader.verifySHA256(of: archive, expected: expected)) { error in
            guard case ModelDownloader.DownloadError.checksumMismatch = error else {
                return XCTFail("Expected integrity rejection, got \(error)")
            }
        }
    }

    func testInvalidDownloadedArchiveNeverReachesInstalledModel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-install-integrity-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installation = root.appendingPathComponent("models")
        for model in SherpaTranscriber.Model.allCases {
            let folder = installation.appendingPathComponent(model.folderName)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let previous = folder.appendingPathComponent("previous")
            try Data("previous valid model".utf8).write(to: previous)
            let candidate = root.appendingPathComponent("candidate")
            try Data("harmless corrupted archive".utf8).write(to: candidate)
            do {
                try await ModelDownloader.installSherpaArchive(candidate, model: model, root: installation) { _ in }
                XCTFail("Changed model bytes must fail before unpacking")
            } catch {
                guard case ModelDownloader.DownloadError.checksumMismatch = error else {
                    return XCTFail("Expected integrity rejection, got \(error)")
                }
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["previous"])
            XCTAssertEqual(try String(contentsOf: previous, encoding: .utf8), "previous valid model")
            XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path), "Unverified archive must not move into model storage")
            XCTAssertFalse(FileManager.default.fileExists(atPath: installation.appendingPathComponent(model.folderName + ".tar.bz2").path))
        }
    }
}
