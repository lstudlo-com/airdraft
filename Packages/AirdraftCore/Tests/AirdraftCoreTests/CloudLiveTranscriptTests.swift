import XCTest
@testable import AirdraftCore

/// AD-123: cloud live text against a scripted connection. No test reaches a
/// provider; keys are fake and must never appear in a URL.
final class CloudLiveTranscriptTests: XCTestCase {
    private func speech(_ seconds: Double, level: Float = 0.2) -> [Float] {
        [Float](repeating: level, count: Int(seconds * 16_000))
    }

    func testSonioxStreamsEveryFrameAndItsFinalTextBecomesTheTranscript() async throws {
        let server = FakeStreamingServer()
        let events = CloudEventLog()
        let provider = SonioxStreaming(hints: TranscriptionHints(language: "en", vocabulary: ["Airdraft"]), engineID: "soniox:stt-async-v5")
        let session = CloudLiveTranscriptSession(provider: provider, apiKey: "fake-key", connector: server.connector,
                                                 onText: { events.text($0) }, onIssue: { events.issue($0) })
        XCTAssertTrue(session.reusesForTranscript)
        // Audio arrives before the connection opens and is kept.
        let early = speech(0.5)
        session.append(early)
        server.openConnection()
        try await waitUntil { server.sent.count >= 2 }
        let request = try XCTUnwrap(server.request)
        XCTAssertEqual(request.url?.absoluteString, "wss://stt-rt.soniox.com/transcribe-websocket")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-key")
        XCTAssertFalse(request.url!.absoluteString.contains("fake-key"))
        let config = try XCTUnwrap(server.sent.first?.jsonObject)
        XCTAssertEqual(config["model"] as? String, "stt-rt-v5")
        XCTAssertEqual(config["audio_format"] as? String, "pcm_s16le")
        XCTAssertEqual(config["sample_rate"] as? Int, 16_000)
        XCTAssertEqual(config["language_hints"] as? [String], ["en"])
        XCTAssertEqual((config["context"] as? [String: Any])?["terms"] as? [String], ["Airdraft"])

        server.reply(.text(#"{"tokens":[{"text":"Hello","is_final":true,"language":"en"},{"text":" wor","is_final":false}]}"#))
        try await waitUntil { events.texts.last == "Hello wor" }
        let late = speech(0.3)
        session.append(late)

        // At release the capture also holds 0.2 s the session never received.
        let capture = early + late + speech(0.2)
        let finishing = Task { await session.finishTranscript(capture: capture) }
        try await waitUntil { server.sent.last == .text("") }
        let audioBytes = server.sent.compactMap { frame -> Int? in if case .data(let data) = frame { return data.count } else { return nil } }
        XCTAssertEqual(audioBytes.reduce(0, +), capture.count * 2, "Every sample is sent once as PCM16")
        server.reply(.text(#"{"tokens":[{"text":" world","is_final":true},{"text":"<fin>","is_final":true}]}"#))
        server.reply(.text(#"{"tokens":[],"finished":true}"#))
        let finished = await finishing.value
        let transcript = try XCTUnwrap(finished)
        XCTAssertEqual(transcript.text, "Hello world")
        XCTAssertEqual(transcript.language, "en")
        XCTAssertEqual(transcript.engine, "soniox:stt-async-v5")
        XCTAssertTrue(server.closed)
        XCTAssertTrue(events.issues.isEmpty)
    }

    func testProviderErrorsDisplayOnlyModelsDeadlinesAndCancelGiveNoTranscript() async throws {
        do { // ProviderErrorStopsLiveTextWithOneIssue
            let server = FakeStreamingServer()
            let events = CloudEventLog()
            let session = CloudLiveTranscriptSession(provider: SonioxStreaming(hints: TranscriptionHints(), engineID: "soniox"),
                                                     apiKey: "fake-key", connector: server.connector,
                                                     onText: { events.text($0) }, onIssue: { events.issue($0) })
            server.openConnection()
            try await waitUntil { !server.sent.isEmpty }
            server.reply(.text(#"{"error_code":401,"error_type":"unauthenticated","error_message":"Invalid API key"}"#))
            try await waitUntil { events.issues.count == 1 }
            XCTAssertTrue(events.issues[0].contains("Invalid API key"))
            let result = await session.finishTranscript(capture: speech(0.2))
            XCTAssertNil(result)
        }

        do { // DisplayOnlyModelNeverStandsIn
            let server = FakeStreamingServer()
            let session = CloudLiveTranscriptSession(provider: DisplayOnlyStreaming(), apiKey: "fake-key", connector: server.connector,
                                                     onText: { _ in }, onIssue: { _ in })
            XCTAssertFalse(session.reusesForTranscript)
            server.openConnection()
            try await waitUntil { server.request != nil }
            let result = await session.finishTranscript(capture: speech(0.2))
            XCTAssertNil(result)
            try await waitUntil { server.closed }
        }

        do { // SilentProviderMissesTheDeadline
            let server = FakeStreamingServer()
            let session = CloudLiveTranscriptSession(provider: SonioxStreaming(hints: TranscriptionHints(), engineID: "soniox"),
                                                     apiKey: "fake-key", connector: server.connector, finishSeconds: 0.2,
                                                     onText: { _ in }, onIssue: { _ in })
            server.openConnection()
            let result = await session.finishTranscript(capture: speech(0.2))
            XCTAssertNil(result, "Release does not wait past the deadline")
            try await waitUntil { server.closed }
        }

        do { // CancelStopsCallbacks
            let server = FakeStreamingServer()
            let events = CloudEventLog()
            let session = CloudLiveTranscriptSession(provider: SonioxStreaming(hints: TranscriptionHints(), engineID: "soniox"),
                                                     apiKey: "fake-key", connector: server.connector,
                                                     onText: { events.text($0) }, onIssue: { events.issue($0) })
            server.openConnection()
            try await waitUntil { !server.sent.isEmpty }
            session.cancel()
            server.reply(.text(#"{"tokens":[{"text":"late","is_final":true}]}"#))
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(events.texts.isEmpty)
            XCTAssertTrue(events.issues.isEmpty)
            let result = await session.finishTranscript(capture: speech(0.2))
            XCTAssertNil(result)
        }
    }

    func testRegistryAndPCMConversion() {
        XCTAssertTrue(CloudStreaming.supports(ASRConfig(kind: .soniox)))
        XCTAssertTrue(CloudStreaming.becomesTranscript(ASRConfig(kind: .soniox)))
        XCTAssertFalse(CloudStreaming.supports(ASRConfig(kind: .groq)))
        XCTAssertFalse(CloudStreaming.supports(ASRConfig(kind: .openRouter)))
        XCTAssertTrue(ModelSpeechPreview.showsLiveText(ASRConfig(kind: .soniox)))
        XCTAssertNil(ModelSpeechPreview.unavailableReason(for: ASRConfig(kind: .soniox), installed: false))

        let data = CloudLiveTranscript.pcm16([0, 1, -1, 2, .nan])
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Int16(littleEndian: $0) }
        XCTAssertEqual(values, [0, 32_767, -32_767, 32_767, 0])
        XCTAssertEqual(CloudLiveTranscript.resample([Float](repeating: 0.5, count: 16_000), to: 24_000).count, 24_000)
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

/// A provider whose streaming model is not the batch model.
private struct DisplayOnlyStreaming: StreamingSpeechProvider {
    var matchesBatchModel: Bool { false }
    var engineID: String { "display-only" }
    func request(apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "wss://example.invalid/stream")!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Key")
        return request
    }
    func startFrames() -> [StreamingFrame] { [] }
    func audioFrame(_ pcm16: Data) -> StreamingFrame { .data(pcm16) }
    func endFrames() -> [StreamingFrame] { [] }
    func makeParser() -> any StreamingParser { SonioxStreaming.Parser() }
}

final class CloudEventLog: Sendable {
    private let state = Locked((texts: [String](), issues: [String]()))
    var texts: [String] { state.value.texts }
    var issues: [String] { state.value.issues }
    func text(_ value: String) { state.withLock { $0.texts.append(value) } }
    func issue(_ value: String) { state.withLock { $0.issues.append(value) } }
}

/// One scripted connection: the test opens it, sees every frame sent and replies.
final class FakeStreamingServer: Sendable {
    private struct State {
        var request: URLRequest?
        var sent: [StreamingFrame] = []
        var replies: [StreamingFrame] = []
        var receiver: CheckedContinuation<StreamingFrame, Error>?
        var opener: CheckedContinuation<Void, Never>?
        var open = false
        var closed = false
    }
    private let state = Locked(State())
    var request: URLRequest? { state.value.request }
    var sent: [StreamingFrame] { state.value.sent }
    var closed: Bool { state.value.closed }

    var connector: StreamingConnector {
        { [self] request in
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> Bool in
                    state.request = request
                    if state.open { return true }
                    state.opener = continuation
                    return false
                }
                if ready { continuation.resume() }
            }
            return Connection(server: self)
        }
    }

    func openConnection() {
        let opener = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.open = true
            defer { state.opener = nil }
            return state.opener
        }
        opener?.resume()
    }

    func reply(_ frame: StreamingFrame) {
        let receiver = state.withLock { state -> CheckedContinuation<StreamingFrame, Error>? in
            guard let receiver = state.receiver else { state.replies.append(frame); return nil }
            state.receiver = nil
            return receiver
        }
        receiver?.resume(returning: frame)
    }

    fileprivate func send(_ frame: StreamingFrame) throws {
        try state.withLock { state in
            guard !state.closed else { throw StreamingError.closed }
            state.sent.append(frame)
        }
    }

    fileprivate func receive() async throws -> StreamingFrame {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = state.withLock { state -> Result<StreamingFrame, Error>? in
                if state.closed { return .failure(StreamingError.closed) }
                if !state.replies.isEmpty { return .success(state.replies.removeFirst()) }
                state.receiver = continuation
                return nil
            }
            if let immediate { continuation.resume(with: immediate) }
        }
    }

    fileprivate func close() {
        let receiver = state.withLock { state -> CheckedContinuation<StreamingFrame, Error>? in
            state.closed = true
            defer { state.receiver = nil }
            return state.receiver
        }
        receiver?.resume(throwing: StreamingError.closed)
    }

    private struct Connection: StreamingConnection {
        let server: FakeStreamingServer
        func send(_ frame: StreamingFrame) async throws { try server.send(frame) }
        func receive() async throws -> StreamingFrame { try await server.receive() }
        func close() { server.close() }
    }
}
