import XCTest
@testable import AirdraftCore

final class HardeningTests: XCTestCase {
    func testProviderErrorBodyShowsMessagesNotRawPages() {
        XCTAssertEqual(ProviderErrorBody.summary(#"{"error":{"message":"Invalid API key","type":"auth"}}"#), "Invalid API key")
        XCTAssertEqual(ProviderErrorBody.summary(#"{"detail":"Model not found"}"#), "Model not found")
        XCTAssertEqual(ProviderErrorBody.summary("Gemini API key is missing."), "Gemini API key is missing.")
        XCTAssertNil(ProviderErrorBody.summary("<html><body>502</body></html>"))
        XCTAssertNil(ProviderErrorBody.summary(#"{"id":42}"#))
        XCTAssertEqual(RefinerError.http(status: 401, body: #"{"error":"bad key"}"#).localizedDescription,
                       "Refinement provider returned HTTP 401: bad key")
    }

    @MainActor
    func testUnreadableDictionaryIsSetAsideNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("dictionary.json")
        try Data("not json".utf8).write(to: file)

        let store = DictionaryStore(directory: dir)
        store.add(DictionaryEntry(term: "Airdraft"))

        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backup = try XCTUnwrap(names.first { $0.hasPrefix("dictionary.unreadable-") })
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(backup), encoding: .utf8), "not json")
    }

    func testModelRemovalStaysInsideModelsFolder() {
        var config = ASRConfig(kind: .qwen3)
        config.qwen3Model = "../../../../outside"
        XCTAssertThrowsError(try LocalModels.remove(config))
    }

    func testCLIProcessTimesOutAndStops() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let started = Date()
        do {
            _ = try await CLIProcess.run(process, input: "", timeout: 0.5)
            XCTFail("expected a timeout")
        } catch RefinerError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertFalse(process.isRunning)
    }

    func testCLIProcessDrainsLargeOutput() async throws {
        // More than a pipe buffer: reading only after exit would deadlock here.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "head -c 300000 /dev/zero | tr '\\0' a; cat"]
        let output = try await CLIProcess.run(process, input: "tail", timeout: 10)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout.count, 300_004)
        XCTAssertTrue(output.stdout.hasSuffix("tail"))
    }
}
