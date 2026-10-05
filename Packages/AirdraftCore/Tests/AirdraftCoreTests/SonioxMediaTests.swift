import XCTest
@testable import AirdraftCore

final class SonioxMediaTests: XCTestCase {
    private let fileID = "11111111-1111-4111-8111-111111111111"
    private let jobID = "22222222-2222-4222-8222-222222222222"
    override func tearDown() { MediaHTTPFixture.handler = nil; super.tearDown() }
    private func session(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
        MediaHTTPFixture.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaHTTPFixture.self]
        return URLSession(configuration: configuration)
    }
    func testResumingJobDoesNotUploadAgainAndPreservesSpeakerTimes() async throws {
        var document = TranscriptDocument(recordingID: "asset", title: "Test", configuration: .init(engine: .soniox))
        document.remoteFileID = fileID; document.remoteJobID = jobID
        let id = jobID
        let session = session { request in
            XCTAssertEqual(request.httpMethod, "GET")
            if request.url!.path.hasSuffix("/transcript") {
                return (200, #"{"tokens":[{"text":"Hello","start_ms":1500,"end_ms":2100,"speaker":"2"},{"text":"<|end|>"}]}"#)
            }
            return (200, "{\"id\":\"\(id)\",\"status\":\"completed\"}")
        }
        let result = try await SonioxMediaTranscriber(key: "fixture", session: session)
            .transcribe(url: URL(fileURLWithPath: "/nonexistent"), stagingDirectory: URL(fileURLWithPath: "/nonexistent"), document: document) { _, _ in XCTFail("Resumed IDs must not change") }
        XCTAssertEqual(result, [.init(start: 1.5, end: 2.1, text: "Hello", speaker: "2")])
    }
    func testDiarizationOptInAndDurableJobIDBeforePolling() async throws {
        var document = TranscriptDocument(recordingID: "asset", title: "Test", configuration: .init(engine: .soniox, identifySpeakers: true))
        document.remoteFileID = fileID
        let id = jobID
        let checkpoint = Checkpoint()
        let session = session { request in
            if request.httpMethod == "POST" {
                var body = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
                    }
                }
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object["enable_speaker_diarization"] as? Bool, true)
                return (200, "{\"id\":\"\(id)\",\"status\":\"queued\"}")
            }
            if request.url!.path.hasSuffix("/transcript") { return (200, #"{"tokens":[]}"#) }
            return (200, "{\"id\":\"\(id)\",\"status\":\"completed\"}")
        }
        _ = try await SonioxMediaTranscriber(key: "fixture", session: session)
            .transcribe(url: URL(fileURLWithPath: "/nonexistent"), stagingDirectory: URL(fileURLWithPath: "/nonexistent"), document: document) { file, job in await checkpoint.save(file, job) }
        let saved = await checkpoint.ids
        XCTAssertEqual(saved.0, fileID); XCTAssertEqual(saved.1, jobID)
    }
    func testCleanupOnlyKnownIDsIsIdempotentAndReportsFailure() async throws {
        let session = session { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return (404, "{}")
        }
        try await SonioxMediaTranscriber(key: "fixture", session: session).cleanup(fileID: fileID, jobID: jobID)
        do {
            try await SonioxMediaTranscriber(key: "fixture", session: session).cleanup(fileID: "../another-user", jobID: nil)
            XCTFail("Unsafe identifier accepted")
        } catch TranscriberError.invalidResponse {}
        let failing = self.session { _ in (500, "{}") }
        do {
            try await SonioxMediaTranscriber(key: "fixture", session: failing).cleanup(fileID: fileID, jobID: nil)
            XCTFail("Cleanup failure was suppressed")
        } catch TranscriberError.http(let status, _) { XCTAssertEqual(status, 500) }
    }
}
private actor Checkpoint {
    var ids: (String?, String?) = (nil, nil)
    func save(_ file: String?, _ job: String?) { ids = (file, job) }
}
private final class MediaHTTPFixture: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
