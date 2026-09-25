import XCTest
@testable import AirdraftCore

final class TranscriberWireTests: XCTestCase {
    private let samples: [Float] = [0, 0.2, -0.2]
    private let hints = TranscriptionHints(language: "zh-TW", vocabulary: ["Airdraft", "Airdraft", "", "C++", "bad\nterm", "<bad>"], chineseScript: .traditional)
    private let fileID = "11111111-1111-4111-8111-111111111111"
    private let jobID = "22222222-2222-4222-8222-222222222222"

    override func tearDown() {
        SpeechURLProtocol.handler = nil
        super.tearDown()
    }

    private func session(_ handler: @escaping (URLRequest) throws -> (Int, String)) -> URLSession {
        SpeechURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpeechURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func body(_ request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }

    func testOpenRouterUsesJSONBase64WAVWithoutChatRoutingFields() throws {
        let engine = OpenRouterTranscriber(model: "qwen/qwen3-asr-1.7b", apiKey: " test-key ")
        let request = try engine.makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(engine.id, "openRouter:qwen/qwen3-asr-1.7b")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 75)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen/qwen3-asr-1.7b")
        XCTAssertEqual(json["language"] as? String, "zh")
        XCTAssertNil(json["provider"])
        XCTAssertNil(json["prompt"])
        XCTAssertNil(json["response_format"])
        let audio = try XCTUnwrap(json["input_audio"] as? [String: String])
        XCTAssertEqual(audio["format"], "wav")
        XCTAssertFalse(audio["data"]?.hasPrefix("data:") ?? true)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(audio["data"])), WAVEncoder.encode(samples: samples))
        let auto = try engine.makeRequest(samples: samples, hints: .init())
        let autoJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(auto.httpBody)) as? [String: Any])
        XCTAssertNil(autoJSON["language"])
    }

    func testOpenRouterCatalogFiltersOutputAndPreservesCurrentModelIDs() async throws {
        let s = session { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/models")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
                           [URLQueryItem(name: "output_modalities", value: "transcription")])
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, #"{"data":[{"id":"vendor/new-asr","name":"New ASR","architecture":{"input_modalities":["audio"],"output_modalities":["transcription"]}},{"id":"vendor/chat","architecture":{"input_modalities":["text"],"output_modalities":["text"]}},{"id":"vendor/no-audio","architecture":{"input_modalities":["text"],"output_modalities":["transcription"]}},{"id":"vendor/no-output","architecture":{"input_modalities":["audio"],"output_modalities":["audio"]}}]}"#)
        }
        defer { s.invalidateAndCancel() }
        let models = try await OpenRouterSpeechCatalog.fetch(session: s)
        XCTAssertEqual(models.map(\.id), ["vendor/new-asr"])
        XCTAssertEqual(models[0].title, "New ASR")
        XCTAssertEqual(models[0].price, "See pricing")
        XCTAssertEqual(models[0].documentationURL.absoluteString, "https://openrouter.ai/vendor/new-asr")
    }

    func testOpenRouterTranscriptionResponseAndFailures() async throws {
        let s = session { request in
            XCTAssertEqual(request.url?.path, "/api/v1/audio/transcriptions")
            return (200, #"{"text":"  測試 OpenRouter  ","usage":{"seconds":1.2}}"#)
        }
        let result = try await OpenRouterTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: hints)
        XCTAssertEqual(result.text, "測試 OpenRouter")
        XCTAssertEqual(result.engine, "openRouter:openai/whisper-1")
        s.invalidateAndCancel()

        for (status, json) in [(401, "unauthorized"), (200, "{}"), (200, "not-json")] {
            let failureSession = session { _ in (status, json) }
            do {
                _ = try await OpenRouterTranscriber(apiKey: "key", session: failureSession).transcribe(samples: samples, hints: .init())
                XCTFail("Expected transcription failure")
            } catch TranscriberError.http(let actual, _) { XCTAssertEqual(actual, status) }
            catch TranscriberError.invalidResponse { XCTAssertEqual(status, 200) }
            catch { XCTFail("\(error)") }
            failureSession.invalidateAndCancel()
        }
    }

    func testOpenRouterDoesNotUploadWithoutKeyOrAudio() async {
        let s = session { _ in XCTFail("Unexpected upload"); return (500, "") }
        defer { s.invalidateAndCancel() }
        for (key, audio) in [(nil as String?, samples), ("key", [])] {
            do {
                _ = try await OpenRouterTranscriber(apiKey: key, session: s).transcribe(samples: audio, hints: .init())
                XCTFail("Expected a local validation failure")
            } catch TranscriberError.missingAPIKey { XCTAssertFalse(audio.isEmpty) }
            catch TranscriberError.emptyAudio { XCTAssertTrue(audio.isEmpty) }
            catch { XCTFail("\(error)") }
        }
    }

    func testAdditionalOpenAIModelsUseSingleLanguageAndPromptFields() throws {
        for model in ["gpt-4o-mini-transcribe", "gpt-4o-transcribe"] {
            let engine = OpenAITranscriber(model: model, apiKey: "key")
            let form = body(try engine.makeRequest(samples: samples, hints: hints))
            XCTAssertEqual(engine.id, "openAI:\(model)")
            XCTAssertTrue(form.contains("name=\"model\"\r\n\r\n\(model)"))
            XCTAssertTrue(form.contains("name=\"language\"\r\n\r\nzh"))
            XCTAssertTrue(form.contains("name=\"prompt\""))
            XCTAssertFalse(form.contains("languages[]"))
            XCTAssertFalse(form.contains("keywords[]"))
        }
    }

    func testAlternativeGroqAndScribeModelsReachTheWire() throws {
        let groq = OpenAICompatibleTranscriber(baseURL: URL(string: ASRProviderKind.groq.preset!.baseURL)!, model: "whisper-large-v3", apiKey: "key")
        XCTAssertTrue(body(try groq.makeRequest(samples: samples, hints: hints)).contains("name=\"model\"\r\n\r\nwhisper-large-v3\r\n"))
        let scribe = ElevenLabsTranscriber(modelId: "scribe_v2_medical", apiKey: "key")
        XCTAssertTrue(body(try scribe.makeRequest(samples: samples, hints: hints)).contains("name=\"model_id\"\r\n\r\nscribe_v2_medical"))
    }

    func testDeepgramMultilingualAndWhisperUseTheirOwnOptions() throws {
        let multi = try DeepgramTranscriber(model: "nova-3-multilingual", apiKey: "key").makeRequest(samples: samples, hints: hints)
        let query = URLComponents(url: multi.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "model", value: "nova-3")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "language", value: "multi")))
        XCTAssertFalse(query.contains { $0.name == "detect_language" })
        XCTAssertEqual(query.filter { $0.name == "language" }.count, 1)
        let whisper = DeepgramTranscriber(model: "whisper-large", apiKey: "key")
        let auto = try whisper.makeRequest(samples: samples, hints: .init()).url!.absoluteString
        XCTAssertTrue(auto.contains("model=whisper-large"))
        XCTAssertTrue(auto.contains("detect_language=true"))
        XCTAssertFalse(auto.contains("smart_format"))
        let zh = try whisper.makeRequest(samples: samples, hints: hints).url!.absoluteString
        XCTAssertTrue(zh.contains("language=zh"))
        XCTAssertFalse(zh.contains("zh-TW"))
    }

    func testConnectionChecksUseAuthenticatedGETWithoutAudioForAllProviders() async throws {
        for preset in EndpointPreset.asr {
            for model in SpeechModelInfo.models(for: preset.kind) {
                var config = ASRConfig()
                config.select(preset.kind)
                config.selectModel(model.id)
                let s = session { request in
                    XCTAssertEqual(request.httpMethod, "GET")
                    XCTAssertNil(request.httpBody)
                    XCTAssertNil(request.httpBodyStream)
                    XCTAssertEqual(request.url?.host, URL(string: preset.baseURL)?.host)
                    switch preset.kind {
                    case .openRouter:
                        XCTAssertEqual(request.url?.host, "openrouter.ai")
                        if request.url?.path == "/api/v1/key" {
                            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                            return (200, #"{"data":{"label":"fixture"}}"#)
                        }
                        XCTAssertEqual(request.url?.path, "/api/v1/models")
                        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
                                       [URLQueryItem(name: "output_modalities", value: "transcription")])
                        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                        return (200, "{\"data\":[{\"id\":\"\(model.id)\",\"architecture\":{\"input_modalities\":[\"audio\"],\"output_modalities\":[\"transcription\"]}}]}")
                    case .elevenLabs:
                        XCTAssertEqual(request.url?.path, "/v1/user")
                        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "test-key")
                        return (200, "{\"user_id\":\"fixture\"}")
                    case .deepgram:
                        XCTAssertEqual(request.url?.path, "/v1/auth/token")
                        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token test-key")
                        return (200, "{\"api_key_id\":\"fixture\"}")
                    default:
                        XCTAssertEqual(request.url?.lastPathComponent, "models")
                        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                        let field = preset.kind == .soniox ? "models" : "data"
                        return (200, "{\"\(field)\":[{\"id\":\"\(model.id)\"}]}")
                    }
                }
                let result = try await SpeechConnectionChecker(session: s).check(config: config, apiKey: " test-key\n")
                XCTAssertEqual(result.modelAvailable, [.openAI, .openRouter, .groq, .soniox].contains(preset.kind))
                if preset.kind == .openRouter {
                    XCTAssertTrue(result.catalogIsPublic)
                    XCTAssertTrue(result.message.contains("Speech access and billing are not verified"))
                }
                s.invalidateAndCancel()
            }
        }
    }

    func testConnectionFailuresHaveActionableMessagesWithoutResponseSecrets() async {
        for (status, response, expected) in [
            (401, "secret-key", SpeechConnectionError.invalidKey),
            (401, "{\"detail\":{\"status\":\"missing_permissions\",\"message\":\"secret-key\"}}", .permissionDenied),
            (403, "secret-key", .permissionDenied), (429, "secret-key", .rateLimited), (503, "secret-key", .server(503)),
            (200, "not-json secret-key", .invalidResponse), (200, "{}", .invalidResponse),
            (200, "{\"data\":[{\"id\":\"unrelated-model\"}]}", .modelUnavailable)
        ] {
            let s = session { _ in (status, response) }
            do {
                _ = try await SpeechConnectionChecker(session: s).check(config: ASRConfig(kind: .openAI), apiKey: "secret-key")
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? SpeechConnectionError, expected)
                XCTAssertFalse(error.localizedDescription.contains("secret-key"))
            }
            s.invalidateAndCancel()
        }
    }

    func testOpenRouterRejectsInvalidKeyBeforePublicCatalogCheck() async {
        let s = session { request in
            XCTAssertEqual(request.url?.path, "/api/v1/key")
            return (401, #"{"error":"bad secret-key"}"#)
        }
        defer { s.invalidateAndCancel() }
        var config = ASRConfig()
        config.select(.openRouter)
        do {
            _ = try await SpeechConnectionChecker(session: s).check(config: config, apiKey: "secret-key")
            XCTFail("A public /models response must not authenticate an invalid key")
        } catch {
            XCTAssertEqual(error as? SpeechConnectionError, .invalidKey)
            XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        }
    }

    func testOpenRouterUnlistedSpeechModelUsesCatalogErrorAfterValidKey() async {
        let s = session { request in
            if request.url?.path == "/api/v1/key" { return (200, #"{"data":{"label":"fixture"}}"#) }
            return (200, #"{"data":[{"id":"vendor/other-speech","architecture":{"input_modalities":["audio"],"output_modalities":["transcription"]}}]}"#)
        }
        defer { s.invalidateAndCancel() }
        var config = ASRConfig()
        config.select(.openRouter)
        config.selectModel("vendor/saved-speech")
        do {
            _ = try await SpeechConnectionChecker(session: s).check(config: config, apiKey: "key")
            XCTFail("Unlisted model should not pass")
        } catch {
            XCTAssertEqual(error as? SpeechConnectionError, .openRouterModelUnlisted)
            XCTAssertTrue(error.localizedDescription.contains("public speech catalog"))
            XCTAssertFalse(error.localizedDescription.contains("model access"))
        }
    }

    func testConnectionRejectsBlankKeysBeforeNetworkingAndMapsOfflineErrors() async {
        let s = session { _ in throw URLError(.notConnectedToInternet) }
        for (key, expected) in [(" \n", SpeechConnectionError.missingKey), ("key", .network)] {
            do {
                _ = try await SpeechConnectionChecker(session: s).check(config: ASRConfig(kind: .openAI), apiKey: key)
                XCTFail("Expected \(expected)")
            } catch { XCTAssertEqual(error as? SpeechConnectionError, expected) }
        }
        s.invalidateAndCancel()
    }

    func testEveryProviderRejectsMalformedConnectionResponses() async {
        for preset in EndpointPreset.asr {
            for response in ["<html>Proxy error</html>", "{}", "{\"error\":\"not authenticated\"}"] {
                let s = session { _ in (200, response) }
                do {
                    _ = try await SpeechConnectionChecker(session: s).check(config: ASRConfig(kind: preset.kind), apiKey: "key")
                    XCTFail("\(preset.name) accepted malformed data")
                } catch { XCTAssertEqual(error as? SpeechConnectionError, .invalidResponse) }
                s.invalidateAndCancel()
            }
        }
    }

    func testConnectionDeadlineAndCancellation() async {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StalledSpeechURLProtocol.self]
        let s = URLSession(configuration: c)
        defer { s.invalidateAndCancel() }
        do {
            _ = try await SpeechConnectionChecker(session: s, timeout: 0.03).check(config: ASRConfig(kind: .openAI), apiKey: "key")
            XCTFail("Expected a timeout")
        } catch { XCTAssertEqual(error as? SpeechConnectionError, .timedOut) }
        let pending = Task { try await SpeechConnectionChecker(session: s).check(config: ASRConfig(kind: .openAI), apiKey: "key") }
        try? await Task.sleep(for: .milliseconds(10))
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testGPTTranscribeUsesItsNativeArrayFieldsAndFiltersInvalidKeywords() throws {
        let request = try OpenAITranscriber(apiKey: "key").makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        let form = body(request)
        XCTAssertTrue(form.contains("name=\"model\"\r\n\r\ngpt-transcribe"))
        XCTAssertTrue(form.contains("name=\"languages[]\"\r\n\r\nzh"))
        XCTAssertFalse(form.contains("name=\"language\""))
        XCTAssertEqual(form.components(separatedBy: "name=\"keywords[]\"").count - 1, 2)
        XCTAssertTrue(form.contains("C++"))
        XCTAssertFalse(form.contains("<bad>"))
        XCTAssertFalse(form.contains("bad\nterm"))
        XCTAssertTrue(form.contains("filename=\"audio.wav\""))
        XCTAssertTrue(form.contains("RIFF"))
        let auto = try OpenAITranscriber(apiKey: "key").makeRequest(samples: samples, hints: .init(language: "  "))
        XCTAssertFalse(body(auto).contains("languages[]"))
    }

    func testGroqRetainsWhisperWire() throws {
        let p = ASRProviderKind.groq.preset!
        let engine = OpenAICompatibleTranscriber(baseURL: URL(string: p.baseURL)!, model: p.defaultModel, apiKey: "groq-key", requiresKey: true)
        let request = try engine.makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer groq-key")
        XCTAssertTrue(body(request).contains("name=\"language\"\r\n\r\nzh"))
        XCTAssertTrue(body(request).contains("whisper-large-v3-turbo"))
        XCTAssertTrue(body(request).contains("name=\"prompt\""))
        XCTAssertFalse(body(request).contains("languages[]"))
    }

    func testScribeUsesNativeAuthAndNoPaidAddOns() throws {
        let request = try ElevenLabsTranscriber(apiKey: "scribe-key").makeRequest(samples: samples, hints: hints)
        XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "scribe-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let form = body(request)
        XCTAssertTrue(form.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(form.contains("name=\"language_code\"\r\n\r\nzh"))
        XCTAssertTrue(form.contains("name=\"tag_audio_events\"\r\n\r\nfalse"))
        XCTAssertTrue(form.contains("name=\"diarize\"\r\n\r\nfalse"))
        XCTAssertFalse(form.contains("keyterms"))
    }

    func testNovaUsesRawWAVAndDominantLanguageDetection() throws {
        let engine = DeepgramTranscriber(apiKey: "dg-key")
        let auto = try engine.makeRequest(samples: samples, hints: .init())
        XCTAssertEqual(auto.value(forHTTPHeaderField: "Authorization"), "Token dg-key")
        XCTAssertEqual(auto.value(forHTTPHeaderField: "Content-Type"), "audio/wav")
        XCTAssertEqual(auto.httpBody, WAVEncoder.encode(samples: samples))
        XCTAssertTrue(auto.url!.absoluteString.contains("detect_language=true"))
        XCTAssertTrue(auto.url!.absoluteString.contains("smart_format=true"))
        XCTAssertTrue(auto.url!.absoluteString.contains("model=nova-3"))
        XCTAssertFalse(auto.url!.absoluteString.contains("keyterm"))
        let zh = try engine.makeRequest(samples: samples, hints: hints)
        XCTAssertTrue(zh.url!.absoluteString.contains("language=zh-TW"))
        XCTAssertFalse(zh.url!.absoluteString.contains("detect_language"))
    }

    func testSonioxUsesCurrentModelAndNonStrictContext() {
        let payload = SonioxTranscriber(apiKey: "key").payload(fileID: fileID, hints: hints)
        XCTAssertEqual(payload["model"] as? String, "stt-async-v5")
        XCTAssertEqual(payload["file_id"] as? String, fileID)
        XCTAssertEqual(payload["language_hints"] as? [String], ["zh"])
        XCTAssertNil(payload["language_hints_strict"])
        XCTAssertNil(payload["translation"])
        let context = payload["context"] as? [String: [String]]
        XCTAssertEqual(context?["terms"]?.filter { $0 == "Airdraft" }.count, 1)
        XCTAssertNil(SonioxTranscriber(apiKey: "key").payload(fileID: fileID, hints: .init())["language_hints"])
    }

    func testSynchronousProviderResponses() async throws {
        let s = session { request in
            switch request.url!.host! {
            case "api.openai.com": return (200, #"{"text":"  測試 API  ","languages":[{"code":"zh"}]}"#)
            case "api.groq.com": return (200, #"{"text":"  測試 API  ","language":"zh"}"#)
            case "api.elevenlabs.io": return (200, #"{"text":"  測試 API  ","language_code":"zh"}"#)
            case "api.deepgram.com": return (200, #"{"results":{"channels":[{"detected_language":"zh","alternatives":[{"transcript":"  測試 API  "}]}]}}"#)
            default: throw URLError(.badURL)
            }
        }
        defer { s.invalidateAndCancel() }
        for engine in engines(session: s) {
            let result = try await engine.transcribe(samples: samples, hints: .init())
            XCTAssertEqual(result.text, "測試 API")
            XCTAssertEqual(result.language, "zh")
            XCTAssertEqual(result.engine, engine.id)
        }
    }

    func testMissingKeysAndEmptyAudioNeverReachNetwork() async {
        let s = session { _ in XCTFail("Unexpected upload"); return (500, "") }
        defer { s.invalidateAndCancel() }
        let cloud = engines(session: s, key: nil) + [SonioxTranscriber(apiKey: nil, session: s)]
        for engine in cloud {
            do {
                _ = try await engine.transcribe(samples: samples, hints: .init())
                XCTFail("Missing key should fail")
            } catch TranscriberError.missingAPIKey {} catch { XCTFail("\(error)") }
            do {
                _ = try await engine.transcribe(samples: [], hints: .init())
                XCTFail("Empty audio should fail")
            } catch TranscriberError.emptyAudio {} catch { XCTFail("\(error)") }
        }
    }

    func testHTTPFailuresAndMalformedResponsesAreNotSuccessfulTranscripts() async {
        for (status, json) in [(401, "unauthorized"), (429, "rate limit"), (200, "{}"), (200, "not-json")] {
            let s = session { _ in (status, json) }
            for engine in engines(session: s) {
                do {
                    _ = try await engine.transcribe(samples: samples, hints: .init())
                    XCTFail("Bad response should fail")
                } catch TranscriberError.http(let actual, _) { XCTAssertEqual(actual, status) }
                catch TranscriberError.invalidResponse { XCTAssertEqual(status, 200) }
                catch { XCTFail("\(error)") }
            }
            s.invalidateAndCancel()
        }
    }

    func testStalledUploadIsCancelledByWallClockDeadline() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalledSpeechURLProtocol.self]
        let s = URLSession(configuration: configuration)
        defer { s.invalidateAndCancel() }
        let started = Date()
        do {
            _ = try await OpenAITranscriber(apiKey: "key", timeout: 0.05, session: s)
                .transcribe(samples: samples, hints: .init())
            XCTFail("A stalled request must time out")
        } catch TranscriberError.timedOut {} catch { XCTFail("\(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testSonioxLifecycleAndCleanup() async throws {
        let requests = RequestLog()
        let s = sonioxSession(requests: requests)
        defer { s.invalidateAndCancel() }
        let result = try await SonioxTranscriber(apiKey: "soniox-key", session: s, pollInterval: 0.01)
            .transcribe(samples: samples, hints: .init(language: "zh", vocabulary: ["Airdraft"]))
        XCTAssertEqual(result.text, "今天 use Airdraft.")
        XCTAssertEqual(result.language, "zh")
        XCTAssertEqual(requests.paths, ["POST /v1/files", "POST /v1/transcriptions", "GET /v1/transcriptions/\(jobID)",
                                       "GET /v1/transcriptions/\(jobID)/transcript", "DELETE /v1/transcriptions/\(jobID)", "DELETE /v1/files/\(fileID)"])
    }

    func testSonioxFailedJobCleansBothResources() async {
        let requests = RequestLog()
        let s = sonioxSession(requests: requests, status: "error")
        defer { s.invalidateAndCancel() }
        do {
            _ = try await SonioxTranscriber(apiKey: "key", session: s, pollInterval: 0.01).transcribe(samples: samples, hints: .init())
            XCTFail("Job error should fail")
        } catch TranscriberError.providerFailure(let provider, _) { XCTAssertEqual(provider, "Soniox") }
        catch { XCTFail("\(error)") }
        XCTAssertEqual(Array(requests.paths.suffix(2)), ["DELETE /v1/transcriptions/\(jobID)", "DELETE /v1/files/\(fileID)"])
    }

    func testSonioxCreateFailureStillDeletesUpload() async {
        let requests = RequestLog()
        let s = sonioxSession(requests: requests, createStatus: 400)
        defer { s.invalidateAndCancel() }
        do {
            _ = try await SonioxTranscriber(apiKey: "key", session: s).transcribe(samples: samples, hints: .init())
            XCTFail("Create should fail")
        } catch TranscriberError.http(let status, _) { XCTAssertEqual(status, 400) }
        catch { XCTFail("\(error)") }
        XCTAssertEqual(requests.paths.last, "DELETE /v1/files/\(fileID)")
        XCTAssertFalse(requests.paths.contains("DELETE /v1/transcriptions/\(jobID)"))
    }

    func testSonioxPollingHasOverallDeadlineAndCleansUp() async {
        let requests = RequestLog()
        let s = sonioxSession(requests: requests, status: "processing")
        defer { s.invalidateAndCancel() }
        let started = Date()
        do {
            _ = try await SonioxTranscriber(apiKey: "key", timeout: 0.08, session: s, pollInterval: 0.01).transcribe(samples: samples, hints: .init())
            XCTFail("Polling must time out")
        } catch TranscriberError.timedOut {} catch { XCTFail("\(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(Array(requests.paths.suffix(2)), ["DELETE /v1/transcriptions/\(jobID)", "DELETE /v1/files/\(fileID)"])
    }

    func testSonioxCancellationStillCleansUp() async {
        let requests = RequestLog()
        let polled = expectation(description: "poll reached")
        polled.assertForOverFulfill = false
        let s = sonioxSession(requests: requests, status: "processing", onPoll: { polled.fulfill() })
        defer { s.invalidateAndCancel() }
        let engine = SonioxTranscriber(apiKey: "key", session: s, pollInterval: 0.05)
        let task = Task { try await engine.transcribe(samples: samples, hints: .init()) }
        await fulfillment(of: [polled], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Should cancel") }
        catch is CancellationError {} catch let error as URLError { XCTAssertEqual(error.code, .cancelled) }
        catch { XCTFail("\(error)") }
        XCTAssertEqual(Array(requests.paths.suffix(2)), ["DELETE /v1/transcriptions/\(jobID)", "DELETE /v1/files/\(fileID)"])
    }

    func testCleanupFailureDoesNotDiscardValidTranscript() async throws {
        let requests = RequestLog()
        let s = sonioxSession(requests: requests, deleteStatus: 503)
        defer { s.invalidateAndCancel() }
        let result = try await SonioxTranscriber(apiKey: "key", session: s, pollInterval: 0.01).transcribe(samples: samples, hints: .init())
        XCTAssertEqual(result.text, "今天 use Airdraft.")
        XCTAssertEqual(requests.paths.filter { $0.hasPrefix("DELETE") }.count, 2)
    }

    private func engines(session: URLSession, key: String? = "key") -> [any Transcriber] {
        [OpenAITranscriber(apiKey: key, session: session),
         OpenAICompatibleTranscriber(baseURL: URL(string: "https://api.groq.com/openai/v1")!, model: "whisper-large-v3-turbo", apiKey: key, requiresKey: true, session: session),
         ElevenLabsTranscriber(apiKey: key, session: session), DeepgramTranscriber(apiKey: key, session: session)]
    }

    private func sonioxSession(requests: RequestLog, status: String = "completed", createStatus: Int = 201,
                               deleteStatus: Int = 204, onPoll: (() -> Void)? = nil) -> URLSession {
        let file = fileID, job = jobID
        return session { request in
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            let route = "\(request.httpMethod!) \(request.url!.path)"
            requests.append(route)
            if request.httpMethod == "DELETE" { return (deleteStatus, "") }
            switch route {
            case "POST /v1/files": return (200, "{\"id\":\"\(file)\"}")
            case "POST /v1/transcriptions": return (createStatus, "{\"id\":\"\(job)\",\"status\":\"queued\"}")
            case "GET /v1/transcriptions/\(job)":
                onPoll?()
                return (200, "{\"id\":\"\(job)\",\"status\":\"\(status)\",\"error_message\":\"test failure\"}")
            case "GET /v1/transcriptions/\(job)/transcript":
                return (200, #"{"text":"今天 use Airdraft.","tokens":[{"language":"zh"},{"language":"en"}]}"#)
            default: XCTFail("Unexpected route \(route)"); return (404, "")
            }
        }
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
}

private final class SpeechURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var callback: ((URLRequest) throws -> (Int, String))?
    static var handler: ((URLRequest) throws -> (Int, String))? {
        get { lock.lock(); defer { lock.unlock() }; return callback }
        set { lock.lock(); defer { lock.unlock() }; callback = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (status, json) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class StalledSpeechURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
