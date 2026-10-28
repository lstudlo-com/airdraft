import XCTest
@testable import AirdraftCore

/// AD-123: OpenAI, Mistral and Gemini live text against scripted connections.
/// All three are display-only. No test reaches a provider; keys are fake and
/// must never appear in a URL.
final class StreamingAdaptersOpenAIMistralGeminiTests: XCTestCase {
    private func speech(_ seconds: Double, level: Float = 0.2) -> [Float] {
        [Float](repeating: level, count: Int(seconds * 16_000))
    }

    private func providerError(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                               _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? StreamingError, .provider(message), file: file, line: line)
        }
    }

    // MARK: OpenAI

    func testOpenAIRequestFramesAndParsing() async throws {
        let provider = OpenAIStreaming(hints: TranscriptionHints(language: "en-US", vocabulary: ["Airdraft", "bad<term>", "Airdraft"]),
                                       engineID: "openAI:gpt-transcribe")
        XCTAssertFalse(provider.matchesBatchModel)
        XCTAssertEqual(provider.sampleRate, 24_000)

        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(request.url?.absoluteString, "wss://api.openai.com/v1/realtime?intent=transcription")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertFalse(request.url?.absoluteString.contains("fake-key") ?? true)

        let start = try XCTUnwrap(provider.startFrames().first?.jsonObject)
        XCTAssertEqual(start["type"] as? String, "session.update")
        let session = try XCTUnwrap(start["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")
        let input = try XCTUnwrap((session["audio"] as? [String: Any])?["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)
        XCTAssertTrue(input["turn_detection"] is NSNull)
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual(transcription["languages"] as? [String], ["en"])
        XCTAssertEqual(transcription["keywords"] as? [String], ["Airdraft"], "Forbidden characters and duplicates are dropped")
        XCTAssertNil(transcription["prompt"])
        XCTAssertNil(transcription["language"], "Never both language and languages")

        let chinese = OpenAIStreaming(hints: TranscriptionHints(language: "zh", chineseScript: .traditional), engineID: "openAI:gpt-transcribe")
        let chineseTranscription = (((chinese.startFrames().first?.jsonObject?["session"] as? [String: Any])?["audio"] as? [String: Any])?["input"]
            as? [String: Any])?["transcription"] as? [String: Any]
        XCTAssertEqual(chineseTranscription?["prompt"] as? String, "以下是繁體中文的內容。")
        XCTAssertNil(chineseTranscription?["keywords"])

        // 0.1 s at 16 kHz becomes 2,400 PCM16 samples at 24 kHz, base64 in JSON.
        let pcm = CloudLiveTranscript.pcm16(speech(0.1), rate: provider.sampleRate)
        XCTAssertEqual(pcm.count, 4_800)
        let append = try XCTUnwrap(provider.audioFrame(pcm).jsonObject)
        XCTAssertEqual(append["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual((append["audio"] as? String).flatMap { Data(base64Encoded: $0) }, pcm)
        XCTAssertEqual(provider.endFrames().map { $0.jsonObject?["type"] as? String }, ["input_audio_buffer.commit"])

        do { // DeltasThenTheCommittedItemsCompletion
            let parser = provider.makeParser()
            try parser.consume(.text(#"{"type":"session.created","session":{"type":"transcription"}}"#))
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"item_1","content_index":0,"delta":"Hello,"}"#))
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"item_1","content_index":0,"delta":" wor"}"#))
            XCTAssertEqual(parser.finalText, "")
            XCTAssertEqual(parser.provisional, "Hello, wor")
            try parser.consume(.text(#"{"type":"input_audio_buffer.committed","item_id":"item_1","previous_item_id":null}"#))
            XCTAssertFalse(parser.finished, "Committed but not transcribed yet")
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"item_1","content_index":0,"transcript":"Hello, world.","languages":[{"code":"en"}]}"#))
            XCTAssertEqual(parser.finalText, "Hello, world.")
            XCTAssertEqual(parser.provisional, "")
            XCTAssertEqual(parser.language, "en")
            XCTAssertTrue(parser.finished)
        }

        do { // CompletionsOutOfOrderKeepFirstSeenOrder
            let parser = provider.makeParser()
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"a","delta":"one"}"#))
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"b","delta":"two"}"#))
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"b","transcript":"Two."}"#))
            XCTAssertEqual(parser.finalText, "Two.")
            XCTAssertEqual(parser.provisional, "one")
            try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"a","transcript":"One."}"#))
            XCTAssertEqual(parser.finalText, "One. Two.")
            XCTAssertFalse(parser.finished, "Nothing was committed by the client yet")
        }

        do { // EmptyCommitEndsQuietly
            let parser = provider.makeParser()
            try parser.consume(.text(#"{"type":"error","error":{"type":"invalid_request_error","code":"input_audio_buffer_commit_empty","message":"buffer too small"}}"#))
            XCTAssertTrue(parser.finished)
        }

        do { // Errors
            let parser = provider.makeParser()
            providerError("OpenAI: Invalid language code") {
                try parser.consume(.text(#"{"type":"error","event_id":"e1","error":{"type":"invalid_request_error","code":"invalid_value","message":"Invalid language code","param":"session.audio.input.transcription.languages"}}"#))
            }
            providerError("OpenAI: Audio could not be transcribed") {
                try parser.consume(.text(#"{"type":"conversation.item.input_audio_transcription.failed","item_id":"item_1","content_index":0,"error":{"type":"transcription_error","message":"Audio could not be transcribed"}}"#))
            }
            XCTAssertThrowsError(try parser.consume(.text("not json"))) { XCTAssertEqual($0 as? StreamingError, .invalidMessage) }
        }
    }

    func testOpenAIShowsLiveTextAndNeverBecomesTheTranscript() async throws {
        let server = try await assertLiveTextOnly(
            OpenAIStreaming(hints: TranscriptionHints(language: "en"), engineID: "openAI:gpt-transcribe"),
            replies: [.text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"item_1","delta":"Hello"}"#),
                      .text(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"item_1","delta":" there"}"#)],
            expected: "Hello there")
        let audio = server.sent.compactMap(\.jsonObject).filter { $0["type"] as? String == "input_audio_buffer.append" }
        XCTAssertFalse(audio.isEmpty)
        XCTAssertTrue(audio.allSatisfy { ($0["audio"] as? String).flatMap { Data(base64Encoded: $0) } != nil })
    }

    // MARK: Mistral

    func testMistralRequestFramesAndParsing() async throws {
        let provider = MistralStreaming(hints: TranscriptionHints(language: "fr-CA", vocabulary: ["Airdraft", "Alder Creek Design"]),
                                        engineID: "mistral:voxtral-mini-latest")
        XCTAssertFalse(provider.matchesBatchModel)
        XCTAssertEqual(provider.sampleRate, 16_000)

        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(request.url?.absoluteString,
                       "wss://api.mistral.ai/v1/audio/transcriptions/realtime?model=voxtral-mini-transcribe-realtime-3")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertFalse(request.url?.absoluteString.contains("fake-key") ?? true)

        let start = try XCTUnwrap(provider.startFrames().first?.jsonObject)
        XCTAssertEqual(start["type"] as? String, "session.update")
        let session = try XCTUnwrap(start["session"] as? [String: Any])
        let format = try XCTUnwrap(session["audio_format"] as? [String: Any])
        XCTAssertEqual(format["encoding"] as? String, "pcm_s16le")
        XCTAssertEqual(format["sample_rate"] as? Int, 16_000)
        XCTAssertEqual(session["language"] as? String, "fr")
        XCTAssertEqual(session["context_bias"] as? [String], ["Airdraft", "Alder Creek Design"])

        // Auto and choices the policy rejects leave the language to detection.
        XCTAssertNil(MistralStreaming.language(TranscriptionHints()))
        XCTAssertNil(MistralStreaming.language(TranscriptionHints(language: "zh-HK")))
        XCTAssertNil(MistralStreaming.language(TranscriptionHints(language: "yue")))
        XCTAssertNil(MistralStreaming(hints: TranscriptionHints(), engineID: "m").startFrames().first?.jsonObject
            .flatMap { ($0["session"] as? [String: Any])?["context_bias"] })

        let pcm = CloudLiveTranscript.pcm16(speech(0.1))
        let append = try XCTUnwrap(provider.audioFrame(pcm).jsonObject)
        XCTAssertEqual(append["type"] as? String, "input_audio.append")
        XCTAssertEqual((append["audio"] as? String).flatMap { Data(base64Encoded: $0) }, pcm)
        XCTAssertEqual(provider.endFrames().map { $0.jsonObject?["type"] as? String }, ["input_audio.end"])

        do { // DeltasAppendUntilDone
            let parser = provider.makeParser()
            try parser.consume(.text(#"{"type":"session.created","session":{"audio_format":{"encoding":"pcm_s16le","sample_rate":16000}}}"#))
            try parser.consume(.text(#"{"type":"session.updated","session":{"language":"fr"}}"#))
            try parser.consume(.text(#"{"type":"transcription.text.delta","text":"Bonjour"}"#))
            try parser.consume(.text(#"{"type":"transcription.text.delta","text":" à tous"}"#))
            XCTAssertEqual(parser.finalText, "Bonjour à tous")
            XCTAssertEqual(parser.provisional, "")
            XCTAssertFalse(parser.finished)
            try parser.consume(.text(#"{"type":"transcription.done","text":"Bonjour à tous.","segments":[],"language":"fr","model":"voxtral-mini-transcribe-realtime-3","usage":{}}"#))
            XCTAssertEqual(parser.finalText, "Bonjour à tous.")
            XCTAssertEqual(parser.language, "fr")
            XCTAssertTrue(parser.finished)
        }

        do { // Errors
            let parser = provider.makeParser()
            providerError("Mistral: Session fields cannot be changed after audio has started.") {
                try parser.consume(.text(#"{"type":"error","error":{"message":"Session fields cannot be changed after audio has started.","code":3051}}"#))
            }
            providerError(#"Mistral: {"detail":"Invalid language alpha2 code"}"#) {
                try parser.consume(.text(#"{"type":"error","error":{"message":{"detail":"Invalid language alpha2 code"},"code":3051}}"#))
            }
            XCTAssertThrowsError(try parser.consume(.data(Data([0xFF])))) { XCTAssertEqual($0 as? StreamingError, .invalidMessage) }
        }
    }

    func testMistralShowsLiveTextAndReportsProviderErrors() async throws {
        _ = try await assertLiveTextOnly(
            MistralStreaming(hints: TranscriptionHints(language: "en"), engineID: "mistral:voxtral-mini-latest"),
            greeting: [.text(#"{"type":"session.created","session":{}}"#)],
            replies: [.text(#"{"type":"transcription.text.delta","text":"Hello"}"#),
                      .text(#"{"type":"transcription.text.delta","text":" there"}"#)],
            expected: "Hello there")

        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let session = CloudLiveTranscriptSession(provider: MistralStreaming(hints: TranscriptionHints(), engineID: "mistral"),
                                                 apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        server.openConnection()
        // An error before session.created stops live text too.
        try await waitUntil { server.request != nil }
        server.reply(.text(#"{"type":"error","error":{"message":"Invalid API key","code":1001}}"#))
        try await waitUntil { events.issues.count == 1 }
        XCTAssertTrue(events.issues[0].contains("Mistral: Invalid API key"))
        let result = await session.finishTranscript(capture: speech(0.2))
        XCTAssertNil(result)
    }

    // MARK: Gemini

    func testGeminiMintsATokenAndKeepsKeyAndTokenOutOfTheURL() async throws {
        let minted = Locked([String]())
        let provider = GeminiStreaming(hints: TranscriptionHints(language: "es-ES", vocabulary: ["Airdraft"]),
                                       engineID: "gemini:gemini-3.5-transcribe",
                                       mintToken: { key in minted.withLock { $0.append(key) }; return "auth_tokens/fake-token" })
        XCTAssertFalse(provider.matchesBatchModel)
        XCTAssertEqual(provider.sampleRate, 16_000)

        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(minted.value, ["fake-key"])
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertEqual(url, "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token auth_tokens/fake-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"), "The long-lived key never reaches the socket")
        XCTAssertFalse(url.contains("fake-key") || url.contains("fake-token") || url.contains("key="))

        // A failed mint fails the connection without opening it.
        let failing = GeminiStreaming(hints: TranscriptionHints(), engineID: "gemini",
                                      mintToken: { _ in throw StreamingError.provider("Gemini: API key not valid") })
        do {
            _ = try await failing.request(apiKey: "fake-key")
            XCTFail("Expected the mint to fail")
        } catch {
            XCTAssertEqual(error as? StreamingError, .provider("Gemini: API key not valid"))
        }

        // The token request: the key in a header, a single use, short expiries.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tokenRequest = try GeminiStreaming.tokenRequest(apiKey: "fake-key", now: now)
        XCTAssertEqual(tokenRequest.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/auth_tokens")
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "x-goog-api-key"), "fake-key")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(tokenRequest.url?.absoluteString.contains("fake-key") ?? true)
        let body = try XCTUnwrap(tokenRequest.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["uses"] as? Int, 1)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(body["newSessionExpireTime"] as? String, formatter.string(from: now.addingTimeInterval(60)))
        XCTAssertEqual(body["expireTime"] as? String, formatter.string(from: now.addingTimeInterval(900)))

        XCTAssertEqual(try GeminiStreaming.token(from: Data(#"{"name":"auth_tokens/abc123"}"#.utf8), status: 200), "auth_tokens/abc123")
        providerError("Gemini: API key not valid. Please pass a valid API key.") {
            _ = try GeminiStreaming.token(from: Data(#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#.utf8), status: 400)
        }
        providerError("Gemini: HTTP 503") { _ = try GeminiStreaming.token(from: Data(), status: 503) }
        for reply in [#"{}"#, #"{"name":""}"#, #"{"name":"bad\r\nInjected: header"}"#, #"{"name":"two words"}"#] {
            XCTAssertThrowsError(try GeminiStreaming.token(from: Data(reply.utf8), status: 200)) {
                XCTAssertEqual($0 as? StreamingError, .invalidMessage)
            }
        }
    }

    func testGeminiFramesAndParsing() throws {
        let provider = GeminiStreaming(hints: TranscriptionHints(language: "es-ES", vocabulary: ["Airdraft", "BigQuery"]),
                                       engineID: "gemini:gemini-3.5-transcribe", mintToken: { _ in "auth_tokens/t" })
        let setup = try XCTUnwrap(provider.startFrames().first?.jsonObject?["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.5-transcribe-live")
        XCTAssertEqual((setup["generationConfig"] as? [String: Any])?["responseModalities"] as? [String], ["TEXT"])
        let transcription = try XCTUnwrap(setup["inputAudioTranscription"] as? [String: Any])
        XCTAssertEqual(transcription["languageCodes"] as? [String], ["es"])
        XCTAssertEqual(transcription["customVocabulary"] as? [String], ["Airdraft", "BigQuery"])
        XCTAssertEqual(transcription["mode"] as? String, "VERBATIM")

        let automatic = GeminiStreaming(hints: TranscriptionHints(), engineID: "gemini", mintToken: { _ in "t" })
        let automaticTranscription = (automatic.startFrames().first?.jsonObject?["setup"] as? [String: Any])?["inputAudioTranscription"] as? [String: Any]
        XCTAssertEqual(automaticTranscription?["languageCodes"] as? [String], [], "An empty list detects the language")
        XCTAssertNil(automaticTranscription?["customVocabulary"])

        let pcm = CloudLiveTranscript.pcm16(speech(0.1))
        let audio = try XCTUnwrap((provider.audioFrame(pcm).jsonObject?["realtimeInput"] as? [String: Any])?["audio"] as? [String: Any])
        XCTAssertEqual(audio["mimeType"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual((audio["data"] as? String).flatMap { Data(base64Encoded: $0) }, pcm)

        do { // InterimReplacedFinalizedJoinedAndOnlyTheEndFinishes
            _ = provider.startFrames()
            let parser = provider.makeParser()
            // The Live API may send its JSON in binary frames.
            try parser.consume(.data(Data(#"{"setupComplete":{}}"#.utf8)))
            try parser.consume(.text(#"{"serverContent":{"interimInputTranscription":{"text":"Hola a","languageCode":"es-ES"}}}"#))
            XCTAssertEqual(parser.provisional, "Hola a")
            try parser.consume(.text(#"{"serverContent":{"interimInputTranscription":{"text":"Hola a todos"}}}"#))
            XCTAssertEqual(parser.provisional, "Hola a todos")
            try parser.consume(.text(#"{"serverContent":{"inputTranscription":{"text":"Hola a todos."}}}"#))
            try parser.consume(.text(#"{"serverContent":{"turnComplete":true}}"#))
            XCTAssertEqual(parser.finalText, "Hola a todos.")
            XCTAssertEqual(parser.provisional, "")
            XCTAssertEqual(parser.language, "es")
            XCTAssertFalse(parser.finished, "A pause mid-recording is not the end")

            try parser.consume(.text(#"{"serverContent":{"interimInputTranscription":{"text":"Adiós"}}}"#))
            XCTAssertEqual(provider.endFrames().first?.jsonObject.flatMap { ($0["realtimeInput"] as? [String: Any])?["audioStreamEnd"] as? Bool }, true)
            XCTAssertFalse(parser.finished)
            try parser.consume(.text(#"{"serverContent":{"inputTranscription":{"text":"Adiós."}}}"#))
            XCTAssertEqual(parser.finalText, "Hola a todos. Adiós.")
            XCTAssertTrue(parser.finished)
        }

        do { // TurnCompleteAfterTheEndFinishes
            _ = provider.startFrames()
            let parser = provider.makeParser()
            _ = provider.endFrames()
            try parser.consume(.text(#"{"serverContent":{"turnComplete":true}}"#))
            XCTAssertTrue(parser.finished)
        }

        do { // Errors
            let parser = provider.makeParser()
            providerError("Gemini: Quota exceeded") {
                try parser.consume(.text(#"{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}"#))
            }
            XCTAssertThrowsError(try parser.consume(.text("[]"))) { XCTAssertEqual($0 as? StreamingError, .invalidMessage) }
        }
    }

    func testGeminiShowsLiveTextAndNeverBecomesTheTranscript() async throws {
        let server = try await assertLiveTextOnly(
            GeminiStreaming(hints: TranscriptionHints(language: "en"), engineID: "gemini:gemini-3.5-transcribe",
                            mintToken: { _ in "auth_tokens/fake-token" }),
            greeting: [.text(#"{"setupComplete":{}}"#)],
            replies: [.data(Data(#"{"setupComplete":{}}"#.utf8)),
                      .text(#"{"serverContent":{"inputTranscription":{"text":"Hello"}}}"#),
                      .text(#"{"serverContent":{"interimInputTranscription":{"text":"there"}}}"#)],
            expected: "Hello there")
        XCTAssertEqual(server.request?.value(forHTTPHeaderField: "Authorization"), "Token auth_tokens/fake-token")
        XCTAssertNotNil(server.sent.first?.jsonObject?["setup"], "Setup is the first message")
    }

    // MARK: Helpers

    /// Runs a display-only provider through a session: early audio is kept, live
    /// text shows, and release returns no transcript and closes the connection.
    @discardableResult
    private func assertLiveTextOnly(_ provider: any StreamingSpeechProvider, greeting: [StreamingFrame] = [],
                                    replies: [StreamingFrame], expected: String,
                                    file: StaticString = #filePath, line: UInt = #line) async throws -> FakeStreamingServer {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertFalse(session.reusesForTranscript, file: file, line: line)
        session.append(speech(0.2))
        server.openConnection()
        // The provider's ready message, when it sends one, then one start frame and the buffered audio.
        for frame in greeting { server.reply(frame) }
        try await waitUntil(file: file, line: line) { server.sent.count >= 2 }
        let request = try XCTUnwrap(server.request, file: file, line: line)
        XCTAssertFalse(request.url?.absoluteString.contains("fake-key") ?? true, file: file, line: line)
        for reply in replies { server.reply(reply) }
        try await waitUntil(file: file, line: line) { events.texts.last == expected }
        let result = await session.finishTranscript(capture: speech(0.3))
        XCTAssertNil(result, "A display-only model never stands in for the batch transcript", file: file, line: line)
        try await waitUntil(file: file, line: line) { server.closed }
        XCTAssertTrue(events.issues.isEmpty, "\(events.issues)", file: file, line: line)
        return server
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out", file: file, line: line)
        throw CancellationError()
    }
}
