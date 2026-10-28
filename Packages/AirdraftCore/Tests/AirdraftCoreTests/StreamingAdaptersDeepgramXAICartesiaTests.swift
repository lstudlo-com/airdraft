import XCTest
@testable import AirdraftCore

/// AD-123: Deepgram, xAI and Cartesia real-time adapters against scripted
/// connections. Keys are fake, never reach a provider and never appear in a URL.
final class StreamingAdaptersDeepgramXAICartesiaTests: XCTestCase {
    private func speech(_ seconds: Double, level: Float = 0.2) -> [Float] {
        [Float](repeating: level, count: Int(seconds * 16_000))
    }

    private func query(_ request: URLRequest) throws -> [(String, String)] {
        let url = try XCTUnwrap(request.url)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return items.map { ($0.name, $0.value ?? "") }
    }

    private func value(_ name: String, in items: [(String, String)]) -> String? {
        items.first { $0.0 == name }?.1
    }

    private func values(_ name: String, in items: [(String, String)]) -> [String] {
        items.filter { $0.0 == name }.map { $0.1 }
    }

    private func assertProviderError(_ parser: any StreamingParser, _ json: String, _ expected: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parser.consume(.text(json)), file: file, line: line) { error in
            XCTAssertEqual(error as? StreamingError, .provider(expected), file: file, line: line)
        }
    }

    // MARK: Deepgram

    func testDeepgramRequestFramesAndParser() async throws {
        let provider = DeepgramStreaming(model: "nova-3", hints: TranscriptionHints(language: "en", vocabulary: ["Airdraft"]),
                                         engineID: "deepgram:nova-3")
        XCTAssertTrue(provider.matchesBatchModel)
        XCTAssertEqual(provider.sampleRate, 16_000)
        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "api.deepgram.com")
        XCTAssertEqual(request.url?.path, "/v1/listen")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token fake-key")
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("fake-key"))
        let items = try query(request)
        XCTAssertEqual(value("model", in: items), "nova-3")
        XCTAssertEqual(value("language", in: items), "en")
        XCTAssertEqual(value("smart_format", in: items), "true")
        XCTAssertEqual(value("encoding", in: items), "linear16")
        XCTAssertEqual(value("sample_rate", in: items), "16000")
        XCTAssertEqual(value("channels", in: items), "1")
        XCTAssertEqual(value("interim_results", in: items), "true")
        XCTAssertNil(value("keyterm", in: items), "The batch request sends no keyterms")
        XCTAssertNil(value("detect_language", in: items))

        XCTAssertEqual(provider.startFrames(), [])
        let pcm = Data([1, 2, 3, 4])
        XCTAssertEqual(provider.audioFrame(pcm), .data(pcm))
        XCTAssertEqual(provider.endFrames(), [.text(#"{"type":"CloseStream"}"#)])

        // Nova-3 Multilingual mirrors the batch request's language=multi.
        let multilingual = DeepgramStreaming(model: "nova-3-multilingual", hints: TranscriptionHints(language: "en"),
                                             engineID: "deepgram:nova-3-multilingual")
        XCTAssertTrue(multilingual.matchesBatchModel)
        let multiRequest = try await multilingual.request(apiKey: "fake-key")
        let multiItems = try query(multiRequest)
        XCTAssertEqual(value("model", in: multiItems), "nova-3")
        XCTAssertEqual(value("language", in: multiItems), "multi")

        // Traditional Chinese keeps the batch request's zh-TW.
        let chinese = DeepgramStreaming(model: "nova-3", hints: TranscriptionHints(language: "zh", chineseScript: .traditional),
                                        engineID: "deepgram:nova-3")
        let chineseRequest = try await chinese.request(apiKey: "fake-key")
        XCTAssertEqual(value("language", in: try query(chineseRequest)), "zh-TW")

        // Batch detection has no streaming equivalent: multi is display only.
        let automatic = DeepgramStreaming(model: "nova-3", hints: TranscriptionHints(), engineID: "deepgram:nova-3")
        XCTAssertFalse(automatic.matchesBatchModel)
        let automaticRequest = try await automatic.request(apiKey: "fake-key")
        XCTAssertEqual(value("language", in: try query(automaticRequest)), "multi")

        let parser = provider.makeParser()
        XCTAssertEqual(parser.language, "en")
        try parser.consume(.text(#"{"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"hello wor"}]}}"#))
        XCTAssertEqual(parser.provisional, "hello wor")
        XCTAssertEqual(parser.finalText, "")
        try parser.consume(.text(#"{"type":"Results","is_final":true,"speech_final":false,"channel":{"alternatives":[{"transcript":"Hello world."}]}}"#))
        try parser.consume(.text(#"{"type":"Results","is_final":true,"speech_final":true,"channel":{"alternatives":[{"transcript":"How are you?"}]}}"#))
        XCTAssertEqual(parser.finalText, "Hello world. How are you?")
        XCTAssertEqual(parser.provisional, "")
        XCTAssertFalse(parser.finished)
        try parser.consume(.text(#"{"type":"SpeechStarted","channel":[0],"timestamp":1.2}"#))
        XCTAssertFalse(parser.finished)
        try parser.consume(.text(#"{"type":"Metadata","request_id":"r","duration":2.5,"channels":1}"#))
        XCTAssertTrue(parser.finished)

        let cjk = DeepgramStreaming.Parser(language: "zh")
        try cjk.consume(.text(#"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"你好"}]}}"#))
        try cjk.consume(.text(#"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"世界"}]}}"#))
        XCTAssertEqual(cjk.finalText, "你好世界")

        assertProviderError(DeepgramStreaming.Parser(), #"{"type":"Error","variant":"DataError","description":"Bad audio"}"#,
                            "Deepgram: Bad audio")
        assertProviderError(DeepgramStreaming.Parser(), #"{"err_code":"INVALID_AUTH","err_msg":"Invalid credentials."}"#,
                            "Deepgram: Invalid credentials.")
        XCTAssertThrowsError(try DeepgramStreaming.Parser().consume(.text("not json")))
    }

    func testDeepgramStreamsEveryFrameAndItsFinalTextBecomesTheTranscript() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let provider = DeepgramStreaming(model: "nova-3", hints: TranscriptionHints(language: "en"), engineID: "deepgram:nova-3")
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertTrue(session.reusesForTranscript)
        let early = speech(0.5)
        session.append(early)
        server.openConnection()
        try await waitUntil { !server.sent.isEmpty }
        let request = try XCTUnwrap(server.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token fake-key")
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("fake-key"))

        server.reply(.text(#"{"type":"Results","is_final":true,"channel":{"alternatives":[{"transcript":"Hello"}]}}"#))
        server.reply(.text(#"{"type":"Results","is_final":false,"channel":{"alternatives":[{"transcript":"wor"}]}}"#))
        try await waitUntil { events.texts.last == "Hello wor" }
        let late = speech(0.3)
        session.append(late)

        let capture = early + late + speech(0.2)
        let finishing = Task { await session.finishTranscript(capture: capture) }
        try await waitUntil { server.sent.last == .text(#"{"type":"CloseStream"}"#) }
        let audioBytes = server.sent.compactMap { frame -> Int? in if case .data(let data) = frame { return data.count } else { return nil } }
        XCTAssertEqual(audioBytes.reduce(0, +), capture.count * 2, "Every sample is sent once as PCM16")
        server.reply(.text(#"{"type":"Results","is_final":true,"from_finalize":true,"channel":{"alternatives":[{"transcript":"world."}]}}"#))
        server.reply(.text(#"{"type":"Metadata","request_id":"r","duration":1.0,"channels":1}"#))
        let finished = await finishing.value
        let transcript = try XCTUnwrap(finished)
        XCTAssertEqual(transcript.text, "Hello world.")
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.engine, "deepgram:nova-3")
        XCTAssertTrue(server.closed)
        XCTAssertTrue(events.issues.isEmpty)
    }

    // MARK: xAI

    func testXAIRequestFramesAndParser() async throws {
        let provider = XAIStreaming(hints: TranscriptionHints(language: "en", vocabulary: ["Airdraft", "C++", " ", "Airdraft"]),
                                    engineID: "xAI:grok-voice-transcribe-2.0")
        XCTAssertTrue(provider.matchesBatchModel)
        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "api.x.ai")
        XCTAssertEqual(request.url?.path, "/v1/stt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("fake-key"))
        XCTAssertTrue(try XCTUnwrap(request.url).absoluteString.contains("keyterm=C%2B%2B"), "A plus sign stays literal")
        let items = try query(request)
        XCTAssertEqual(value("model", in: items), "grok-voice-transcribe-2.0")
        XCTAssertEqual(value("encoding", in: items), "pcm")
        XCTAssertEqual(value("sample_rate", in: items), "16000")
        XCTAssertEqual(value("interim_results", in: items), "true")
        XCTAssertEqual(value("language", in: items), "en")
        XCTAssertEqual(value("format", in: items), "true")
        XCTAssertEqual(values("keyterm", in: items), ["Airdraft", "C++"])

        // Automatic detection sends no language, so formatting (which needs one) is omitted.
        let automaticRequest = try await XAIStreaming(hints: TranscriptionHints(), engineID: "xAI").request(apiKey: "fake-key")
        let automatic = try query(automaticRequest)
        XCTAssertNil(value("language", in: automatic))
        XCTAssertNil(value("format", in: automatic))

        XCTAssertEqual(provider.startFrames(), [])
        let pcm = Data([5, 6])
        XCTAssertEqual(provider.audioFrame(pcm), .data(pcm))
        XCTAssertEqual(provider.endFrames(), [.text(#"{"type":"audio.done"}"#)])

        let parser = provider.makeParser()
        try parser.consume(.text(#"{"type":"transcript.created"}"#))
        try parser.consume(.text(#"{"type":"transcript.partial","text":"Hello","is_final":false,"speech_final":false}"#))
        XCTAssertEqual(parser.provisional, "Hello")
        XCTAssertEqual(parser.finalText, "")
        try parser.consume(.text(#"{"type":"transcript.partial","text":"Hello there,","is_final":true,"speech_final":false}"#))
        XCTAssertEqual(parser.finalText, "Hello there,")
        XCTAssertEqual(parser.provisional, "")
        try parser.consume(.text(#"{"type":"transcript.partial","text":"Hello there, world.","is_final":true,"speech_final":true}"#))
        XCTAssertEqual(parser.finalText, "Hello there, world.", "The utterance final replaces its chunks")
        try parser.consume(.text(#"{"type":"transcript.partial","text":"Bye.","is_final":true,"speech_final":false}"#))
        XCTAssertEqual(parser.finalText, "Hello there, world. Bye.")
        XCTAssertFalse(parser.finished)
        try parser.consume(.text(#"{"type":"transcript.done","text":"Hello there, world. Bye.","duration":3.2}"#))
        XCTAssertTrue(parser.finished)
        XCTAssertEqual(parser.finalText, "Hello there, world. Bye.")
        XCTAssertEqual(parser.language, "en")

        // transcript.done restating only the last utterance completes its chunks.
        let lastUtterance = XAIStreaming.Parser()
        try lastUtterance.consume(.text(#"{"type":"transcript.partial","text":"One.","is_final":true,"speech_final":true}"#))
        try lastUtterance.consume(.text(#"{"type":"transcript.partial","text":"Two","is_final":true,"speech_final":false}"#))
        try lastUtterance.consume(.text(#"{"type":"transcript.done","text":"Two three.","duration":2}"#))
        XCTAssertEqual(lastUtterance.finalText, "One. Two three.")

        // transcript.done alone carries the whole text.
        let doneOnly = XAIStreaming.Parser()
        try doneOnly.consume(.text(#"{"type":"transcript.done","text":"Only text.","duration":1}"#))
        XCTAssertEqual(doneOnly.finalText, "Only text.")
        XCTAssertTrue(doneOnly.finished)

        assertProviderError(XAIStreaming.Parser(), #"{"type":"error","message":"Invalid API key"}"#, "xAI: Invalid API key")
    }

    func testXAIStreamsEveryFrameAndItsFinalTextBecomesTheTranscript() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let provider = XAIStreaming(hints: TranscriptionHints(language: "en", vocabulary: ["Airdraft"]),
                                    engineID: "xAI:grok-voice-transcribe-2.0")
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertTrue(session.reusesForTranscript)
        let early = speech(0.5)
        session.append(early)
        server.openConnection()
        // Audio waits for transcript.created.
        try await waitUntil { server.request != nil }
        XCTAssertTrue(server.sent.isEmpty)
        server.reply(.text(#"{"type":"transcript.created"}"#))
        try await waitUntil { !server.sent.isEmpty }
        let request = try XCTUnwrap(server.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("fake-key"))

        server.reply(.text(#"{"type":"transcript.created"}"#))
        server.reply(.text(#"{"type":"transcript.partial","text":"Hello Air","is_final":false,"speech_final":false}"#))
        try await waitUntil { events.texts.last == "Hello Air" }
        let late = speech(0.3)
        session.append(late)

        let capture = early + late + speech(0.2)
        let finishing = Task { await session.finishTranscript(capture: capture) }
        try await waitUntil { server.sent.last == .text(#"{"type":"audio.done"}"#) }
        let audioBytes = server.sent.compactMap { frame -> Int? in if case .data(let data) = frame { return data.count } else { return nil } }
        XCTAssertEqual(audioBytes.reduce(0, +), capture.count * 2, "Every sample is sent once as PCM16")
        server.reply(.text(#"{"type":"transcript.partial","text":"Hello Airdraft,","is_final":true,"speech_final":false}"#))
        server.reply(.text(#"{"type":"transcript.partial","text":"Hello Airdraft, goodbye.","is_final":true,"speech_final":true}"#))
        server.reply(.text(#"{"type":"transcript.done","text":"Hello Airdraft, goodbye.","duration":1.0}"#))
        let finished = await finishing.value
        let transcript = try XCTUnwrap(finished)
        XCTAssertEqual(transcript.text, "Hello Airdraft, goodbye.")
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.engine, "xAI:grok-voice-transcribe-2.0")
        XCTAssertTrue(server.closed)
        XCTAssertTrue(events.issues.isEmpty)
    }

    // MARK: Cartesia

    func testCartesiaRequestFramesAndParser() async throws {
        let provider = CartesiaStreaming(hints: TranscriptionHints(language: "en", vocabulary: ["Airdraft"]),
                                         engineID: "cartesia:ink-whisper")
        XCTAssertTrue(provider.matchesBatchModel)
        let request = try await provider.request(apiKey: "fake-key")
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "api.cartesia.ai")
        XCTAssertEqual(request.url?.path, "/stt/websocket")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "fake-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cartesia-Version"), CartesiaTranscriber.apiVersion)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("fake-key"))
        let items = try query(request)
        XCTAssertEqual(value("model", in: items), "ink-whisper")
        XCTAssertEqual(value("language", in: items), "en")
        XCTAssertEqual(value("encoding", in: items), "pcm_s16le")
        XCTAssertEqual(value("sample_rate", in: items), "16000")
        XCTAssertEqual(value("cartesia_version", in: items), CartesiaTranscriber.apiVersion)
        XCTAssertNil(value("keyterm", in: items), "Ink-Whisper takes no keyterms, like the batch request")
        XCTAssertNil(value("api_key", in: items))
        XCTAssertNil(value("access_token", in: items))

        // Like the file endpoint, Ink-Whisper never streams without a language.
        do {
            _ = try await CartesiaStreaming(hints: TranscriptionHints(), engineID: "cartesia:ink-whisper").request(apiKey: "fake-key")
            XCTFail("Automatic language must be refused")
        } catch {
            XCTAssertTrue(error is SpeechLanguageError)
        }

        XCTAssertEqual(provider.startFrames(), [])
        let pcm = Data([7, 8])
        XCTAssertEqual(provider.audioFrame(pcm), .data(pcm))
        XCTAssertEqual(provider.endFrames(), [.text("close")])

        let parser = provider.makeParser()
        try parser.consume(.text(#"{"type":"transcript","is_final":false,"request_id":"r","text":"Hel"}"#))
        XCTAssertEqual(parser.provisional, "Hel")
        XCTAssertEqual(parser.finalText, "")
        try parser.consume(.text(#"{"type":"transcript","is_final":true,"request_id":"r","text":"Hello","language":"en"}"#))
        try parser.consume(.text(#"{"type":"transcript","is_final":true,"request_id":"r","text":" world."}"#))
        XCTAssertEqual(parser.finalText, "Hello world.", "Deltas carry their own spacing")
        XCTAssertEqual(parser.provisional, "")
        try parser.consume(.text(#"{"type":"flush_done","request_id":"r"}"#))
        XCTAssertFalse(parser.finished)
        try parser.consume(.text(#"{"type":"done","request_id":"r"}"#))
        XCTAssertTrue(parser.finished)
        XCTAssertEqual(parser.language, "en")

        assertProviderError(CartesiaStreaming.Parser(),
                            #"{"type":"error","status_code":401,"title":"Unauthorized","message":"Invalid API key"}"#,
                            "Cartesia: Invalid API key")
    }

    func testCartesiaStreamsEveryFrameAndItsFinalTextBecomesTheTranscript() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let provider = CartesiaStreaming(hints: TranscriptionHints(language: "en"), engineID: "cartesia:ink-whisper")
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertTrue(session.reusesForTranscript)
        let early = speech(0.5)
        session.append(early)
        server.openConnection()
        try await waitUntil { !server.sent.isEmpty }
        let request = try XCTUnwrap(server.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "fake-key")
        XCTAssertFalse(try XCTUnwrap(request.url).absoluteString.contains("fake-key"))

        server.reply(.text(#"{"type":"transcript","is_final":true,"request_id":"r","text":"Hello"}"#))
        server.reply(.text(#"{"type":"transcript","is_final":false,"request_id":"r","text":" wor"}"#))
        try await waitUntil { events.texts.last == "Hello wor" }
        let late = speech(0.3)
        session.append(late)

        let capture = early + late + speech(0.2)
        let finishing = Task { await session.finishTranscript(capture: capture) }
        try await waitUntil { server.sent.last == .text("close") }
        let audioBytes = server.sent.compactMap { frame -> Int? in if case .data(let data) = frame { return data.count } else { return nil } }
        XCTAssertEqual(audioBytes.reduce(0, +), capture.count * 2, "Every sample is sent once as PCM16")
        server.reply(.text(#"{"type":"transcript","is_final":true,"request_id":"r","text":" world."}"#))
        server.reply(.text(#"{"type":"done","request_id":"r"}"#))
        let finished = await finishing.value
        let transcript = try XCTUnwrap(finished)
        XCTAssertEqual(transcript.text, "Hello world.")
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.engine, "cartesia:ink-whisper")
        XCTAssertTrue(server.closed)
        XCTAssertTrue(events.issues.isEmpty)
    }

    func testProviderErrorDuringSessionStopsLiveTextWithOneIssue() async throws {
        let cases: [(any StreamingSpeechProvider, String, String)] = [
            (DeepgramStreaming(model: "nova-3", hints: TranscriptionHints(language: "en"), engineID: "deepgram:nova-3"),
             #"{"type":"Error","variant":"DataError","description":"Bad audio"}"#, "Bad audio"),
            (XAIStreaming(hints: TranscriptionHints(language: "en"), engineID: "xAI:grok-voice-transcribe-2.0"),
             #"{"type":"error","message":"Invalid API key"}"#, "Invalid API key"),
            (CartesiaStreaming(hints: TranscriptionHints(language: "en"), engineID: "cartesia:ink-whisper"),
             #"{"type":"error","status_code":401,"title":"Unauthorized","message":"Invalid API key"}"#, "Invalid API key"),
        ]
        for (provider, reply, message) in cases {
            let server = FakeStreamingServer()
            let events = CloudEventLog()
            let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                     onText: { events.text($0) }, onIssue: { events.issue($0) })
            session.append(speech(0.1))
            server.openConnection()
            try await waitUntil { server.request != nil }
            server.reply(.text(reply))
            try await waitUntil { events.issues.count == 1 }
            XCTAssertTrue(events.issues[0].contains(message), events.issues[0])
            let result = await session.finishTranscript(capture: speech(0.2))
            XCTAssertNil(result)
        }
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
