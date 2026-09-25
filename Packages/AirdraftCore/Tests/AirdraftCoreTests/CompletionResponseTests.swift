import XCTest
@testable import AirdraftCore

final class CompletionResponseTests: XCTestCase {
    func testTruncatedProviderResponsesAreRejectedBeforeReturningText() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CompletionFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://fixture.invalid/v1")!
        let cases: [(any Refiner, String, String)] = [
            (OpenAICompatibleRefiner(baseURL: url, model: "test", apiKey: "fixture", session: session),
             #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#, "length"),
            (AnthropicRefiner(baseURL: url, model: "test", apiKey: "fixture", session: session),
             #"{"content":[{"type":"text","text":"partial"}],"stop_reason":"max_tokens"}"#, "max_tokens"),
            (GeminiRefiner(baseURL: url, model: "test", apiKey: "fixture", session: session),
             #"{"candidates":[{"content":{"parts":[{"text":"partial"}]},"finishReason":"MAX_TOKENS"}]}"#, "MAX_TOKENS"),
        ]
        let request = RefineRequest(transcript: "Complete original words", profile: RefinementProfile.defaults[0],
                                    context: .empty, family: .general, dictionary: [])
        for (refiner, body, _) in cases {
            CompletionFixtureProtocol.body = body
            do { _ = try await refiner.refine(request); XCTFail("Must reject partial output") }
            catch RefinerError.incompleteOutput {}
        }
    }
}

private final class CompletionFixtureProtocol: URLProtocol {
    static var body = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
