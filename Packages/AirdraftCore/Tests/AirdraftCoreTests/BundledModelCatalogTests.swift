import XCTest
@testable import AirdraftCore

/// A missing, malformed or unreviewed bundled GGUF or Core ML catalogue must
/// not crash at first use, and must never supply an artifact to install.
final class BundledModelCatalogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ contents: String?) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".json")
        if let contents { try Data(contents.utf8).write(to: url) }
        return url
    }

    private let revision = String(repeating: "a", count: 40)
    private let digest = String(repeating: "b", count: 64)

    private func gguf(id: String = "whisper-tiny", repository: String = "org/repo", revision: String? = nil,
                      filename: String = "model-Q8_0.gguf", bytes: Int = 10, sha256: String? = nil,
                      languages: String = #"["en"]"#) -> String {
        """
        {"id":"\(id)","title":"T","family":"F","creator":"C","brand":"B","repository":"\(repository)",
         "revision":"\(revision ?? self.revision)","filename":"\(filename)","quantization":"Q8_0","bytes":\(bytes),
         "sha256":"\(sha256 ?? digest)","languages":\(languages),"automatic":true,"manualControl":"automatic",
         "license":"MIT","documentation":"https://example.com"}
        """
    }

    private func coreML(id: String = "parakeet-v2", revision: String? = nil, path: String = "Decoder.mlmodelc/weights/weight.bin",
                        second: String? = nil, bytes: Int = 10, sha256: String? = nil) -> String {
        let files = ([path] + (second.map { [$0] } ?? [])).map {
            #"{"path":"\#($0)","bytes":\#(bytes),"sha256":"\#(sha256 ?? digest)"}"#
        }.joined(separator: ",")
        return """
        {"id":"\(id)","title":"T","repository":"org/repo","revision":"\(revision ?? self.revision)","version":"v2",
         "precision":"int8","creator":"C","languages":["en"],"files":[\(files)]}
        """
    }

    private func assertDamaged<Entry>(_ catalog: BundledModelCatalog<Entry>, _ kind: ModelCatalogueError.Catalogue,
                                      id: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(catalog.models.isEmpty, file: file, line: line)
        XCTAssertEqual(catalog.error?.catalogue, kind, file: file, line: line)
        XCTAssertNil(catalog.model(id), file: file, line: line)
        XCTAssertThrowsError(try catalog.require(id), file: file, line: line) { error in
            XCTAssertTrue(error is ModelCatalogueError, "\(error)", file: file, line: line)
            XCTAssertTrue(error.localizedDescription.contains("Reinstall Airdraft"), error.localizedDescription, file: file, line: line)
        }
    }

    func testDamagedGGUFCatalogueIsUnavailableInsteadOfCrashing() throws {
        let damaged: [String?] = [
            nil, "{not json", "[]", "[\(gguf()),\(gguf())]",
            "[\(gguf(id: "../escape"))]", "[\(gguf(id: ".hidden"))]", "[\(gguf(filename: "a/b.gguf"))]",
            "[\(gguf(filename: ".."))]", "[\(gguf(repository: "not a repo"))]", "[\(gguf(revision: "main"))]",
            "[\(gguf(bytes: 0))]", "[\(gguf(sha256: "abc"))]", "[\(gguf(languages: "[]"))]",
            // One bad entry rejects the whole file, including the good one.
            "[\(gguf(id: "good")),\(gguf(id: "bad", sha256: "x"))]"
        ]
        for contents in damaged {
            assertDamaged(GGUFModelCatalog.catalog(url: try file(contents)), .gguf, id: "whisper-tiny")
        }
        assertDamaged(GGUFModelCatalog.catalog(url: nil), .gguf, id: "whisper-tiny")
        assertDamaged(GGUFModelCatalog.catalog(url: try file("[\(gguf(id: "good")),\(gguf(id: "bad", sha256: "x"))]")),
                      .gguf, id: "good")

        let valid = GGUFModelCatalog.catalog(url: try file("[\(gguf())]"))
        XCTAssertNil(valid.error)
        let model = try valid.require("whisper-tiny")
        XCTAssertEqual(model.downloadURL?.absoluteString,
                       "https://huggingface.co/org/repo/resolve/\(revision)/model-Q8_0.gguf")
        XCTAssertThrowsError(try valid.require("unknown")) { error in
            guard case ModelDownloader.DownloadError.unpinned("unknown") = error else { return XCTFail("\(error)") }
        }
    }

    func testDamagedCoreMLCatalogueIsUnavailableInsteadOfCrashing() throws {
        let damaged: [String?] = [
            nil, "{", "[]", "[\(coreML()),\(coreML())]",
            "[\(coreML(path: "../../escape.bin"))]", "[\(coreML(path: "/etc/passwd"))]",
            "[\(coreML(path: "Decoder.mlmodelc//weight.bin"))]", "[\(coreML(path: "has space.bin"))]",
            "[\(coreML(path: "a.bin", second: "a.bin"))]", "[\(coreML(id: "a/b"))]",
            "[\(coreML(revision: String(repeating: "A", count: 40)))]", "[\(coreML(bytes: -1))]",
            "[\(coreML(sha256: String(repeating: "z", count: 64)))]",
            #"[{"id":"parakeet-v2","title":"T","repository":"org/repo","revision":"\#(revision)","version":"v2","precision":"int8","creator":"C","languages":["en"],"files":[]}]"#,
            #"[{"id":"parakeet-v2","title":"T","repository":"org/repo","revision":"\#(revision)","version":"v2","precision":"int8","creator":"C","languages":[],"files":[{"path":"a.bin","bytes":1,"sha256":"\#(digest)"}]}]"#
        ]
        for contents in damaged {
            assertDamaged(CoreMLSpeechModelCatalog.catalog(url: try file(contents)), .coreML, id: "parakeet-v2")
        }

        let valid = CoreMLSpeechModelCatalog.catalog(url: try file("[\(coreML())]"))
        XCTAssertNil(valid.error)
        let model = try valid.require("parakeet-v2")
        XCTAssertEqual(model.downloadURL(for: model.files[0])?.absoluteString,
                       "https://huggingface.co/org/repo/resolve/\(revision)/Decoder.mlmodelc/weights/weight.bin")
    }

    /// The shipped catalogues pass the same review, so every engine stays available.
    func testBundledCataloguesPassReview() {
        XCTAssertNil(GGUFModelCatalog.catalogueError)
        XCTAssertNil(CoreMLSpeechModelCatalog.catalogueError)
        XCTAssertFalse(GGUFModelCatalog.models.isEmpty)
        XCTAssertFalse(CoreMLSpeechModelCatalog.models.isEmpty)
        for kind in [ASRProviderKind.transcribeCpp, .fluidAudio, .whisperKit] {
            XCTAssertNil(LocalModels.catalogueError(for: ASRConfig(kind: kind)))
        }
        XCTAssertEqual(ModelCatalogueError(catalogue: .gguf, detail: "x").errorDescription?.contains("GGUF"), true)
        XCTAssertEqual(ModelCatalogueError(catalogue: .coreML, detail: "x").errorDescription?.contains("Core ML"), true)
    }
}
