import XCTest
@testable import AirdraftCore

final class AdditionalCloudSpeechTests: XCTestCase {
    private let samples: [Float] = [0, 0.2, -0.2]
    private let jobID = "22222222-2222-4222-8222-222222222222"
    private let hints = TranscriptionHints(language: "zh-TW", vocabulary: ["Airdraft", "Airdraft", "", "C++"], chineseScript: .traditional)

    override func tearDown() { AdditionalSpeechURLProtocol.handler = nil; super.tearDown() }

    private func session(_ handler: @escaping (URLRequest) throws -> AdditionalSpeechResponse?) -> URLSession {
        AdditionalSpeechURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AdditionalSpeechURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    func testNativeMultipartContractsAndLanguageValidation() throws {
        let cartesia = try CartesiaTranscriber(apiKey: " key ").makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(cartesia.url?.absoluteString, "https://api.cartesia.ai/stt")
        XCTAssertEqual(cartesia.value(forHTTPHeaderField: "Cartesia-Version"), "2026-08-14")
        XCTAssertEqual(cartesia.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        XCTAssertTrue(String(decoding: body(cartesia), as: UTF8.self).contains("\r\nzh\r\n"))
        XCTAssertThrowsError(try CartesiaTranscriber(apiKey: "key").makeRequest(samples: samples, hints: .init())) {
            guard case SpeechLanguageError.automaticUnavailable = $0 else { return XCTFail("\($0)") }
        }
        let xai = try XAITranscriber(apiKey: "key").makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(xai.url?.path, "/v1/stt")
        let xaiBody = String(decoding: body(xai), as: UTF8.self)
        XCTAssertTrue(xaiBody.contains("grok-voice-transcribe-2.0"))
        XCTAssertTrue(xaiBody.contains("name=\"keyterm\"\r\n\r\nC++"))
        XCTAssertLessThan(try XCTUnwrap(xaiBody.range(of: "name=\"keyterm\"")?.lowerBound),
                          try XCTUnwrap(xaiBody.range(of: "name=\"file\"")?.lowerBound))
        let auto = try XAITranscriber(apiKey: "key").makeRequest(samples: samples, hints: .init())
        XCTAssertFalse(String(decoding: body(auto), as: UTF8.self).contains("name=\"language\""))
        let mistral = try MistralTranscriber(apiKey: "key").makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(mistral.url?.absoluteString, "https://api.mistral.ai/v1/audio/transcriptions")
        XCTAssertTrue(String(decoding: body(mistral), as: UTF8.self).contains("voxtral-mini-latest"))
        XCTAssertThrowsError(try MistralTranscriber(apiKey: "key").makeRequest(samples: samples, hints: .init(language: "yue")))
    }

    func testSynchronousRepliesAndHTTPFailures() async throws {
        for kind in [ASRProviderKind.cartesia, .xAI, .mistral] {
            let s = session { _ in .init(body: #"{"type":"transcript","text":"  中文 English  ","language":"zh"}"#) }
            let engine: any Transcriber
            switch kind {
            case .cartesia: engine = CartesiaTranscriber(apiKey: "key", session: s)
            case .xAI: engine = XAITranscriber(apiKey: "key", session: s)
            default: engine = MistralTranscriber(apiKey: "key", session: s)
            }
            let result = try await engine.transcribe(samples: samples, hints: hints)
            XCTAssertEqual(result.text, "中文 English")
            XCTAssertEqual(result.language, "zh")
            XCTAssertEqual(result.engine, ASRConfig(kind: kind).engineID)
            s.invalidateAndCancel()
        }
        let s = session { _ in .init(status: 429, body: "quota") }
        defer { s.invalidateAndCancel() }
        do {
            _ = try await XAITranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: .init())
            XCTFail("Expected HTTP failure")
        } catch TranscriberError.http(let status, _) { XCTAssertEqual(status, 429) }
    }

    func testAllNewAdaptersRejectMissingKeysAndEmptyAudioLocally() async {
        let s = session { _ in XCTFail("Unexpected upload"); return .init(status: 500) }
        defer { s.invalidateAndCancel() }
        for key in [nil, "key"] as [String?] {
            let engines: [any Transcriber] = [AssemblyAITranscriber(apiKey: key, session: s), CartesiaTranscriber(apiKey: key, session: s),
                SpeechmaticsTranscriber(apiKey: key, session: s), XAITranscriber(apiKey: key, session: s),
                MistralTranscriber(apiKey: key, session: s), GeminiTranscriber(apiKey: key, session: s)]
            for engine in engines {
                do {
                    _ = try await engine.transcribe(samples: key == nil ? samples : [], hints: hints)
                    XCTFail("Expected validation failure")
                } catch TranscriberError.missingAPIKey { XCTAssertNil(key) }
                catch TranscriberError.emptyAudio { XCTAssertNotNil(key) }
                catch { XCTFail("\(error)") }
            }
        }
    }

    func testAssemblyPayloadUsesOnlySelectedModelAndMixedLanguageRecognition() throws {
        let engine = AssemblyAITranscriber(apiKey: "key")
        let payload = try engine.payload(audioURL: "https://fixture.invalid/audio", hints: hints)
        XCTAssertEqual(payload["speech_models"] as? [String], ["universal-3-5-pro"])
        XCTAssertEqual(payload["keyterms_prompt"] as? [String], ["Airdraft", "C++"])
        let options = try XCTUnwrap(payload["language_detection_options"] as? [String: Any])
        XCTAssertEqual(options["expected_languages"] as? [String], ["en", "zh"])
        XCTAssertEqual(options["code_switching"] as? Bool, true)
        XCTAssertNil(payload["prompt"])
        XCTAssertThrowsError(try engine.payload(audioURL: "", hints: .init(language: "yue")))
        XCTAssertEqual(SpeechLanguagePolicy.assemblyLanguages.count, 18)
    }

    func testAssemblyBatchCompletesAndDeletesOwnJob() async throws {
        let deleted = expectation(description: "Assembly job deleted")
        let s = session { request in
            XCTAssertEqual(request.url?.host, "api.assemblyai.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "key")
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/v2/transcript/\(self.jobID)"); deleted.fulfill(); return .init()
            }
            switch request.url?.path {
            case "/v2/upload":
                XCTAssertEqual(self.body(request), WAVEncoder.encode(samples: self.samples))
                return .init(body: #"{"upload_url":"https://cdn.assemblyai.com/upload/fixture"}"#)
            case "/v2/transcript": return .init(body: "{\"id\":\"\(self.jobID)\",\"status\":\"queued\"}")
            default: return .init(body: "{\"id\":\"\(self.jobID)\",\"status\":\"completed\",\"text\":\"中文 English\",\"language_code\":\"zh\"}")
            }
        }
        defer { s.invalidateAndCancel() }
        let result = try await AssemblyAITranscriber(apiKey: "key", session: s, pollInterval: 0.01).transcribe(samples: samples, hints: hints)
        XCTAssertEqual(result.text, "中文 English")
        await fulfillment(of: [deleted], timeout: 1)
    }

    func testSpeechmaticsMandarinAndVocabularyPayload() throws {
        let config = try XCTUnwrap(SpeechmaticsTranscriber(apiKey: "key").payload(hints: hints)["transcription_config"] as? [String: Any])
        XCTAssertEqual(config["model"] as? String, "enhanced")
        XCTAssertEqual(config["language"] as? String, "cmn")
        XCTAssertEqual((config["additional_vocab"] as? [[String: String]])?.map { $0["content"]! }, ["Airdraft", "C++"])
        let automatic = try SpeechmaticsTranscriber(apiKey: "key").payload(hints: .init())
        XCTAssertEqual((automatic["transcription_config"] as? [String: Any])?["language"] as? String, "auto")
    }

    func testSpeechmaticsBatchCompletesAndDeletesAudioAndJob() async throws {
        let deleted = expectation(description: "Speechmatics job deleted")
        let s = session { request in
            XCTAssertEqual(request.url?.host, "eu1.asr.api.speechmatics.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, "/v2/jobs/fixture-job")
                XCTAssertEqual(request.url?.query, "force=true"); deleted.fulfill(); return .init()
            }
            if request.httpMethod == "POST" {
                let body = String(decoding: self.body(request), as: UTF8.self)
                XCTAssertTrue(body.contains("name=\"data_file\""))
                XCTAssertTrue(body.contains("Content-Type: application/json"))
                return .init(status: 201, body: #"{"id":"fixture-job"}"#)
            }
            if request.url?.lastPathComponent == "transcript" {
                XCTAssertEqual(request.url?.query, "format=txt"); return .init(body: "  中文 English  ")
            }
            return .init(body: #"{"job":{"id":"fixture-job","status":"done"}}"#)
        }
        defer { s.invalidateAndCancel() }
        let result = try await SpeechmaticsTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: hints)
        XCTAssertEqual(result.text, "中文 English")
        await fulfillment(of: [deleted], timeout: 1)
    }

    func testBatchCancellationStillDeletesOnlyOwnedJob() async throws {
        for kind in [ASRProviderKind.assemblyAI, .speechmatics] {
            let polling = expectation(description: "Poll started"), deleted = expectation(description: "Cancelled job deleted")
            let s = session { request in
                if request.httpMethod == "DELETE" { deleted.fulfill(); return .init() }
                if request.url?.lastPathComponent == "upload" { return .init(body: #"{"upload_url":"https://cdn.assemblyai.com/upload/fixture"}"#) }
                if request.httpMethod == "POST" {
                    return .init(body: kind == .assemblyAI ? "{\"id\":\"\(self.jobID)\",\"status\":\"queued\"}" : #"{"id":"fixture-job"}"#)
                }
                polling.fulfill(); return nil // Hold the poll until cancellation.
            }
            let engine: any Transcriber = kind == .assemblyAI ? AssemblyAITranscriber(apiKey: "key", session: s, pollInterval: 0.01) :
                SpeechmaticsTranscriber(apiKey: "key", session: s, pollInterval: 0.01)
            let task = Task { try await engine.transcribe(samples: samples, hints: hints) }
            await fulfillment(of: [polling], timeout: 2)
            task.cancel()
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
            await fulfillment(of: [deleted], timeout: 1)
            s.invalidateAndCancel()
        }
    }

    func testBatchTimeoutDeletesOwnJob() async {
        let deleted = expectation(description: "Timed out job deleted")
        let s = session { request in
            if request.httpMethod == "DELETE" { deleted.fulfill(); return .init() }
            if request.url?.lastPathComponent == "upload" { return .init(body: #"{"upload_url":"https://cdn.assemblyai.com/upload/fixture"}"#) }
            return .init(body: "{\"id\":\"\(self.jobID)\",\"status\":\"queued\"}")
        }
        defer { s.invalidateAndCancel() }
        do {
            _ = try await AssemblyAITranscriber(apiKey: "key", timeout: 0.04, session: s, pollInterval: 0.01).transcribe(samples: samples, hints: hints)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is TranscriberError) }
        await fulfillment(of: [deleted], timeout: 1)
    }

    func testGeminiUsesVerbatimAndCurrentStepsSchemaAndDeletesFile() async throws {
        let deleted = expectation(description: "Gemini file deleted")
        let s = geminiSession(deleted: deleted, response: #"{"status":"completed","steps":[{"type":"thought","summary":[]},{"type":"model_output","content":[{"type":"text","text":"um 中文 "},{"type":"text","text":"English"}]}]}"#)
        defer { s.invalidateAndCancel() }
        let result = try await GeminiTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: hints)
        XCTAssertEqual(result.text, "um 中文 English")
        await fulfillment(of: [deleted], timeout: 1)
    }

    func testGeminiRejectsPartialOrMalformedTranscriptsAndStillDeletesFile() async {
        for response in [#"{"status":"in_progress","steps":[{"type":"model_output","content":[{"type":"text","text":"partial"}]}]}"#,
                         #"{"status":"completed","steps":[]}"#, #"{"status":"completed","outputs":[{"type":"text","text":"old"}]}"#] {
            let deleted = expectation(description: "Failed Gemini file deleted")
            let s = geminiSession(deleted: deleted, response: response)
            do { _ = try await GeminiTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: hints); XCTFail("Expected invalid response") }
            catch { guard case TranscriberError.invalidResponse = error else { return XCTFail("\(error)") } }
            await fulfillment(of: [deleted], timeout: 1)
            s.invalidateAndCancel()
        }
    }

    func testGeminiCancellationDeletesItsUploadedFile() async {
        let pending = expectation(description: "Gemini interaction pending"), deleted = expectation(description: "Cancelled Gemini file deleted")
        let s = geminiSession(deleted: deleted, response: "", pending: pending)
        defer { s.invalidateAndCancel() }
        let task = Task { try await GeminiTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: hints) }
        await fulfillment(of: [pending], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        await fulfillment(of: [deleted], timeout: 1)
    }

    private func geminiSession(deleted: XCTestExpectation, response: String, pending: XCTestExpectation? = nil) -> URLSession {
        session { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.httpMethod == "DELETE" { XCTAssertEqual(request.url?.path, "/v1beta/files/fixture"); deleted.fulfill(); return .init() }
            if request.url?.path == "/upload/v1beta/files" {
                if request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start" {
                    return .init(headers: ["X-Goog-Upload-URL": "https://generativelanguage.googleapis.com/upload/v1beta/files?upload_id=fixture"])
                }
                XCTAssertEqual(self.body(request), WAVEncoder.encode(samples: self.samples))
                return .init(body: #"{"file":{"name":"files/fixture","uri":"https://generativelanguage.googleapis.com/v1beta/files/fixture","state":"ACTIVE"}}"#)
            }
            XCTAssertEqual(request.url?.path, "/v1beta/interactions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Revision"), "2026-05-20")
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: self.body(request)) as? [String: Any])
            XCTAssertEqual(payload["store"] as? Bool, false)
            XCTAssertEqual(payload["model"] as? String, "gemini-3.5-transcribe")
            let generation = try XCTUnwrap(payload["generation_config"] as? [String: Any])
            let config = try XCTUnwrap(generation["transcription_config"] as? [String: Any])
            XCTAssertEqual((config["mode"] as? [String: String])?["type"], "verbatim")
            XCTAssertEqual(config["custom_vocabulary"] as? [String], ["Airdraft", "C++"])
            XCTAssertEqual(config["language_codes"] as? [String], ["zh"])
            if let pending { pending.fulfill(); return nil }
            return .init(body: response)
        }
    }

    func testGeminiDoesNotForwardKeyToAnUntrustedUploadHost() async {
        let s = session { request in
            XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
            return .init(headers: ["X-Goog-Upload-URL": "https://attacker.invalid/upload"])
        }
        defer { s.invalidateAndCancel() }
        do { _ = try await GeminiTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: hints); XCTFail("Expected rejection") }
        catch { guard case TranscriberError.invalidResponse = error else { return XCTFail("\(error)") } }
    }
}

private struct AdditionalSpeechResponse {
    var status = 200
    var body = "{}"
    var headers: [String: String] = [:]
}

private final class AdditionalSpeechURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var callback: ((URLRequest) throws -> AdditionalSpeechResponse?)?
    static var handler: ((URLRequest) throws -> AdditionalSpeechResponse?)? {
        get { lock.lock(); defer { lock.unlock() }; return callback }
        set { lock.lock(); defer { lock.unlock() }; callback = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            guard let result = try handler(request) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: result.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
