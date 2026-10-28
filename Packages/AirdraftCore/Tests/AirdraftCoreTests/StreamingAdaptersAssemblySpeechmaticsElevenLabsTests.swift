import XCTest
@testable import AirdraftCore

/// AD-123: the AssemblyAI, Speechmatics and ElevenLabs real-time adapters against
/// a scripted connection. No test reaches a provider; keys are fake and must
/// never appear in a URL.
final class StreamingAdaptersAssemblySpeechmaticsElevenLabsTests: XCTestCase {
    private func speech(_ seconds: Double, level: Float = 0.2) -> [Float] {
        [Float](repeating: level, count: Int(seconds * 16_000))
    }

    private func query(_ request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func jsonArray(_ value: String?) -> [String]? {
        guard let value else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String]
    }

    private func assertProviderError(_ parser: any StreamingParser, _ frame: StreamingFrame, _ expected: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parser.consume(frame), file: file, line: line) { error in
            XCTAssertEqual(error as? StreamingError, .provider(expected), file: file, line: line)
        }
    }

    // MARK: AssemblyAI

    func testAssemblyAIRequestFramesAndParsing() async throws {
        let provider = AssemblyAIStreaming(batchModel: "universal-3-5-pro",
                                           hints: TranscriptionHints(language: "es", vocabulary: ["Airdraft", "C++"]),
                                           engineID: "assemblyAI:universal-3-5-pro")
        XCTAssertFalse(provider.matchesBatchModel, "The realtime model is configured differently from async")
        XCTAssertEqual(provider.sampleRate, 16_000)
        let request = try await provider.request(apiKey: "fake-key")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "streaming.assemblyai.com")
        XCTAssertEqual(url.path, "/v3/ws")
        XCTAssertFalse(url.absoluteString.contains("fake-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fake-key", "No Bearer prefix")
        let items = query(request)
        XCTAssertEqual(items["speech_model"], "universal-3-5-pro")
        XCTAssertEqual(items["encoding"], "pcm_s16le")
        XCTAssertEqual(items["sample_rate"], "16000")
        XCTAssertEqual(items["language_detection"], "true")
        XCTAssertEqual(jsonArray(items["language_codes"]), ["en", "es"])
        XCTAssertEqual(jsonArray(items["keyterms_prompt"]), ["Airdraft", "C++"])
        XCTAssertTrue(url.absoluteString.contains("%2B"), "A plus sign is not read as a space")

        let preview = AssemblyAIStreaming(batchModel: "universal-3-6-pro-preview", hints: TranscriptionHints(), engineID: "a")
        let previewRequest = try await preview.request(apiKey: "fake-key")
        let previewItems = query(previewRequest)
        XCTAssertEqual(previewItems["speech_model"], "universal-3-6-pro")
        XCTAssertNil(previewItems["language_codes"], "Auto leaves languages to detection")
        XCTAssertNil(previewItems["keyterms_prompt"])

        XCTAssertTrue(provider.startFrames().isEmpty)
        XCTAssertEqual(provider.audioFrame(Data([1, 2, 3, 4])), .data(Data([1, 2, 3, 4])))
        XCTAssertEqual(provider.endFrames().map { $0.jsonObject?["type"] as? String }, ["ForceEndpoint", "Terminate"])

        let parser = provider.makeParser()
        try parser.consume(.text(#"{"type":"Begin","id":"x","expires_at":1}"#))
        try parser.consume(.text(#"{"type":"Turn","turn_order":0,"end_of_turn":false,"transcript":"Hola","language_code":"es"}"#))
        XCTAssertEqual(parser.provisional, "Hola")
        XCTAssertEqual(parser.finalText, "")
        try parser.consume(.text(#"{"type":"Turn","turn_order":0,"end_of_turn":true,"turn_is_formatted":true,"transcript":"Hola, mundo."}"#))
        XCTAssertEqual(parser.finalText, "Hola, mundo.")
        XCTAssertEqual(parser.provisional, "")
        XCTAssertEqual(parser.language, "es")
        try parser.consume(.text(#"{"type":"Turn","turn_order":1,"end_of_turn":false,"transcript":"Otra"}"#))
        XCTAssertEqual(parser.provisional, "Otra")
        try parser.consume(.text(#"{"type":"Turn","turn_order":1,"end_of_turn":true,"transcript":"Otra frase."}"#))
        XCTAssertEqual(parser.finalText, "Hola, mundo. Otra frase.")
        XCTAssertFalse(parser.finished)
        try parser.consume(.text(#"{"type":"Termination","audio_duration_seconds":2,"session_duration_seconds":3}"#))
        XCTAssertTrue(parser.finished)

        assertProviderError(provider.makeParser(), .text(#"{"type":"Error","error_code":3008,"error":"Session expired"}"#),
                            "AssemblyAI: Session expired")
    }

    func testAssemblyAISessionShowsTextButNeverStandsInForTheBatchModel() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let provider = AssemblyAIStreaming(batchModel: "universal-3-5-pro", hints: TranscriptionHints(language: "en"),
                                           engineID: "assemblyAI:universal-3-5-pro")
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertFalse(session.reusesForTranscript)
        session.append(speech(0.3))
        server.openConnection()
        try await waitUntil { !server.sent.isEmpty }
        XCTAssertEqual(server.sent.first, .data(CloudLiveTranscript.pcm16(speech(0.3))))
        server.reply(.text(#"{"type":"Begin","id":"x"}"#))
        server.reply(.text(#"{"type":"Turn","turn_order":0,"end_of_turn":false,"transcript":"Hello wor"}"#))
        try await waitUntil { events.texts.last == "Hello wor" }
        server.reply(.text(#"{"type":"Turn","turn_order":0,"end_of_turn":true,"transcript":"Hello world."}"#))
        try await waitUntil { events.texts.last == "Hello world." }
        let result = await session.finishTranscript(capture: speech(0.5))
        XCTAssertNil(result, "Display-only live text leaves the transcript to the batch request")
        try await waitUntil { server.closed }
        XCTAssertTrue(events.issues.isEmpty)
    }

    // MARK: Speechmatics

    func testSpeechmaticsRequestFramesAndParsing() async throws {
        XCTAssertNil(SpeechmaticsStreaming(config: ASRConfig(kind: .speechmatics), hints: TranscriptionHints()),
                     "Real-time Speechmatics has no automatic language identification")
        XCTAssertNil(SpeechmaticsStreaming(config: ASRConfig(kind: .speechmatics, language: "auto"), hints: TranscriptionHints()))
        let config = ASRConfig(kind: .speechmatics, language: "zh")
        let provider = try XCTUnwrap(SpeechmaticsStreaming(config: config, hints: TranscriptionHints(language: "zh", vocabulary: ["Airdraft"])))
        XCTAssertTrue(provider.matchesBatchModel)
        XCTAssertEqual(provider.engineID, "speechmatics:enhanced")
        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(request.url?.absoluteString, "wss://eu.rt.speechmatics.com/v2/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertFalse(request.url?.absoluteString.contains("fake-key") ?? true)

        let start = try XCTUnwrap(provider.startFrames().first?.jsonObject)
        XCTAssertEqual(provider.startFrames().count, 1)
        XCTAssertEqual(start["message"] as? String, "StartRecognition")
        let format = try XCTUnwrap(start["audio_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "raw")
        XCTAssertEqual(format["encoding"] as? String, "pcm_s16le")
        XCTAssertEqual(format["sample_rate"] as? Int, 16_000)
        let transcription = try XCTUnwrap(start["transcription_config"] as? [String: Any])
        XCTAssertEqual(transcription["language"] as? String, "cmn", "Mandarin uses the batch request's code")
        XCTAssertEqual(transcription["model"] as? String, "enhanced")
        XCTAssertEqual(transcription["enable_partials"] as? Bool, true)
        XCTAssertEqual((transcription["additional_vocab"] as? [[String: String]])?.first?["content"], "Airdraft")

        // A language saved on the config is enough when no hints are given yet.
        XCTAssertNotNil(SpeechmaticsStreaming(config: ASRConfig(kind: .speechmatics, language: "en"), hints: TranscriptionHints()))

        XCTAssertEqual(provider.endFrames().first?.jsonObject?["last_seq_no"] as? Int, 0)
        XCTAssertEqual(provider.audioFrame(Data([1, 2])), .data(Data([1, 2])))
        _ = provider.audioFrame(Data([3, 4]))
        let end = try XCTUnwrap(provider.endFrames().first?.jsonObject)
        XCTAssertEqual(end["message"] as? String, "EndOfStream")
        XCTAssertEqual(end["last_seq_no"] as? Int, 2, "Counts every audio chunk sent")

        let parser = provider.makeParser()
        try parser.consume(.text(#"{"message":"RecognitionStarted","id":"x"}"#))
        try parser.consume(.text(#"{"message":"AudioAdded","seq_no":1}"#))
        try parser.consume(.text(#"{"message":"AddPartialTranscript","metadata":{"transcript":"你好","start_time":0,"end_time":1},"results":[]}"#))
        XCTAssertEqual(parser.provisional, "你好")
        try parser.consume(.text(#"{"message":"AddTranscript","metadata":{"transcript":"你好。","start_time":0,"end_time":1},"results":[]}"#))
        XCTAssertEqual(parser.finalText, "你好。")
        XCTAssertEqual(parser.provisional, "")
        try parser.consume(.text(#"{"message":"AddTranscript","metadata":{"transcript":"世界。"},"results":[]}"#))
        XCTAssertEqual(parser.finalText, "你好。世界。", "CJK segments join without a space")
        XCTAssertEqual(parser.language, "zh")
        try parser.consume(.text(#"{"message":"Warning","type":"idle_timeout","reason":"Idle"}"#))
        XCTAssertFalse(parser.finished)
        try parser.consume(.text(#"{"message":"EndOfTranscript"}"#))
        XCTAssertTrue(parser.finished)

        assertProviderError(provider.makeParser(), .text(#"{"message":"Error","type":"not_authorised","reason":"Invalid key"}"#),
                            "Speechmatics: Invalid key")
    }

    func testSpeechmaticsFinalTextBecomesTheTranscript() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let provider = try XCTUnwrap(SpeechmaticsStreaming(config: ASRConfig(kind: .speechmatics, language: "en"),
                                                           hints: TranscriptionHints(language: "en")))
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertTrue(session.reusesForTranscript)
        let early = speech(0.5)
        session.append(early)
        server.openConnection()
        try await waitUntil { !server.sent.isEmpty }
        XCTAssertEqual(server.sent.count, 1, "Audio waits for RecognitionStarted")
        XCTAssertEqual(server.sent.first?.jsonObject?["message"] as? String, "StartRecognition")
        server.reply(.text(#"{"message":"RecognitionStarted","id":"x"}"#))
        try await waitUntil { server.sent.count >= 2 }
        server.reply(.text(#"{"message":"AddPartialTranscript","metadata":{"transcript":"Hello wor"},"results":[]}"#))
        try await waitUntil { events.texts.last == "Hello wor" }
        server.reply(.text(#"{"message":"AddTranscript","metadata":{"transcript":"Hello world. "},"results":[]}"#))
        try await waitUntil { events.texts.last == "Hello world." }
        let late = speech(0.3)
        session.append(late)

        let capture = early + late + speech(0.2)
        let finishing = Task { await session.finishTranscript(capture: capture) }
        try await waitUntil { server.sent.last?.jsonObject?["message"] as? String == "EndOfStream" }
        let audio = server.sent.compactMap { frame -> Int? in if case .data(let data) = frame { return data.count } else { return nil } }
        XCTAssertEqual(audio.reduce(0, +), capture.count * 2, "Every sample is sent once as PCM16")
        XCTAssertEqual(server.sent.last?.jsonObject?["last_seq_no"] as? Int, audio.count)
        server.reply(.text(#"{"message":"AddTranscript","metadata":{"transcript":"Goodbye."},"results":[]}"#))
        server.reply(.text(#"{"message":"EndOfTranscript"}"#))
        let finished = await finishing.value
        let transcript = try XCTUnwrap(finished)
        XCTAssertEqual(transcript.text, "Hello world. Goodbye.")
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.engine, "speechmatics:enhanced")
        XCTAssertTrue(server.closed)
        XCTAssertTrue(events.issues.isEmpty)
    }

    // MARK: ElevenLabs

    func testElevenLabsRequestFramesAndParsing() async throws {
        let provider = ElevenLabsStreaming(hints: TranscriptionHints(language: "en-US"), engineID: "elevenlabs:scribe_v2")
        XCTAssertFalse(provider.matchesBatchModel, "scribe_v2_realtime is not the batch scribe_v2")
        let request = try await provider.request(apiKey: "fake-key")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "api.elevenlabs.io")
        XCTAssertEqual(url.path, "/v1/speech-to-text/realtime")
        XCTAssertFalse(url.absoluteString.contains("fake-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "fake-key")
        let items = query(request)
        XCTAssertEqual(items["model_id"], "scribe_v2_realtime")
        XCTAssertEqual(items["audio_format"], "pcm_16000")
        XCTAssertEqual(items["commit_strategy"], "vad")
        XCTAssertEqual(items["language_code"], "en")
        let autoRequest = try await ElevenLabsStreaming(hints: TranscriptionHints(), engineID: "e").request(apiKey: "fake-key")
        XCTAssertNil(query(autoRequest)["language_code"])

        XCTAssertTrue(provider.startFrames().isEmpty)
        let chunk = try XCTUnwrap(provider.audioFrame(Data([1, 2, 3, 4])).jsonObject)
        XCTAssertEqual(chunk["message_type"] as? String, "input_audio_chunk")
        XCTAssertEqual(chunk["audio_base_64"] as? String, Data([1, 2, 3, 4]).base64EncodedString())
        XCTAssertEqual(chunk["commit"] as? Bool, false)
        XCTAssertEqual(chunk["sample_rate"] as? Int, 16_000)
        let end = try XCTUnwrap(provider.endFrames().first?.jsonObject)
        XCTAssertEqual(end["commit"] as? Bool, true)
        XCTAssertEqual(end["audio_base_64"] as? String, "")

        let parser = provider.makeParser()
        try parser.consume(.text(#"{"message_type":"session_started","session_id":"x","config":{}}"#))
        try parser.consume(.text(#"{"message_type":"partial_transcript","text":"Hello wor"}"#))
        XCTAssertEqual(parser.provisional, "Hello wor")
        try parser.consume(.text(#"{"message_type":"committed_transcript","text":"Hello world."}"#))
        XCTAssertEqual(parser.finalText, "Hello world.")
        XCTAssertEqual(parser.provisional, "")
        try parser.consume(.text(#"{"message_type":"committed_transcript","text":"Again."}"#))
        XCTAssertEqual(parser.finalText, "Hello world. Again.")
        XCTAssertEqual(parser.language, "en")
        XCTAssertFalse(parser.finished, "ElevenLabs sends no end-of-input acknowledgement")

        assertProviderError(provider.makeParser(), .text(#"{"message_type":"auth_error","error":"Invalid API key"}"#),
                            "ElevenLabs: Invalid API key")
        assertProviderError(provider.makeParser(), .text(#"{"message_type":"quota_exceeded"}"#), "ElevenLabs: quota_exceeded")
    }

    func testElevenLabsSessionShowsTextButNeverBecomesTheTranscript() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let session = CloudLiveTranscriptSession(provider: ElevenLabsStreaming(hints: TranscriptionHints(), engineID: "elevenlabs:scribe_v2"),
                                                 apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertFalse(session.reusesForTranscript)
        let audio = speech(0.2)
        session.append(audio)
        server.openConnection()
        try await waitUntil { !server.sent.isEmpty }
        let sent = try XCTUnwrap(server.sent.first?.jsonObject?["audio_base_64"] as? String)
        XCTAssertEqual(Data(base64Encoded: sent), CloudLiveTranscript.pcm16(audio))
        server.reply(.text(#"{"message_type":"session_started","session_id":"x"}"#))
        server.reply(.text(#"{"message_type":"partial_transcript","text":"Hello"}"#))
        try await waitUntil { events.texts.last == "Hello" }
        server.reply(.text(#"{"message_type":"committed_transcript","text":"Hello there."}"#))
        try await waitUntil { events.texts.last == "Hello there." }
        let result = await session.finishTranscript(capture: audio)
        XCTAssertNil(result, "Display-only live text leaves the transcript to scribe_v2")
        try await waitUntil { server.closed }
        XCTAssertTrue(events.issues.isEmpty)
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
