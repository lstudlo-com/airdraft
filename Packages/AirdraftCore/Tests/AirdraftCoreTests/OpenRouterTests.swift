import XCTest
@testable import AirdraftCore

final class OpenRouterTests: XCTestCase {
    private let model = "google/gemma-4-31b-it"
    private let request = RefineRequest(transcript: "今天開會", profile: RefinementProfile.defaults[0],
                                        context: .empty, family: .general, dictionary: [])

    func testProviderWideComparisonKeepsVariantAndTierMetricsSeparate() throws {
        let endpoints = try OpenRouterCatalog.decode(Data("""
        {"data":{"endpoints":[
          {"name":"Vertex","provider_name":"Google Vertex","tag":"google-vertex","max_completion_tokens":115200},
          {"name":"Vertex US","provider_name":"Google Vertex","tag":"google-vertex/us-central1","max_completion_tokens":8192},
          {"name":"Flex","provider_name":"Google Vertex","tag":"google-vertex/flex","max_completion_tokens":65536},
          {"name":"Priority","provider_name":"Google Vertex","tag":"google-vertex/global/priority","max_completion_tokens":32768},
          {"name":"Other","provider_name":"Other","tag":"google-vertex-other","max_completion_tokens":4096}
        ]}}
        """.utf8))
        let all = OpenRouterCatalog.relatedEndpoints(providerID: "google-vertex", in: endpoints)
        XCTAssertEqual(all.map(\.maxCompletionTokens), [115200, 8192])
        let exact = OpenRouterCatalog.relatedEndpoints(providerID: "google-vertex/us-central1", in: endpoints)
        XCTAssertEqual(exact.map(\.maxCompletionTokens), [8192])
        XCTAssertEqual(OpenRouterCatalog.relatedEndpoints(providerID: "google-vertex/flex", in: endpoints)
            .map(\.maxCompletionTokens), [65536])
        XCTAssertEqual(OpenRouterCatalog.relatedEndpoints(providerID: "google-vertex/global/priority", in: endpoints)
            .map(\.maxCompletionTokens), [32768])
        XCTAssertTrue(OpenRouterCatalog.relatedEndpoints(providerID: "", in: endpoints).isEmpty)
        XCTAssertTrue(OpenRouterCatalog.relatedEndpoints(providerID: "unknown", in: endpoints).isEmpty)
    }

    func testChoicesPersistPerModelAndAcrossProviderSwitches() throws {
        var config = LLMConfig(kind: .openRouter, model: model)
        config.openRouterRouting = OpenRouterRouting(providerID: "deepinfra/turbo")
        config.model = "other/model"
        XCTAssertEqual(config.openRouterRouting, OpenRouterRouting())
        config.openRouterRouting = OpenRouterRouting(providerID: "together", allowFallbacks: true)
        config.select(.groq)
        config = try JSONDecoder().decode(LLMConfig.self, from: JSONEncoder().encode(config))
        config.select(.openRouter)
        XCTAssertEqual(config.model, "other/model")
        XCTAssertEqual(config.openRouterRouting, OpenRouterRouting(providerID: "together", allowFallbacks: true))
        config.model = model
        XCTAssertEqual(config.openRouterRouting, OpenRouterRouting(providerID: "deepinfra/turbo"))
    }

    func testOlderSettingsDefaultToAutomaticWithoutLosingOtherChoices() throws {
        let original = LLMConfig(kind: .openRouter, model: model, thinkingEffort: .medium)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "openRouterRoutingByModel")
        let restored = try JSONDecoder().decode(LLMConfig.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.openRouterRouting, OpenRouterRouting())
    }

    @MainActor
    func testFactoryPassesTheSelectedModelsRouteToRefiner() async throws {
        var config = LLMConfig(kind: .openRouter, model: model)
        config.openRouterRouting = OpenRouterRouting(providerID: "deepinfra/turbo")
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in "test-only" })
        let candidate = await factory.refiner(for: config)
        let refiner = try XCTUnwrap(candidate as? OpenAICompatibleRefiner)
        let route = try XCTUnwrap(refiner.payload(for: request)["provider"] as? [String: Any])
        XCTAssertEqual(route["only"] as? [String], ["deepinfra/turbo"])
        XCTAssertEqual(route["allow_fallbacks"] as? Bool, false)
    }

    func testAutomaticPreferredAndExclusiveRequests() throws {
        for routing in [OpenRouterRouting(), OpenRouterRouting(providerID: "deepinfra/turbo"),
                        OpenRouterRouting(providerID: "deepinfra/turbo", allowFallbacks: true)] {
            let refiner = engine(routing: routing)
            for minimal in [false, true] {
                let body = refiner.payload(for: request, minimal: minimal)
                let route = body["provider"] as? [String: Any]
                if routing.providerID.isEmpty {
                    XCTAssertNil(route)
                } else {
                    XCTAssertEqual(route?["order"] as? [String], ["deepinfra/turbo"])
                    XCTAssertEqual(route?["allow_fallbacks"] as? Bool, routing.allowFallbacks)
                    XCTAssertEqual(route?["only"] as? [String], routing.allowFallbacks ? nil : ["deepinfra/turbo"])
                }
                XCTAssertNil(body["chat_template_kwargs"])
                XCTAssertNil(body["reasoning_effort"])
                if !minimal { XCTAssertEqual((body["reasoning"] as? [String: Bool])?["enabled"], false) }
            }
        }
    }

    func testRoutingNeverLeaksToOtherProviders() {
        for kind in [LLMProviderKind.openAICompatible, .cerebras, .groq, .openAI] {
            let refiner = OpenAICompatibleRefiner(baseURL: URL(string: kind.defaultBaseURL)!, model: "test", apiKey: nil,
                provider: kind, openRouterRouting: OpenRouterRouting(providerID: "deepinfra/turbo"))
            XCTAssertNil(refiner.payload(for: request)["provider"])
        }
    }

    func testEndpointDecodingKeepsVariantsAndActualMetrics() throws {
        let data = Data(#"""
        {"data":{"endpoints":[
          {"name":"DeepInfra | model","provider_name":"DeepInfra","tag":"deepinfra/turbo","status":0,
           "context_length":262144,"max_completion_tokens":16384,"quantization":"fp4",
           "pricing":{"prompt":"0.00000009","completion":0.00000034,"input_cache_read":"0"},
           "throughput_last_30m":{"p50":123.45,"p90":90},"latency_last_30m":{"p50":0.35},"uptime_last_30m":99.8},
          {"name":"DeepInfra | model","provider_name":"DeepInfra","tag":"deepinfra/fp8",
           "pricing":{"prompt":"bad","completion":"-1"},"throughput_last_30m":null,"latency_last_30m":null},
          {"name":"Other","provider_name":"Other","tag":"other","throughput_last_30m":87.5,
           "latency_last_30m":{"p90":1}},
          {"name":"Missing slug","provider_name":"Other","tag":""}
        ]}}
        """#.utf8)
        let endpoints = try OpenRouterCatalog.decode(data)
        XCTAssertEqual(endpoints.count, 3)
        let turbo = try XCTUnwrap(endpoints.first { $0.tag == "deepinfra/turbo" })
        XCTAssertEqual(turbo.title, "DeepInfra · turbo")
        XCTAssertEqual(turbo.throughput?.value, 123.45)
        XCTAssertEqual(turbo.throughput?.isMedian, true)
        XCTAssertEqual(turbo.latency?.value, 0.35)
        XCTAssertEqual(turbo.pricing?.prompt, 0.00000009)
        XCTAssertEqual(turbo.pricing?.cachedInput, 0)
        XCTAssertEqual(turbo.pricing?.completion, 0.00000034)
        XCTAssertEqual(turbo.contextLength, 262144)
        XCTAssertEqual(turbo.maxCompletionTokens, 16384)
        XCTAssertEqual(turbo.quantization, "fp4")
        XCTAssertEqual(turbo.uptime, 99.8)
        let fp8 = try XCTUnwrap(endpoints.first { $0.tag == "deepinfra/fp8" })
        XCTAssertNil(fp8.throughput)
        XCTAssertNil(fp8.pricing?.prompt)
        XCTAssertNil(fp8.pricing?.completion)
        let other = try XCTUnwrap(endpoints.first { $0.tag == "other" })
        XCTAssertEqual(other.throughput?.value, 87.5)
        XCTAssertEqual(other.throughput?.isMedian, false)
        XCTAssertNil(other.latency?.value)
    }

    func testCatalogURLsPreserveFreeVariantAndNormalizeRoutingAliases() throws {
        let url = try OpenRouterCatalog.endpointsURL(model: model)
        XCTAssertEqual(url.absoluteString, "https://openrouter.ai/api/v1/models/google/gemma-4-31b-it/endpoints")
        XCTAssertEqual(try OpenRouterCatalog.endpointsURL(model: model + ":nitro"), url)
        XCTAssertTrue(try OpenRouterCatalog.endpointsURL(model: model + ":free").absoluteString.contains(":free/endpoints"))
        for invalid in ["", "no-author", "a/b/c", "../model", "a/b?query=1"] {
            XCTAssertThrowsError(try OpenRouterCatalog.endpointsURL(model: invalid))
        }
    }

    func test400RetryPreservesRestrictionAndReportsSelectedHost() async throws {
        let session = session(statuses: [400, 200])
        defer { session.invalidateAndCancel() }
        let result = try await engine(routing: OpenRouterRouting(providerID: "deepinfra/turbo"), session: session).refine(request)
        XCTAssertEqual(result.servedBy, "DeepInfra")
        XCTAssertEqual(OpenRouterTestProtocol.requests.count, 2)
        for request in OpenRouterTestProtocol.requests {
            let data = try body(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let provider = try XCTUnwrap(json["provider"] as? [String: Any])
            XCTAssertEqual(provider["only"] as? [String], ["deepinfra/turbo"])
            XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenRouter-Metadata"), "enabled")
        }
        let retry = try XCTUnwrap(JSONSerialization.jsonObject(with: body(OpenRouterTestProtocol.requests[1])) as? [String: Any])
        XCTAssertEqual(Set(retry.keys), ["model", "messages", "stream", "provider"])
    }

    func testModelAndUndocumentedProviderFieldDoNotPretendToVerifyHost() async throws {
        let session = session(statuses: [200])
        defer { session.invalidateAndCancel() }
        OpenRouterTestProtocol.reply = #"{"model":"google/gemma-4-31b-it","provider":"WrongHost","choices":[{"finish_reason":"stop","message":{"content":"今天開會。"}}]}"#
        let result = try await engine(routing: OpenRouterRouting(providerID: "deepinfra/turbo"), session: session).refine(request)
        XCTAssertNil(result.servedBy)
    }

    func testMetadataReportsSelectedFallbackRatherThanPreferredHost() async throws {
        let session = session(statuses: [200])
        defer { session.invalidateAndCancel() }
        OpenRouterTestProtocol.reply = #"{"model":"google/gemma-4-31b-it","openrouter_metadata":{"endpoints":{"available":[{"provider":"DeepInfra","selected":false},{"provider":"Together","selected":true}]}},"choices":[{"finish_reason":"stop","message":{"content":"今天開會。"}}]}"#
        let result = try await engine(routing: OpenRouterRouting(providerID: "deepinfra/turbo", allowFallbacks: true), session: session).refine(request)
        XCTAssertEqual(result.servedBy, "Together")
        let requestBody = try XCTUnwrap(JSONSerialization.jsonObject(with: body(try XCTUnwrap(OpenRouterTestProtocol.requests.first))) as? [String: Any])
        let provider = try XCTUnwrap(requestBody["provider"] as? [String: Any])
        XCTAssertEqual(provider["order"] as? [String], ["deepinfra/turbo"])
        XCTAssertNil(provider["only"])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, true)
    }

    func testUnavailableHostFailsWithoutRetryingThroughAnotherProvider() async throws {
        let session = session(statuses: [503])
        defer { session.invalidateAndCancel() }
        do {
            _ = try await engine(routing: OpenRouterRouting(providerID: "deepinfra/turbo"), session: session).refine(request)
            XCTFail("Unavailable host must fail refinement")
        } catch RefinerError.http(let status, _) { XCTAssertEqual(status, 503) }
        XCTAssertEqual(OpenRouterTestProtocol.requests.count, 1)
    }

    func testEndpointDiscoverySendsNoKeyOrTranscriptAndPropagatesErrors() async throws {
        let session = session(statuses: [200, 404])
        defer { session.invalidateAndCancel() }
        OpenRouterTestProtocol.reply = #"{"data":{"endpoints":[]}}"#
        let endpoints = try await OpenRouterCatalog.fetch(model: model, session: session)
        XCTAssertTrue(endpoints.isEmpty)
        let request = try XCTUnwrap(OpenRouterTestProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
        do {
            _ = try await OpenRouterCatalog.fetch(model: model, session: session)
            XCTFail("404 must not look like an empty successful catalog")
        } catch RefinerError.http(let status, _) { XCTAssertEqual(status, 404) }
    }

    private func engine(routing: OpenRouterRouting, session: URLSession = .shared) -> OpenAICompatibleRefiner {
        OpenAICompatibleRefiner(baseURL: URL(string: LLMProviderKind.openRouter.defaultBaseURL)!, model: model,
            apiKey: "test-only", provider: .openRouter, openRouterRouting: routing, session: session)
    }

    private func session(statuses: [Int]) -> URLSession {
        OpenRouterTestProtocol.requests = []
        OpenRouterTestProtocol.statuses = statuses
        OpenRouterTestProtocol.reply = #"{"model":"google/gemma-4-31b-it","openrouter_metadata":{"endpoints":{"available":[{"provider":"DeepInfra","selected":true}]}},"choices":[{"finish_reason":"stop","message":{"content":"今天開會。"}}]}"#
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenRouterTestProtocol.self]
        return URLSession(configuration: config)
    }

    private func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class OpenRouterTestProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var statuses: [Int] = []
    static var reply = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
            captured.httpBody = data
        }
        Self.requests.append(captured)
        let status = Self.statuses.isEmpty ? 500 : Self.statuses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
