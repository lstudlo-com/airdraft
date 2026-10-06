import Foundation
import Network
import XCTest
@testable import AirdraftCore

final class ProviderTransportTests: XCTestCase {
    func testOriginComparisonNormalizesCaseAndDefaultPorts() throws {
        for (source, destination) in [
            ("HTTP://EXAMPLE.TEST/a", "http://example.test:80/b"),
            ("https://example.test:443/a", "https://EXAMPLE.TEST/b"),
            ("https://[::1]:8443/a", "https://[::1]:8443/b"),
        ] {
            XCTAssertTrue(ProviderTransport.allowsRedirect(from: URL(string: source), to: URL(string: destination)))
        }
        for destination in ["https://other.test/b", "https://example.test:444/b", "http://example.test/b",
                            "file:///tmp/example", "/relative-without-base"] {
            XCTAssertFalse(ProviderTransport.allowsRedirect(from: URL(string: "https://example.test/a"),
                                                            to: URL(string: destination)), destination)
        }
        XCTAssertFalse(ProviderTransport.allowsRedirect(from: nil, to: URL(string: "https://example.test")))
    }

    func testRelativeSameOrigin307And308PreserveHarmlessPost() async throws {
        let server = try await TransportServer.start(routes: [
            "/307": .init(status: 307, location: "/destination"),
            "/308": .init(status: 308, location: "/destination"),
        ])
        defer { server.stop() }
        let session = ProviderTransport.makeSession()
        defer { session.invalidateAndCancel() }
        for path in ["307", "308"] {
            let (_, response) = try await session.data(for: markerRequest(server.url(path)))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
        let destinations = server.requests.filter { $0.path == "/destination" }
        XCTAssertEqual(destinations.count, 2)
        for request in destinations {
            XCTAssertEqual(request.method, "POST")
            XCTAssertTrue(request.headers.lowercased().contains("x-airdraft-audit: harmless-marker"))
            XCTAssertEqual(request.body, Data("harmless synthetic content".utf8))
        }
    }

    func testCrossHostPortAndSchemeRedirectsNeverReachDestination() async throws {
        let destination = try await TransportServer.start()
        defer { destination.stop() }
        let portURL = destination.url("destination")
        let locations = [portURL.absoluteString, "http://localhost:{port}/destination", "https://127.0.0.1:{port}/destination"]
        let routes = locations.enumerated().reduce(into: [String: TransportServer.Response]()) { result, pair in
            for status in [307, 308] { result["/\(pair.offset)-\(status)"] = .init(status: status, location: pair.element) }
        }
        let origin = try await TransportServer.start(routes: routes)
        defer { origin.stop() }
        let session = ProviderTransport.makeSession()
        defer { session.invalidateAndCancel() }
        for path in routes.keys.sorted() {
            let (_, response) = try await session.data(for: markerRequest(origin.url(String(path.dropFirst()))))
            XCTAssertTrue([307, 308].contains((response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        XCTAssertEqual(destination.connectionCount, 0)
        XCTAssertTrue(destination.requests.isEmpty)
        XCTAssertEqual(origin.connectionCount, routes.count, "Host/scheme redirects must not open another connection")
        XCTAssertEqual(origin.requests.count, routes.count)
    }

    func testCacheAndCookieStateAreNotRetained() async throws {
        let server = try await TransportServer.start(routes: ["/cache": .init(status: 200,
            headers: "Cache-Control: public, max-age=600\r\nSet-Cookie: audit=ordinary; Path=/\r\n")])
        defer { server.stop() }
        let session = ProviderTransport.makeSession()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        for _ in 0..<2 { _ = try await session.data(from: server.url("cache")) }
        XCTAssertEqual(server.requests.count, 2, "A cacheable response must still make another request")
        XCTAssertTrue(server.requests.allSatisfy { !$0.headers.lowercased().contains("\r\ncookie:") })
    }

    func testCancellationAndWallClockDeadlineRemainBounded() async throws {
        let server = try await TransportServer.start(routes: ["/wait": .init(status: 200, withholdResponse: true)])
        defer { server.stop() }
        let session = ProviderTransport.makeSession()
        defer { session.invalidateAndCancel() }
        let task = Task { try await session.data(from: server.url("wait")) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transport must throw") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        var request = URLRequest(url: server.url("wait"))
        request.timeoutInterval = 0.1
        let started = Date()
        do {
            _ = try await HTTPDeadline.data(for: request, session: session,
                                            timeoutError: FixtureError.deadline, invalidResponse: FixtureError.invalid)
            XCTFail("Withheld response must time out")
        } catch { XCTAssertEqual(error as? FixtureError, .deadline) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    private enum FixtureError: Error, Equatable { case deadline, invalid }

    private func markerRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("harmless synthetic content".utf8)
        request.setValue("harmless-marker", forHTTPHeaderField: "X-Airdraft-Audit")
        return request
    }
}

/// Loopback HTTP exercises Foundation's real redirect/cache behavior without
/// provider adapters, credentials, app storage, or any audio device.
private final class TransportServer: @unchecked Sendable {
    struct Response: Sendable {
        var status: Int
        var location: String? = nil
        var headers = ""
        var withholdResponse = false
    }
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: String
        let body: Data
    }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "airdraft.test.private-transport")
    private let lock = NSLock()
    private let routes: [String: Response]
    private var connections: [NWConnection] = []
    private var received: [Request] = []
    private var accepted = 0
    private var started = false
    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return received }
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return accepted }

    private init(routes: [String: Response]) throws {
        self.routes = routes
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    static func start(routes: [String: Response] = [:]) async throws -> TransportServer {
        let server = try TransportServer(routes: routes)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.listener.stateUpdateHandler = { state in
                guard !server.started else { return }
                if case .ready = state { server.started = true; continuation.resume() }
                if case .failed(let error) = state { server.started = true; continuation.resume(throwing: error) }
            }
            server.listener.newConnectionHandler = { connection in
                server.connections.append(connection)
                server.lock.lock(); server.accepted += 1; server.lock.unlock()
                connection.start(queue: server.queue)
                server.receive(connection, bytes: Data())
            }
            server.listener.start(queue: server.queue)
        }
        return server
    }

    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            var bytes = bytes
            bytes.append(data ?? Data())
            guard bytes.count < 65_536, error == nil else { connection.cancel(); return }
            guard let divider = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if !complete { self.receive(connection, bytes: bytes) }
                return
            }
            let headers = String(decoding: bytes[..<divider.lowerBound], as: UTF8.self)
            let fields = headers.components(separatedBy: "\r\n")
            let length = fields.first(where: { $0.lowercased().hasPrefix("content-length:") })
                .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = Data(bytes[divider.upperBound...])
            guard body.count >= length else {
                if !complete { self.receive(connection, bytes: bytes) }
                return
            }
            let start = (fields.first ?? "").split(separator: " ").map(String.init)
            guard start.count >= 2 else { connection.cancel(); return }
            let request = Request(method: start[0], path: start[1], headers: headers, body: body)
            self.lock.lock(); self.received.append(request); self.lock.unlock()
            let response = self.routes[request.path] ?? Response(status: 200)
            guard !response.withholdResponse else { return }
            let location = response.location.map {
                "Location: \($0.replacingOccurrences(of: "{port}", with: String(self.listener.port!.rawValue)))\r\n"
            } ?? ""
            let reply = "HTTP/1.1 \(response.status) Fixture\r\n\(location)\(response.headers)Content-Length: 2\r\nConnection: close\r\n\r\nOK"
            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/\(path)")! }
    func stop() {
        queue.async { self.listener.cancel(); self.connections.forEach { $0.cancel() }; self.connections.removeAll() }
    }
}
