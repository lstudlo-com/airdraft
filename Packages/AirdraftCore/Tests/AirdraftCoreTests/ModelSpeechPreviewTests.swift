import XCTest
@testable import AirdraftCore

/// AD-084: cadence, window bounds, cancellation and mixing for model-driven live text.
/// A fake clock and decoder make the cadence deterministic; no engine or audio device runs.
final class ModelSpeechPreviewTests: XCTestCase {
    private func seconds(_ value: Double, level: Float = 0.1) -> [Float] {
        [Float](repeating: level, count: Int(value * 16_000))
    }

    func testCadenceRespectsMinimumIntervalNewAudioAndDecodeCostBackoff() async throws {
        do { // DecodesRespectMinimumIntervalAndNewAudio
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.2)
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            defer { session.cancel() }

            session.append(seconds(3))
            try await waitUntil { decoder.calls.count == 1 }
            // No new audio: polling continues without another decode.
            try await clock.waitUntilTime(clock.now + 5)
            XCTAssertEqual(decoder.calls.count, 1)

            // Less than the 0.5-second minimum of new audio does not decode.
            session.append(seconds(0.25))
            try await clock.waitUntilTime(clock.now + 3)
            XCTAssertEqual(decoder.calls.count, 1)

            session.append(seconds(0.3))
            try await waitUntil { decoder.calls.count == 2 }
            let calls = decoder.calls
            XCTAssertEqual(calls[0].samples, 48_000)
            XCTAssertEqual(calls[1].samples, 56_800)
            XCTAssertGreaterThanOrEqual(calls[1].start - calls[0].start, 1.0 + 0.2 - 1e-9)
            try await waitUntil { events.texts.last == "n56800" }
            XCTAssertEqual(decoder.maximumConcurrent, 1)
        }

        do { // CadenceBacksOffToTwiceTheDecodeCost
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.8)
            let session = makeSession(clock: clock, decoder: decoder, events: PreviewEventLog())
            defer { session.cancel() }

            session.append(seconds(1))
            try await waitUntil { decoder.calls.count == 1 }
            for _ in 0..<4 {
                session.append(seconds(1))
                let count = decoder.calls.count
                try await waitUntil { decoder.calls.count == count + 1 }
            }
            let starts = decoder.calls.map(\.start)
            // Each start waits for the previous end plus 2 x 0.8 s.
            for (earlier, later) in zip(starts, starts.dropFirst()) {
                XCTAssertGreaterThanOrEqual(later - earlier, 0.8 + 1.6 - 1e-9)
            }
            let intervals = session.metrics.intervals
            XCTAssertEqual(intervals.count, 4)
            XCTAssertTrue(intervals.allSatisfy { $0 >= 2.4 - 1e-9 })
        }
    }

    /// The window commits at a quiet point and bounds every decode, the buffer drops the
    /// oldest audio while decodes are skipped, and the display is a bounded tail.
    func testWindowBufferAndDisplayStayBounded() async throws {
        do { // WindowCommitsAtQuietPointAndBoundsEveryDecode
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            defer { session.cancel() }

            // 12 s of speech with a silent 100 ms frame at 8.0 s, inside the 7-10 s search span.
            var audio = seconds(12, level: 0.3)
            for index in 128_000..<129_600 { audio[index] = 0 }
            session.append(audio)
            try await waitUntil { decoder.calls.count >= 2 }
            let calls = decoder.calls
            XCTAssertEqual(calls[0].samples, 128_800, "Commit cuts at the quiet frame's centre")
            XCTAssertEqual(calls[1].samples, 192_000 - 128_800, "Provisional text covers only the uncommitted tail")
            XCTAssertTrue(calls.allSatisfy { $0.samples <= 160_000 })
            try await waitUntil { events.texts.last == "n128800 n63200" }
            XCTAssertEqual(session.metrics.commits, 1)
            XCTAssertLessThanOrEqual(session.metrics.longestWindowSamples, 160_000)
        }

        do { // BufferDropsOldestAudioWhileDecodesAreSkipped
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            decoder.busy = true
            let session = makeSession(clock: clock, decoder: decoder, events: PreviewEventLog())
            defer { session.cancel() }

            for _ in 0..<25 { session.append(seconds(1)) }
            try await waitUntil { session.metrics.skippedBusy >= 1 }
            XCTAssertGreaterThan(session.metrics.droppedSamples, 0)
            XCTAssertEqual(session.metrics.decodes, 0)
            XCTAssertTrue(decoder.calls.allSatisfy { $0.samples <= 20 * 16_000 })
        }

        do { // DisplayIsBoundedTail
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            decoder.text = { String(repeating: "word ", count: 400) + "end\($0)" }
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            defer { session.cancel() }
            session.append(seconds(1))
            try await waitUntil { !events.texts.isEmpty }
            let shown = try XCTUnwrap(events.texts.last)
            XCTAssertLessThanOrEqual(shown.count, 500)
            XCTAssertGreaterThan(shown.count, 470)
            XCTAssertTrue(shown.hasPrefix("word "), "The bounded tail starts at a word boundary")
            XCTAssertTrue(shown.hasSuffix("end16000"))
            let chinese = String(repeating: "我們開會", count: 200)
            XCTAssertEqual(ModelSpeechPreview.tail(chinese, maximum: 500).count, 500, "Unspaced text keeps the full bound")
        }
    }

    /// A slow decode stops with one nonfatal issue, errors and invalid audio stop once,
    /// cancel during a decode drops its result and later audio, and a preempted decode
    /// retries without an issue.
    func testSlowFailedCancelledAndPreemptedDecodes() async throws {
        do { // SlowDecodeStopsPreviewWithNonfatalIssue
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 3.5)
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            session.append(seconds(2))
            try await waitUntil { !events.issues.isEmpty }
            XCTAssertFalse(session.isActive)
            XCTAssertTrue(events.texts.isEmpty, "A too-slow result is never shown")
            XCTAssertEqual(events.issues.count, 1)
            session.append(seconds(2))
            XCTAssertEqual(decoder.calls.count, 1)
        }

        do { // DecoderErrorAndInvalidAudioStopPreviewOnce
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            decoder.failure = TranscriberError.invalidResponse
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            session.append(seconds(1))
            try await waitUntil { events.issues.count == 1 }
            XCTAssertFalse(session.isActive)

            let invalidEvents = PreviewEventLog()
            let invalid = makeSession(clock: FakePreviewClock(), decoder: FakePreviewDecoder(clock: clock, cost: 0), events: invalidEvents)
            invalid.append([0.1, .nan])
            XCTAssertEqual(invalidEvents.issues.count, 1)
            invalid.append([.infinity])
            XCTAssertEqual(invalidEvents.issues.count, 1)
            XCTAssertFalse(invalid.isActive)
        }

        do { // CancelDuringDecodeDropsItsResultAndLaterAudio
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0)
            decoder.gate = true
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            session.append(seconds(1))
            try await waitUntil { decoder.waiting }
            session.cancel()
            decoder.release()
            session.append(seconds(5))
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(events.texts.isEmpty, "A decode that finished after cancel is never published")
            XCTAssertTrue(events.issues.isEmpty, "Cancellation is not an issue")
            XCTAssertFalse(session.isActive)
            XCTAssertEqual(decoder.calls.count, 1)
        }

        do { // PreemptedDecodeRetriesWithoutIssue
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            decoder.cancellations = 1
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events)
            defer { session.cancel() }
            session.append(seconds(1))
            try await waitUntil { events.texts == ["n16000"] }
            XCTAssertTrue(events.issues.isEmpty)
            XCTAssertEqual(decoder.calls.count, 2)
            XCTAssertEqual(session.metrics.preempted, 1)
        }
    }

    func testJoinQuietestCutAndMeetingMixerTimeline() {
        do { // JoinAndQuietestCut
            XCTAssertEqual(ModelSpeechPreview.join("Hello there", "general"), "Hello there general")
            XCTAssertEqual(ModelSpeechPreview.join("我們開會", "然後討論"), "我們開會然後討論")
            XCTAssertEqual(ModelSpeechPreview.join("Done", ", next"), "Done, next")
            XCTAssertEqual(ModelSpeechPreview.join("", " tail "), "tail")
            XCTAssertEqual(ModelSpeechPreview.join("head", ""), "head")
            var samples = [Float](repeating: 0.5, count: 48_000)
            for index in 20_000..<21_600 { samples[index] = 0 }
            XCTAssertEqual(ModelSpeechPreview.quietestCut(samples, in: 16_000..<32_000), 20_800)
            XCTAssertEqual(ModelSpeechPreview.quietestCut(samples, in: 0..<100), 100)
        }

        do { // MeetingMixerAveragesTracksOnOneTimeline
            let output = Locked<[Float]>([])
            let mixer = MeetingPreviewMixer(lagSeconds: 0.1) { chunk in output.withLock { $0.append(contentsOf: chunk) } }
            // Capture delivers both tracks in small interleaved chunks (20 ms here) for 0.5 s.
            for index in 0..<25 {
                let offset = Double(index) * 0.02
                mixer.append([Float](repeating: 0.4, count: 320), track: .microphone, at: offset)
                mixer.append([Float](repeating: 0.2, count: 320), track: .system, at: offset)
            }
            let mixed = output.value
            XCTAssertEqual(mixed.count, 8_000 - 1_600, "Audio newer than the lag waits for the other track")
            // Both sources cover every emitted sample, so each is their average (the saved mix rule).
            XCTAssertTrue(mixed.allSatisfy { abs($0 - 0.3) < 1e-6 })
            // Late audio for an emitted span never reappears.
            mixer.append([Float](repeating: 0.9, count: 800), track: .system, at: 0)
            XCTAssertEqual(output.value.count, 6_400)
            // A single source keeps its level.
            let single = Locked<[Float]>([])
            let solo = MeetingPreviewMixer(lagSeconds: 0) { chunk in single.withLock { $0.append(contentsOf: chunk) } }
            solo.append([Float](repeating: 0.25, count: 1_600), track: .system, at: 1)
            XCTAssertEqual(single.value.count, 17_600, "Leading time before the first chunk is silence on the timeline")
            XCTAssertEqual(single.value.suffix(1_600).allSatisfy { $0 == 0.25 }, true)
            mixer.finish()
            mixer.append([Float](repeating: 0.4, count: 16_000), track: .microphone, at: 0.5)
            XCTAssertEqual(output.value.count, 6_400)
        }
    }

    func testSupportedEnginesNoticesAndAppleSpeechPreviewLocale() {
        XCTAssertTrue(ModelSpeechPreview.supports(ASRConfig(kind: .parakeet)))
        XCTAssertTrue(ModelSpeechPreview.supports(ASRConfig(kind: .senseVoice)))
        XCTAssertTrue(ModelSpeechPreview.supports(ASRConfig(kind: .orukeet)))
        for kind in [ASRProviderKind.whisperKit, .qwen3, .cohere, .fireRed, .transcribeCpp, .fluidAudio,
                     .openAI, .deepgram, .soniox, .groq] {
            XCTAssertFalse(ModelSpeechPreview.supports(ASRConfig(kind: kind)), kind.rawValue)
            XCTAssertNotNil(ModelSpeechPreview.unavailableReason(for: ASRConfig(kind: kind)), kind.rawValue)
            XCTAssertNil(ModelSpeechPreview.appleSpeechLocale(for: ASRConfig(kind: kind)), kind.rawValue)
        }

        // The recording window's notice names the model in one short phrase; the
        // longer Settings reason keeps its alternatives.
        let whisper = ASRConfig(kind: .whisperKit)
        let notice = try? XCTUnwrap(ModelSpeechPreview.recordingNotice(for: whisper))
        XCTAssertEqual(notice, "\(whisper.modelDisplayName) doesn’t support live text")
        XCTAssertNotEqual(notice, ModelSpeechPreview.unavailableReason(for: whisper))
        XCTAssertNil(ModelSpeechPreview.recordingNotice(for: ASRConfig(kind: .apple, appleLocale: "en-US", language: "")))

        // Apple Speech never decodes through the factory, but previews with its own
        // analyzer in the model's effective locale, so it is not unavailable.
        let apple = ASRConfig(kind: .apple, appleLocale: "ja-JP", language: "")
        XCTAssertFalse(ModelSpeechPreview.supports(apple))
        XCTAssertEqual(ModelSpeechPreview.appleSpeechLocale(for: apple), "ja-JP")
        XCTAssertNil(ModelSpeechPreview.unavailableReason(for: apple, installed: false))
        let mandarin = ASRConfig(kind: .apple, appleLocale: "zh-TW", language: "zh", chineseScript: .simplified)
        XCTAssertEqual(ModelSpeechPreview.appleSpeechLocale(for: mandarin), "zh-CN")
    }

    /// AD-123: committed windows plus the tail decoded at release are the transcript;
    /// a busy engine never drops audio; failure, cancellation, a failed tail and a
    /// display-only session give nil so the pipeline transcribes again.
    func testLiveTextBecomesTranscriptOnlyWhenItCoversTheRecording() async throws {
        do { // CommittedWindowsAndTailFormTheTranscript
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            let finals = FakeLiveFinals()
            let events = PreviewEventLog()
            let session = makeSession(clock: clock, decoder: decoder, events: events, finals: finals.finals)
            defer { session.cancel() }
            XCTAssertTrue(session.reusesForTranscript)

            var audio = seconds(12, level: 0.3)
            for index in 128_000..<129_600 { audio[index] = 0 }
            session.append(audio)
            try await waitUntil { session.metrics.commits == 1 }
            XCTAssertEqual(finals.segments, [128_800], "The committed window goes through the guarded segment path")
            try await waitUntil { events.texts.contains { $0.hasPrefix("shown128800") } }

            // The recording ends a second later; the tail starts at the commit.
            let capture = audio + seconds(1, level: 0.3)
            let finished = await session.finishTranscript(capture: capture)
            let transcript = try XCTUnwrap(finished)
            XCTAssertEqual(transcript.text, "seg128800 tail\(capture.count - 128_800)")
            XCTAssertEqual(transcript.engine, "fake-engine")
            XCTAssertEqual(transcript.adjustments, [.repetitionTrimmed, .repetitionTrimmed])
            XCTAssertEqual(finals.tails, [capture.count - 128_800])
            let shown = events.texts.count
            session.append(seconds(2))
            try await clock.waitUntilTime(clock.now + 3)
            XCTAssertEqual(events.texts.count, shown, "No live text after finishing")
        }

        do { // BusyEngineNeverDropsAudio
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            decoder.busy = true
            let finals = FakeLiveFinals()
            finals.busy = true
            let session = makeSession(clock: clock, decoder: decoder, events: PreviewEventLog(), finals: finals.finals)
            defer { session.cancel() }
            var capture: [Float] = []
            for _ in 0..<25 { let second = seconds(1); capture += second; session.append(second) }
            try await waitUntil { finals.segmentCalls >= 1 }
            XCTAssertEqual(session.metrics.droppedSamples, 0)
            let finished = await session.finishTranscript(capture: capture)
            let transcript = try XCTUnwrap(finished)
            XCTAssertEqual(transcript.text, "tail400000", "The whole recording is decoded at release")
        }

        do { // FailureCancellationFailedTailAndDisplayOnlyGiveNil
            let clock = FakePreviewClock()
            let decoder = FakePreviewDecoder(clock: clock, cost: 0.1)
            decoder.failure = .invalidResponse
            let failed = makeSession(clock: clock, decoder: decoder, events: PreviewEventLog(), finals: FakeLiveFinals().finals)
            failed.append(seconds(1))
            try await waitUntil { !failed.isActive }
            let none = await failed.finishTranscript(capture: seconds(1))
            XCTAssertNil(none, "A failed session cannot stand in for the model")

            let cancelled = makeSession(clock: FakePreviewClock(), decoder: FakePreviewDecoder(clock: clock, cost: 0.1),
                                        events: PreviewEventLog(), finals: FakeLiveFinals().finals)
            cancelled.cancel()
            let afterCancel = await cancelled.finishTranscript(capture: seconds(1))
            XCTAssertNil(afterCancel)

            let tailFails = FakeLiveFinals()
            tailFails.tailFails = true
            let failing = makeSession(clock: FakePreviewClock(), decoder: FakePreviewDecoder(clock: clock, cost: 0.1),
                                      events: PreviewEventLog(), finals: tailFails.finals)
            let afterTailFailure = await failing.finishTranscript(capture: seconds(1))
            XCTAssertNil(afterTailFailure)

            let displayOnly = makeSession(clock: FakePreviewClock(), decoder: FakePreviewDecoder(clock: clock, cost: 0.1),
                                          events: PreviewEventLog())
            XCTAssertFalse(displayOnly.reusesForTranscript)
            let displayResult = await displayOnly.finishTranscript(capture: seconds(1))
            XCTAssertNil(displayResult)

            let trimmed = makeSession(clock: FakePreviewClock(), decoder: FakePreviewDecoder(clock: clock, cost: 0.1),
                                      events: PreviewEventLog(), finals: FakeLiveFinals().finals)
            let silentResult = await trimmed.finishTranscript(capture: [Float](repeating: 0, count: 8_000))
            let silent = try XCTUnwrap(silentResult)
            XCTAssertTrue(silent.isEmpty, "A silent tail is not decoded")
        }
    }

    // MARK: - Helpers

    private func makeSession(clock: FakePreviewClock, decoder: FakePreviewDecoder, events: PreviewEventLog,
                             policy: ModelPreviewPolicy = .standard, finals: ModelPreviewFinals? = nil) -> ModelPreviewSession {
        ModelSpeechPreview.start(policy: policy, decode: { try await decoder.decode($0) }, finals: finals,
                                 onText: { events.addText($0) }, onIssue: { events.addIssue($0) },
                                 now: { clock.now }, sleep: { try await clock.sleep($0) })
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out", file: file, line: line)
    }
}

/// AD-123: segment and tail decoders that record their window sizes.
final class FakeLiveFinals: Sendable {
    private struct State {
        var segments: [Int] = []
        var segmentCalls = 0
        var tails: [Int] = []
        var busy = false
        var tailFails = false
    }
    private let state = Locked(State())
    var segments: [Int] { state.value.segments }
    var segmentCalls: Int { state.value.segmentCalls }
    var tails: [Int] { state.value.tails }
    var busy: Bool { get { state.value.busy } set { state.withLock { $0.busy = newValue } } }
    var tailFails: Bool { get { state.value.tailFails } set { state.withLock { $0.tailFails = newValue } } }

    var finals: ModelPreviewFinals {
        ModelPreviewFinals(segment: { [self] samples in
            let busy = state.withLock { state -> Bool in
                state.segmentCalls += 1
                if !state.busy { state.segments.append(samples.count) }
                return state.busy
            }
            guard !busy else { return nil }
            return (Transcript(text: "seg\(samples.count)", engine: "fake-engine", latencyMs: 1, adjustments: [.repetitionTrimmed]),
                    "shown\(samples.count)")
        }, tail: { [self] samples in
            let fails = state.withLock { state -> Bool in
                state.tails.append(samples.count)
                return state.tailFails
            }
            if fails { throw TranscriberError.invalidResponse }
            return Transcript(text: "tail\(samples.count)", engine: "fake-engine", latencyMs: 1, adjustments: [.repetitionTrimmed])
        })
    }
}

/// Simulated time: each sleep advances it, then yields to real tasks.
final class FakePreviewClock: Sendable {
    private let time = Locked(0.0)
    var now: Double { time.value }
    func advance(_ seconds: Double) { time.withLock { $0 += max(0, seconds) } }
    func sleep(_ seconds: Double) async throws {
        try Task.checkCancellation()
        advance(seconds)
        // A real pause keeps the polling loop from monopolising the test's executor.
        try await Task.sleep(for: .microseconds(200))
    }
    func waitUntilTime(_ target: Double) async throws {
        let deadline = Date().addingTimeInterval(3)
        while now < target, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
    }
}

final class PreviewEventLog: Sendable {
    private let state = Locked((texts: [String](), issues: [String]()))
    var texts: [String] { state.value.texts }
    var issues: [String] { state.value.issues }
    func addText(_ text: String) { state.withLock { $0.texts.append(text) } }
    func addIssue(_ issue: String) { state.withLock { $0.issues.append(issue) } }
}

/// Records each window, its simulated start time and concurrency.
final class FakePreviewDecoder: Sendable {
    struct Call: Sendable { let samples: Int; let start: Double }
    private struct State {
        var calls: [Call] = []
        var active = 0
        var maximumActive = 0
        var busy = false
        var failure: TranscriberError?
        var gate = false
        var waiter: CheckedContinuation<Void, Never>?
        var released = false
        var cancellations = 0
        var text: @Sendable (Int) -> String = { "n\($0)" }
    }
    private let state = Locked(State())
    private let clock: FakePreviewClock
    private let cost: Double

    init(clock: FakePreviewClock, cost: Double) {
        self.clock = clock
        self.cost = cost
    }

    var calls: [Call] { state.value.calls }
    var maximumConcurrent: Int { state.value.maximumActive }
    var waiting: Bool { state.value.waiter != nil }
    var busy: Bool { get { state.value.busy } set { state.withLock { $0.busy = newValue } } }
    var failure: TranscriberError? { get { state.value.failure } set { state.withLock { $0.failure = newValue } } }
    var gate: Bool { get { state.value.gate } set { state.withLock { $0.gate = newValue } } }
    var cancellations: Int { get { state.value.cancellations } set { state.withLock { $0.cancellations = newValue } } }
    var text: @Sendable (Int) -> String { get { state.value.text } set { state.withLock { $0.text = newValue } } }

    func release() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume()
    }

    func decode(_ samples: [Float]) async throws -> String? {
        let start = clock.now
        let setup = state.withLock { state -> (busy: Bool, failure: TranscriberError?, gate: Bool, cancel: Bool) in
            state.calls.append(Call(samples: samples.count, start: start))
            state.active += 1
            state.maximumActive = max(state.maximumActive, state.active)
            let cancel = state.cancellations > 0
            if cancel { state.cancellations -= 1 }
            return (state.busy, state.failure, state.gate && !state.released, cancel)
        }
        defer { state.withLock { $0.active -= 1 } }
        if setup.gate {
            await withCheckedContinuation { continuation in
                let resumeNow = state.withLock { state -> Bool in
                    if state.released { return true }
                    state.waiter = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        clock.advance(cost)
        if setup.cancel { throw CancellationError() }
        if let failure = setup.failure { throw failure }
        if setup.busy { return nil }
        return text(samples.count)
    }
}
