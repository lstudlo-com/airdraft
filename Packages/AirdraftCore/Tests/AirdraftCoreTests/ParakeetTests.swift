import XCTest
@testable import AirdraftCore

final class ParakeetTests: XCTestCase {
    private let requiredAssets = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]

    @MainActor
    func testConfigRoundTripAndFactoryIdentity() async throws {
        let config = ASRConfig(kind: .parakeet)
        let restored = try JSONDecoder().decode(ASRConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
        XCTAssertTrue(restored.kind.isLocal)
        XCTAssertEqual(restored.engineID, "sherpa-onnx:parakeet")
        XCTAssertEqual(LocalModels.folder(for: restored), LocalModels.sherpaFolder(for: .parakeet))
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("A local model must not read a cloud credential")
            return nil
        })
        let first = await factory.transcriber(for: restored)
        let second = await factory.transcriber(for: config)
        XCTAssertEqual(first.id, config.engineID)
        XCTAssertTrue((first as AnyObject) === (second as AnyObject))
        let ready = await first.isReady()
        XCTAssertFalse(ready, "Constructing a provider must not load or download it")
    }

    func testEveryNamedAssetMustBeANonemptyFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for omitted in requiredAssets {
            for name in requiredAssets {
                let file = directory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: file)
                if name != omitted { try Data([1]).write(to: file) }
            }
            XCTAssertFalse(LocalModels.hasSherpa(.parakeet, at: directory), "Missing \(omitted)")
            let omittedFile = directory.appendingPathComponent(omitted)
            try Data().write(to: omittedFile)
            XCTAssertFalse(LocalModels.hasSherpa(.parakeet, at: directory), "Empty \(omitted)")
            try FileManager.default.removeItem(at: omittedFile)
            try FileManager.default.createDirectory(at: omittedFile, withIntermediateDirectories: true)
            XCTAssertFalse(LocalModels.hasSherpa(.parakeet, at: directory), "Directory named \(omitted)")
        }
        for name in requiredAssets {
            let file = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
            try Data([1]).write(to: file)
        }
        XCTAssertTrue(LocalModels.hasSherpa(.parakeet, at: directory))
        try FileManager.default.moveItem(at: directory.appendingPathComponent("joiner.int8.onnx"),
                                        to: directory.appendingPathComponent("joiner.other.onnx"))
        XCTAssertFalse(LocalModels.hasSherpa(.parakeet, at: directory), "Another conversion is not the pinned INT8 asset")
    }

    func testMissingModelDoesNotDownloadOrWriteFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = SherpaTranscriber(model: .parakeet, modelDirectory: directory)
        await assertNotDownloaded { try await engine.prepare() }
        await assertNotDownloaded { _ = try await engine.transcribe(samples: [0.1], hints: .init()) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        let ready = await engine.isReady()
        XCTAssertFalse(ready)
    }

    func testIncompleteInstallNeverReachesNativeRecognizer() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in requiredAssets { try Data([1]).write(to: directory.appendingPathComponent(name)) }
        try Data().write(to: directory.appendingPathComponent(LocalModels.incompleteMarker))
        let engine = SherpaTranscriber(model: .parakeet, modelDirectory: directory)
        await assertNotDownloaded { try await engine.prepare() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(LocalModels.incompleteMarker).path))
    }

    func testArchiveIntegrityRejectsChangedBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive")
        try Data("abc".utf8).write(to: file)
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        XCTAssertNoThrow(try ModelDownloader.verifySHA256(of: file, expected: digest))
        try Data("abd".utf8).write(to: file)
        XCTAssertThrowsError(try ModelDownloader.verifySHA256(of: file, expected: digest)) { error in
            guard case ModelDownloader.DownloadError.checksumMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    /// Explicitly downloaded fixture only; never installs a model or changes app preferences.
    func testNativeOfficialSampleReloadAndLongRecording() async throws {
        guard let path = ProcessInfo.processInfo.environment["AIRDRAFT_PARAKEET_TEST_MODEL_DIR"] else {
            throw XCTSkip("Set AIRDRAFT_PARAKEET_TEST_MODEL_DIR to the verified Parakeet v3 INT8 folder for native inference")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        XCTAssertTrue(LocalModels.hasSherpa(.parakeet, at: directory))
        // Upstream en.wav is 24 kHz; the Transcriber contract is 16 kHz mono.
        let samples = try AudioFile.load(path: directory.appendingPathComponent("test_wavs/en.wav").path)
        XCTAssertEqual(Double(samples.count) / 16_000, 3.845, accuracy: 0.02)
        let expected = "Ask not what your country can do for you, ask what you can do for your country."
        let engine = SherpaTranscriber(model: .parakeet, modelDirectory: directory)
        try await engine.prepare()
        let first = try await engine.transcribe(samples: samples, hints: .init(language: "en"))
        XCTAssertEqual(words(first.text), words(expected))
        XCTAssertEqual(first.engine, "sherpa-onnx:parakeet")
        XCTAssertNil(first.language, "An ignored hint must not be reported as detected language")
        await engine.unload()
        let unloaded = await engine.isReady()
        XCTAssertFalse(unloaded)
        try await engine.prepare()
        let reloaded = try await engine.transcribe(samples: samples, hints: .init())
        XCTAssertEqual(words(reloaded.text), words(expected))

        // Five-second periods put silence in the chunker's 24–30 second search window.
        let period = samples + Array(repeating: Float(0), count: max(0, 80_000 - samples.count))
        let repeated = Array(repeating: period, count: 9).flatMap { $0 }
        XCTAssertGreaterThan(repeated.count, 30 * 16_000)
        let long = try await engine.transcribe(samples: repeated, hints: .init())
        XCTAssertEqual(words(long.text), Array(repeating: words(expected), count: 9).flatMap { $0 })
        print("Parakeet native: sample=\(first.latencyMs)ms reload=\(reloaded.latencyMs)ms long=\(long.latencyMs)ms; long audio=\(Double(repeated.count) / 16_000)s")
        await engine.unload()
        let finalReady = await engine.isReady()
        XCTAssertFalse(finalReady)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-parakeet-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private func assertNotDownloaded(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("Expected modelNotDownloaded", file: file, line: line)
        } catch TranscriberError.modelNotDownloaded {
            // Expected; in particular no native model parse or network request took place.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
