import Foundation
import XCTest
@testable import AirdraftCore

final class BrowserContextURLTests: XCTestCase {
    func testOnlyOriginSurvivesBrowserURLCapture() {
        let samples = [
            ("https://example.test/docs?q=ordinary#heading", "https://example.test"),
            ("HTTP://EXAMPLE.TEST:8080/a/b", "http://example.test:8080"),
            ("https://example.test:443/", "https://example.test:443"),
            ("https://reader:label@example.test/private", "https://example.test"),
            ("https://example.test/文件/%E6%96%87?q=ordinary", "https://example.test"),
            ("https://[::1]:8443/docs#heading", "https://[::1]:8443"),
            ("http://localhost:1234/v1", "http://localhost:1234"),
        ]
        for (input, expected) in samples {
            XCTAssertEqual(BrowserContextURL.origin(from: input), expected, input)
        }
    }

    func testMalformedAndNonWebURLsDoNotBecomeContext() {
        for value in ["", "file:///tmp/document", "javascript:example", "https:///missing",
                      "httpstuff://example.test", "//example.test/docs", "https://",
                      "https://bad host/docs", "https://example.test:0/", "https://example.test:65536/",
                      "https://example.test/\nprivate"] {
            XCTAssertNil(BrowserContextURL.origin(from: value), value)
        }
    }

    func testOriginKeepsClassificationAndReachesPromptAndHistoryWithoutURLState() throws {
        let context = AppContext(appName: "Browser",
            url: BrowserContextURL.origin(from: "https://docs.google.com:443/document/ordinary?q=sample#section"))
        XCTAssertEqual(AppFamily.classify(context), .document)
        let request = RefineRequest(transcript: "Example sentence.",
            profile: try XCTUnwrap(RefinementProfile.defaultProfile(id: RefinementProfile.cleanID)),
            context: context, family: AppFamily.classify(context), dictionary: [])
        let prompt = PromptBuilder.userMessage(for: request)
        XCTAssertTrue(prompt.contains("url: https://docs.google.com:443\n"))
        let record = DictationRecord(url: context.url, mode: "Clean", family: "document",
            rawTranscript: "Example sentence.", refinedText: "Example sentence.", finalText: "Example sentence.",
            asrEngine: "fixture", audioSeconds: 0, asrMs: 0, llmMs: 0, inserted: false)
        let saved = try JSONDecoder().decode(DictationRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(saved.url, "https://docs.google.com:443")
        for text in [prompt, try XCTUnwrap(saved.url)] {
            XCTAssertFalse(text.contains("/document/ordinary"))
            XCTAssertFalse(text.contains("q=sample"))
            XCTAssertFalse(text.contains("#section"))
        }
        XCTAssertNil(AppContext.empty.url)
    }
}
