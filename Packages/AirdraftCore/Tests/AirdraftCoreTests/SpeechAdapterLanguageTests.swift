import XCTest
@testable import AirdraftCore

final class SpeechAdapterLanguageTests: XCTestCase {
    func testAppleLanguageNeverFallsBackToUnrelatedSavedLocale() {
        XCTAssertEqual(ASRConfig(kind: .apple, appleLocale: "zh-TW", language: "fr").effectiveAppleLocale, "fr")
        XCTAssertEqual(ASRConfig(kind: .apple, appleLocale: "zh-TW", language: "en_GB").effectiveAppleLocale, "en-GB")
        XCTAssertEqual(ASRConfig(kind: .apple, appleLocale: "zh-TW", language: "").effectiveAppleLocale, "zh-TW")
        XCTAssertEqual(ASRConfig(kind: .apple, appleLocale: "en-US", language: "zh").effectiveAppleLocale, "zh-TW")
    }

    func testQwenUsesOfficialLanguageNamesAndPreservesAuto() throws {
        for (code, expected) in [("zh", "Chinese"), ("en-US", "English"), ("yue", "Cantonese"), ("tl", "Filipino")] {
            let options = try Qwen3ASRTranscriber.decodingOptions(for: .init(language: code))
            XCTAssertEqual(options.language, expected)
            XCTAssertEqual(options.maxTokens, 1024)
        }
        let automatic = try Qwen3ASRTranscriber.decodingOptions(for: .init(chineseScript: .traditional))
        XCTAssertNil(automatic.language)
        XCTAssertNil(automatic.context, "Auto must not acquire a Chinese script prompt")
        XCTAssertThrowsError(try Qwen3ASRTranscriber.decodingOptions(for: .init(language: "unknown")))
        XCTAssertThrowsError(try Qwen3ASRTranscriber.decodingOptions(for: .init(language: "uk")))
        XCTAssertEqual(try Qwen3ASRTranscriber.decodingOptions(for: .init(language: "uk"), allowUnverifiedLanguage: true).language, "Ukrainian")
    }

    func testDeepgramPreservesCantoneseAndRejectsChineseMultilingual() throws {
        XCTAssertEqual(try DeepgramTranscriber.requestLanguage(model: "nova-3", hints: .init(language: "yue")), "zh-HK")
        XCTAssertEqual(try DeepgramTranscriber.requestLanguage(model: "nova-3", hints: .init(language: "zh", chineseScript: .traditional)), "zh-TW")
        XCTAssertEqual(try DeepgramTranscriber.requestLanguage(model: "whisper-large", hints: .init(language: "zh", chineseScript: .traditional)), "zh")
        XCTAssertNil(try DeepgramTranscriber.requestLanguage(model: "nova-3", hints: .init()))
        XCTAssertEqual(try DeepgramTranscriber.requestLanguage(model: "nova-3-multilingual", hints: .init()), "multi")
        XCTAssertThrowsError(try DeepgramTranscriber.requestLanguage(model: "nova-3-multilingual", hints: .init(language: "zh")))
    }

    func testCohereRejectsAutoBeforeLoadingWeights() async {
        let engine = CohereTranscriber(modelId: "fixture/absent-cohere")
        do {
            _ = try await engine.transcribe(samples: [0.1], hints: .init())
            XCTFail("Auto must not become an English prompt")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("language"))
            XCTAssertFalse(error is TranscriberError, "Language validation must precede model loading")
        }
    }
}

/// Offline cloud fixtures use synthetic keys and stay outside the credential-free allowlist.
final class SpeechCloudLanguageTests: XCTestCase {
    func testDeepgramRegionalLanguageReachesRequestAfterPolicyResolution() throws {
        let engine = DeepgramTranscriber(model: "nova-3", apiKey: "fixture-key")
        for language in ["en-GB", "fr-CA", "pt-PT", "nl-BE", "de-CH", "es-419", "zh-Hant", "zh-CN"] {
            let resolved = try SpeechLanguagePolicy.resolve(ASRConfig(kind: .deepgram, model: "nova-3", language: language))
            let hints = TranscriptionHints(language: resolved.language, chineseScript: .traditional)
            let request = try engine.makeRequest(samples: [0.1], hints: hints)
            let query = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first(where: { $0.name == "language" })?.value, language)
            XCTAssertFalse(query.contains(where: { $0.name == "detect_language" }))
        }
    }

    func testDeepgramMetadataUsesAppliedOrDetectedLanguageInsteadOfIgnoredHints() async throws {
        let session = responseSession()
        defer { session.invalidateAndCancel() }
        for (model, language, expected) in [
            ("nova-3-multilingual", "en", nil as String?),
            ("nova-3", "", nil),
            ("nova-3", "fr-CA", "fr-CA")
        ] {
            let engine = DeepgramTranscriber(model: model, apiKey: "fixture-key", session: session)
            let transcript = try await engine.transcribe(samples: [0.1], hints: .init(language: language))
            XCTAssertEqual(transcript.text, "fixture")
            XCTAssertEqual(transcript.language, expected, model)
        }
        let detectedSession = responseSession(protocolClass: SpeechDetectedLanguageResponseProtocol.self)
        defer { detectedSession.invalidateAndCancel() }
        let detected = try await DeepgramTranscriber(model: "nova-3-multilingual", apiKey: "fixture-key", session: detectedSession)
            .transcribe(samples: [0.1], hints: .init(language: "en"))
        XCTAssertEqual(detected.language, "fr", "An actual detection takes precedence over the ignored hint")
    }

    func testOpenRouterMetadataMatchesLanguageActuallySent() async throws {
        let session = responseSession()
        defer { session.invalidateAndCancel() }
        for (model, language, expected) in [
            ("fish-audio/transcribe-1", "zh", nil as String?),
            ("fish-audio/transcribe-1-pro", "zh", nil),
            ("nvidia/parakeet-tdt-0.6b-v3", "en", nil),
            ("qwen/qwen3-asr-1.7b", "zh-TW", "zh"),
            ("qwen/qwen3-asr-1.7b", "", nil),
            ("custom/unverified", "uk-UA", "uk")
        ] {
            let engine = OpenRouterTranscriber(model: model, apiKey: "fixture-key", session: session)
            let hints = TranscriptionHints(language: language)
            let request = try engine.makeRequest(samples: [0.1], hints: hints)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["language"] as? String, expected, model)
            let transcript = try await engine.transcribe(samples: [0.1], hints: hints)
            XCTAssertEqual(transcript.text, "fixture")
            XCTAssertEqual(transcript.language, expected, model)
        }
    }

    private func responseSession(protocolClass: URLProtocol.Type = SpeechLanguageResponseProtocol.self) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

/// Every request is answered in process; no shared mutable callback or network.
private class SpeechLanguageResponseProtocol: URLProtocol {
    class var response: String {
        #"{"text":"fixture","results":{"channels":[{"alternatives":[{"transcript":"fixture"}]}]}}"#
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class SpeechDetectedLanguageResponseProtocol: SpeechLanguageResponseProtocol {
    override class var response: String {
        #"{"results":{"channels":[{"detected_language":"fr","alternatives":[{"transcript":"fixture"}]}]}}"#
    }
}
