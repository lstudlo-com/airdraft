import Foundation
import os
import XCTest
@testable import AirdraftCore

final class RefinerCompatibilityTests: XCTestCase {
    func testConfirmedLocalPrefixPrewarmingKeepsFinalPromptAndOutputBudget() async throws {
        let fixture = RefinerCompatibilityFixture(mode: .supported, loopback: true)
        defer { fixture.close() }
        let refiner = fixture.chat()
        let prepared = try await refiner.prepare(fixture.request(transcript: ""), backend: .lmStudio, owner: UUID())
        XCTAssertTrue(fixture.bodies.isEmpty, "Required preparation must never wait for speculative prefill")
        try await prepared.prewarmPrompt(fixture.request(transcript: ""), backend: .lmStudio)
        XCTAssertEqual(fixture.bodies.count, 1)
        XCTAssertEqual(fixture.bodies[0]["max_tokens"] as? Int, 1)
        let result = try await prepared.refine(fixture.request())
        XCTAssertEqual(result.text, "Complete original words")
        XCTAssertEqual(fixture.bodies.count, 2, "One speculative prefix request and one complete refinement")
        XCTAssertNil(fixture.bodies[1]["max_tokens"], "The eventual refinement remains unlimited")
        let warmMessages = try XCTUnwrap(fixture.bodies[0]["messages"] as? [[String: String]])
        let finalMessages = try XCTUnwrap(fixture.bodies[1]["messages"] as? [[String: String]])
        XCTAssertEqual(warmMessages[0], finalMessages[0], "Preparation must reuse the exact selected system prompt")
        XCTAssertFalse(warmMessages[1]["content"]?.contains("Complete original words") == true)
        XCTAssertTrue(finalMessages[1]["content"]?.contains("Complete original words") == true)
        for option in ["temperature", "reasoning_effort", "chat_template_kwargs"] {
            XCTAssertEqual(String(describing: fixture.bodies[0][option]), String(describing: fixture.bodies[1][option]))
        }
    }

    func testUnmanagedAndCloudProvidersNeverReceiveSpeculativeRequests() async throws {
        let fixture = RefinerCompatibilityFixture(mode: .supported, loopback: true)
        defer { fixture.close() }
        try await fixture.chat().prewarmPrompt(fixture.request(transcript: ""), backend: .unmanaged)
        for provider in [LLMProviderKind.openAI, .openRouter, .groq, .cerebras] {
            let refiner = OpenAICompatibleRefiner(baseURL: fixture.url, model: "fixture", apiKey: nil,
                                                provider: provider, session: fixture.session)
            try await refiner.prewarmPrompt(fixture.request(transcript: ""), backend: .lmStudio)
        }
        try await fixture.chat().prewarmPrompt(fixture.request(), backend: .lmStudio)
        XCTAssertTrue(fixture.bodies.isEmpty, "Only an empty transcript and a confirmed managed local server allow prefill")
        let remote = RefinerCompatibilityFixture(mode: .supported)
        defer { remote.close() }
        try await remote.chat().prewarmPrompt(remote.request(transcript: ""), backend: .lmStudio)
        XCTAssertTrue(remote.bodies.isEmpty, "A recognized remote/LAN server must not receive extra inference")
        _ = try await remote.chat().refine(remote.request())
        XCTAssertEqual(remote.bodies.count, 1, "The configured remote server remains available for normal refinement")
    }

    func testFailedLocalWarmupStillAllowsNormalCompleteRefinement() async throws {
        let fixture = RefinerCompatibilityFixture(mode: .supported, loopback: true)
        fixture.failWarm = true
        defer { fixture.close() }
        let refiner = fixture.chat()
        try await refiner.prewarmPrompt(fixture.request(transcript: ""), backend: .lmStudio)
        let result = try await refiner.refine(fixture.request())
        XCTAssertEqual(result.text, "Complete original words")
        XCTAssertEqual(fixture.bodies.count, 2)
        XCTAssertNil(fixture.bodies[1]["max_tokens"])
    }

    func testCancellingInFlightLocalWarmupCannotContinueAfterCancellation() async throws {
        let fixture = RefinerCompatibilityFixture(mode: .supported, loopback: true)
        fixture.withholdWarm = true
        defer { fixture.close() }
        let task = Task {
            try await fixture.chat().prewarmPrompt(fixture.request(transcript: ""), backend: .lmStudio)
        }
        for _ in 0..<200 where fixture.bodies.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(fixture.bodies.count, 1, "Warmup must start before cancellation")
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled prefix work must report cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(fixture.bodies.count, 1, "Cancellation must not retry or start final inference")
    }

    func testRepeatedUnsupportedOptionsNegotiateOnceWithoutChangingWords() async throws {
        let fixture = RefinerCompatibilityFixture()
        defer { fixture.close() }
        var refiner = fixture.chat()
        refiner.compatibility = RefinerCompatibility()
        let first = try await refiner.refine(fixture.request())
        XCTAssertEqual(first.text, "Complete original words")
        XCTAssertEqual(fixture.bodies.count, 2)
        let second = try await refiner.refine(fixture.request(transcript: "Different original words"))
        XCTAssertEqual(second.text, "Complete original words")
        XCTAssertEqual(fixture.bodies.count, 3, "The next request skips the previously rejected options")
        XCTAssertNotNil(fixture.bodies[0]["temperature"])
        XCTAssertNil(fixture.bodies[1]["temperature"])
        XCTAssertNil(fixture.bodies[2]["temperature"])
        let messages = try XCTUnwrap(fixture.bodies[2]["messages"] as? [[String: String]])
        XCTAssertTrue(messages[1]["content"]?.contains("Different original words") == true)
    }

    func testFailedMinimalAndIncompleteResultsDoNotTeachCompatibility() async throws {
        for mode in [RefinerCompatibilityFixture.Mode.failure, .incomplete] {
            let fixture = RefinerCompatibilityFixture(mode: mode)
            defer { fixture.close() }
            var refiner = fixture.chat()
            refiner.compatibility = RefinerCompatibility()
            for _ in 0..<2 {
                do { _ = try await refiner.refine(fixture.request()); XCTFail("Expected a failed result") }
                catch RefinerError.http {}
                catch RefinerError.incompleteOutput {}
            }
            XCTAssertEqual(fixture.bodies.count, 4, "Both requests must try the full contract")
            XCTAssertNotNil(fixture.bodies[2]["temperature"])
        }
    }

    func testExpiryAndChangedModelOptionsOrEndpointRetryFullContract() async throws {
        let time = OSAllocatedUnfairLock(initialState: 0.0)
        let compatibility = RefinerCompatibility(lifetime: 10, clock: { time.withLock { $0 } })
        let fixture = RefinerCompatibilityFixture()
        defer { fixture.close() }
        var refiner = fixture.chat()
        refiner.compatibility = compatibility
        _ = try await refiner.refine(fixture.request())
        _ = try await refiner.refine(fixture.request())
        XCTAssertEqual(fixture.bodies.count, 3)
        time.withLock { $0 = 10 }
        fixture.mode = .supported
        _ = try await refiner.refine(fixture.request())
        XCTAssertEqual(fixture.bodies.count, 4)
        XCTAssertNotNil(fixture.bodies[3]["temperature"], "Expiry must discover new server support")

        fixture.mode = .unsupported
        for changed in [fixture.chat(model: "another-model"), fixture.chat(temperature: 0.6), fixture.chat(effort: .high)] {
            var changed = changed
            changed.compatibility = compatibility
            let count = fixture.bodies.count
            _ = try await changed.refine(fixture.request())
            XCTAssertEqual(fixture.bodies.count, count + 2)
        }
        let other = RefinerCompatibilityFixture()
        defer { other.close() }
        var anotherEndpoint = other.chat()
        anotherEndpoint.compatibility = compatibility
        _ = try await anotherEndpoint.refine(other.request())
        XCTAssertEqual(other.bodies.count, 2)
    }

    func testCacheCapacityIsBoundedAndWireIsIsolated() async throws {
        let time = OSAllocatedUnfairLock(initialState: 0.0)
        let cache = RefinerCompatibility(capacity: 2, clock: { time.withLock { $0 } })
        let endpoint = URL(string: "https://fixture.invalid/v1")!
        func key(_ model: String, wire: String = "chat") throws -> RefinerCompatibility.Key {
            try .init(endpoint: endpoint, wire: wire, model: model, options: ["temperature": 0.2])
        }
        let first = try key("first"), second = try key("second"), third = try key("third")
        await cache.recordSuccess(first)
        time.withLock { $0 = 1 }
        await cache.recordSuccess(second)
        time.withLock { $0 = 2 }
        await cache.recordSuccess(third)
        let evicted = await cache.prefersMinimal(first)
        let retained = await cache.prefersMinimal(second)
        let anotherWire = await cache.prefersMinimal(try key("second", wire: "messages"))
        XCTAssertFalse(evicted)
        XCTAssertTrue(retained)
        XCTAssertFalse(anotherWire)
    }

    func testCachedMinimalFailureRetriesFullContractAndForgetsPreference() async throws {
        let fixture = RefinerCompatibilityFixture()
        defer { fixture.close() }
        var refiner = fixture.chat()
        refiner.compatibility = RefinerCompatibility()
        _ = try await refiner.refine(fixture.request())
        fixture.mode = .requiresOptions
        _ = try await refiner.refine(fixture.request())
        XCTAssertEqual(fixture.bodies.count, 4)
        XCTAssertNil(fixture.bodies[2]["temperature"])
        XCTAssertNotNil(fixture.bodies[3]["temperature"])
        _ = try await refiner.refine(fixture.request())
        XCTAssertEqual(fixture.bodies.count, 5)
        XCTAssertNotNil(fixture.bodies[4]["temperature"])
    }

    func testInvalidCachedResultForgetsPreferenceWithoutAnotherInference() async throws {
        for mode in [RefinerCompatibilityFixture.Mode.incomplete, .malformed] {
            let fixture = RefinerCompatibilityFixture()
            defer { fixture.close() }
            var refiner = fixture.chat()
            refiner.compatibility = RefinerCompatibility()
            _ = try await refiner.refine(fixture.request())
            fixture.mode = mode
            do { _ = try await refiner.refine(fixture.request()); XCTFail("Expected an invalid response") }
            catch RefinerError.incompleteOutput {}
            catch RefinerError.invalidResponse {}
            XCTAssertEqual(fixture.bodies.count, 3, "Never repeat inference after an incomplete response")
            fixture.mode = .unsupported
            _ = try await refiner.refine(fixture.request())
            XCTAssertEqual(fixture.bodies.count, 5)
            XCTAssertNotNil(fixture.bodies[3]["temperature"], "The next request must renegotiate full options")
        }
    }

    func testCancelledRefinementMakesNoRequestAndCannotLearnPreference() async throws {
        let fixture = RefinerCompatibilityFixture()
        defer { fixture.close() }
        var refiner = fixture.chat()
        refiner.compatibility = RefinerCompatibility()
        let captured = refiner
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await captured.refine(fixture.request())
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertTrue(fixture.bodies.isEmpty)
        _ = try await refiner.refine(fixture.request())
        XCTAssertEqual(fixture.bodies.count, 2)
    }

    func testConcurrentRefinementsReuseNegotiationWithoutSharingPrompts() async throws {
        let fixture = RefinerCompatibilityFixture()
        defer { fixture.close() }
        var refiner = fixture.chat()
        refiner.compatibility = RefinerCompatibility()
        _ = try await refiner.refine(fixture.request())
        let captured = refiner
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let result = try await captured.refine(fixture.request(transcript: "Independent words \(index)"))
                    XCTAssertEqual(result.text, "Complete original words")
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(fixture.bodies.count, 10, "Every subsequent inference sends one fresh request")
        let inputs = try fixture.bodies.dropFirst(2).map { body in
            try XCTUnwrap((body["messages"] as? [[String: String]])?.last?["content"])
        }
        for index in 0..<8 { XCTAssertTrue(inputs.contains { $0.contains("Independent words \(index)") }) }
    }
}

final class RefinerCompatibilityFixture: @unchecked Sendable {
    enum Mode { case unsupported, failure, incomplete, malformed, supported, requiresOptions }
    private struct State {
        var mode: Mode
        var bodies: [[String: Any]] = []
        var failWarm = false
        var withholdWarm = false
    }
    private let state: OSAllocatedUnfairLock<State>
    let url: URL
    let session: URLSession
    private let wire: String
    var bodies: [[String: Any]] { state.withLock { $0.bodies } }
    var mode: Mode { get { state.withLock { $0.mode } } set { state.withLock { $0.mode = newValue } } }
    var failWarm: Bool { get { state.withLock { $0.failWarm } } set { state.withLock { $0.failWarm = newValue } } }
    var withholdWarm: Bool { get { state.withLock { $0.withholdWarm } } set { state.withLock { $0.withholdWarm = newValue } } }

    init(mode: Mode = .unsupported, wire: String = "chat", loopback: Bool = false) {
        self.wire = wire
        let identifier = UUID().uuidString.lowercased()
        url = URL(string: loopback ? "http://localhost:1234/\(identifier)/v1" : "https://\(identifier).invalid/v1")!
        state = OSAllocatedUnfairLock(initialState: State(mode: mode))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RefinerCompatibilityFixtureProtocol.self]
        session = URLSession(configuration: config)
        RefinerCompatibilityFixtureProtocol.fixtures.withLock { $0[url.absoluteString] = self }
    }
    func close() {
        session.invalidateAndCancel()
        RefinerCompatibilityFixtureProtocol.fixtures.withLock { $0[url.absoluteString] = nil }
    }
    func chat(model: String = "fixture", temperature: Double = 0.2, effort: ThinkingEffort = .off) -> OpenAICompatibleRefiner {
        .init(baseURL: url, model: model, apiKey: nil, temperature: temperature, effort: effort, session: session)
    }
    func request(transcript: String = "Complete original words") -> RefineRequest {
        .init(transcript: transcript, profile: RefinementProfile.defaults[0], context: .empty, family: .general, dictionary: [])
    }
    func reply(to request: URLRequest) throws -> (Int, Data) {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let size = stream.read(&buffer, maxLength: buffer.count)
                guard size > 0 else { break }
                bytes.append(contentsOf: buffer.prefix(size))
            }
        }
        let body = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        let (mode, failWarm, withholdWarm) = state.withLock { state in
            state.bodies.append(body)
            return (state.mode, state.failWarm, state.withholdWarm)
        }
        if body["max_tokens"] as? Int == 1 {
            if withholdWarm { throw RefinerCompatibilityFixtureError.withheld }
            if failWarm { return (503, Data("Synthetic warmup unavailable".utf8)) }
        }
        let optional = body[wire == "anthropic" ? "output_config" : wire == "gemini" ? "generationConfig" : "temperature"] != nil
        if mode == .failure || mode == .unsupported && optional || mode == .incomplete && optional || mode == .requiresOptions && !optional {
            return (400, Data(#"{"error":{"message":"Unsupported option"}}"#.utf8))
        }
        if mode == .malformed { return (200, Data("invalid JSON fixture".utf8)) }
        let response: String
        if wire == "anthropic" { response = #"{"content":[{"type":"text","text":"Complete original words"}],"stop_reason":"\#(mode == .incomplete ? "max_tokens" : "end_turn")"}"# }
        else if wire == "gemini" { response = #"{"candidates":[{"content":{"parts":[{"text":"Complete original words"}]},"finishReason":"\#(mode == .incomplete ? "MAX_TOKENS" : "STOP")"}]}"# }
        else { response = "{\"choices\":[{\"message\":{\"content\":\"Complete original words\"},\"finish_reason\":\"\(mode == .incomplete || body["max_tokens"] as? Int == 1 ? "length" : "stop")\"}]}" }
        return (200, Data(response.utf8))
    }
}

private final class RefinerCompatibilityFixtureProtocol: URLProtocol {
    static let fixtures = OSAllocatedUnfairLock(initialState: [String: RefinerCompatibilityFixture]())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let fixture = Self.fixtures.withLock({ fixtures in
                fixtures.first { request.url!.absoluteString.hasPrefix($0.key + "/") }?.value
            }) else { throw URLError(.resourceUnavailable) }
            let (status, data) = try fixture.reply(to: request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch RefinerCompatibilityFixtureError.withheld {}
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private enum RefinerCompatibilityFixtureError: Error { case withheld }
