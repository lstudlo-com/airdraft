import XCTest
@testable import AirdraftCore

final class LMStudioControlTests: XCTestCase {
    func testModelSnapshotDiscoversServerAndInstancesInOneRequest() async throws {
        let fixture = Fixture()
        let snapshot = try await fixture.control.modelSnapshot(baseURL: fixture.base, modelKey: "loaded-2")
        XCTAssertEqual(snapshot.server, .lmStudio)
        XCTAssertEqual(snapshot.instances, ["loaded-2"])
        XCTAssertEqual(fixture.requests.count, 1, "Readiness must not fetch the same inventory twice")
        let missing = try await fixture.control.modelSnapshot(baseURL: fixture.base, modelKey: "missing")
        XCTAssertEqual(missing.server, .lmStudio)
        XCTAssertEqual(missing.instances, [])
        XCTAssertEqual(fixture.requests.count, 2, "Each check must observe fresh external model state")
    }

    func testModelSnapshotDoesNotManageAnUnrecognizedServer() async throws {
        let fixture = Fixture(status: 503)
        let snapshot = try await fixture.control.modelSnapshot(baseURL: fixture.base, modelKey: "local-model")
        XCTAssertEqual(snapshot.server, .unmanaged)
        XCTAssertEqual(snapshot.instances, [])
    }

    func testLocalModelLifecycleUsesNativeEndpointsAndExactInstance() async throws {
        let fixture = Fixture()
        let control = fixture.control
        let base = URL(string: "http://localhost:1234/v1?unused=value#fragment")!
        XCTAssertEqual(LMStudioControl.apiRoot(for: base)?.absoluteString, "http://localhost:1234/api/v1")
        let kind = await control.serverKind(baseURL: base)
        XCTAssertEqual(kind, .lmStudio)
        let all = try await control.instances(baseURL: base, modelKey: "local-model")
        XCTAssertEqual(all, ["loaded-1", "loaded-2"])
        let byInstance = try await control.instances(baseURL: base, modelKey: "loaded-2")
        XCTAssertEqual(byInstance, ["loaded-2"], "Selecting a specific instance must not unload a sibling")
        let missing = try await control.instances(baseURL: base, modelKey: "not-downloaded")
        XCTAssertEqual(missing, [])
        let loaded = try await control.load(baseURL: base, modelKey: "local-model")
        XCTAssertEqual(loaded, "loaded-3")
        try await control.unload(baseURL: base, instanceID: loaded)
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 6)
        let load = try XCTUnwrap(requests.first { $0.url?.path == "/api/v1/models/load" })
        let loadBody = try body(load)
        XCTAssertEqual(load.httpMethod, "POST")
        XCTAssertEqual(loadBody["model"] as? String, "local-model")
        XCTAssertEqual(loadBody["context_length"] as? Int, LMStudioControl.dictationContextLength)
        let unload = try XCTUnwrap(requests.last)
        XCTAssertEqual(try body(unload)["instance_id"] as? String, "loaded-3")
    }

    func testUnloadHTTPFailureDoesNotReportSuccess() async throws {
        let fixture = Fixture(status: 500)
        do {
            try await fixture.control.unload(baseURL: fixture.base, instanceID: "loaded-1")
            XCTFail("A failed unload must remain retryable")
        } catch RefinerError.http(let status, _) { XCTAssertEqual(status, 500) }
    }

    func testInstancesRejectsServerFailureEvenWhenBodyLooksValid() async throws {
        let fixture = Fixture(status: 503)
        do {
            _ = try await fixture.control.instances(baseURL: fixture.base, modelKey: "local-model")
            XCTFail("A server error cannot establish loaded model state")
        } catch RefinerError.http(let status, _) { XCTAssertEqual(status, 503) }
    }

    func testLoadFailureIsReportedAndServerDetectionRemainsUnmanaged() async throws {
        let fixture = Fixture(status: 500)
        let kind = await fixture.control.serverKind(baseURL: fixture.base)
        XCTAssertEqual(kind, .unmanaged)
        do {
            _ = try await fixture.control.load(baseURL: fixture.base, modelKey: "local-model")
            XCTFail("Expected HTTP failure")
        } catch RefinerError.http(let status, _) { XCTAssertEqual(status, 500) }
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        var bytes = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private final class Fixture: Sendable {
        let base = URL(string: "http://localhost:1234/v1")!
        let control: LMStudioControl
        private let id = UUID().uuidString
        private let state: LMStudioFixtureProtocol.State
        var requests: [URLRequest] { state.requests.value }

        init(status: Int = 200) {
            state = LMStudioFixtureProtocol.State(status: status)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [LMStudioFixtureProtocol.self]
            config.httpAdditionalHeaders = ["X-Airdraft-Fixture": id]
            let fixtureID = id
            let fixtureState = state
            LMStudioFixtureProtocol.states.withLock { $0[fixtureID] = fixtureState }
            control = LMStudioControl(session: URLSession(configuration: config))
        }

        deinit { LMStudioFixtureProtocol.states.withLock { _ = $0.removeValue(forKey: id) } }
    }
}

private final class LMStudioFixtureProtocol: URLProtocol {
    final class State: Sendable {
        let status: Int
        let requests = Locked<[URLRequest]>([])
        init(status: Int) { self.status = status }
    }
    static let states = Locked<[String: State]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: "X-Airdraft-Fixture"),
              let state = Self.states.value[id] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        state.requests.withLock { $0.append(request) }
        let body: String
        switch request.url?.path {
        case "/api/v1/models/load": body = #"{"instance_id":"loaded-3"}"#
        case "/api/v1/models/unload": body = #"{"instance_id":"loaded-3"}"#
        default: body = #"{"models":[{"key":"local-model","loaded_instances":[{"id":"loaded-1"},{"id":"loaded-2"}]},{"key":"other","loaded_instances":[] }]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: state.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
