import XCTest
@testable import AirdraftCore

@MainActor
final class MemoryPressureTests: XCTestCase {
    private let config = ASRConfig(kind: .parakeet)

    /// An idle model unloads and reloads normally, a recently used model survives warning but
    /// not critical pressure, and a pinned model stays resident until released.
    func testPressureUnloadsIdleModelsButKeepsRecentUnderWarningAndPinned() async throws {
        do { // IdleModelUnloadsUnderPressure
            let (factory, status, speech, clock) = try await loadedFactory()
            clock.advance(MemoryPressureLevel.warning.minimumIdleSeconds + 1)
            let result = await factory.unloadForMemoryPressure(minimumIdleSeconds: MemoryPressureLevel.warning.minimumIdleSeconds)
            XCTAssertEqual(result.unloaded, [config.engineID])
            XCTAssertFalse(result.skippedBusy)
            XCTAssertEqual(status.state(for: config.engineID), .notLoaded)
            let unloads = await speech.unloads
            XCTAssertEqual(unloads, 1)
            // The next dictation loads it again through the normal path.
            try await factory.prepare(config)
            XCTAssertEqual(status.state(for: config.engineID), .ready)
            await factory.unloadAll()
        }

        do { // RecentlyUsedModelSurvivesWarningButNotCritical
            let (factory, status, _, clock) = try await loadedFactory()
            clock.advance(30)
            var result = await factory.unloadForMemoryPressure(minimumIdleSeconds: MemoryPressureLevel.warning.minimumIdleSeconds)
            XCTAssertEqual(result.keptRecent, [config.engineID])
            XCTAssertEqual(status.state(for: config.engineID), .ready)
            result = await factory.unloadForMemoryPressure(minimumIdleSeconds: MemoryPressureLevel.critical.minimumIdleSeconds)
            XCTAssertEqual(result.unloaded, [config.engineID], "Critical pressure frees a model idle past its short grace")
            XCTAssertEqual(status.state(for: config.engineID), .notLoaded)
        }

        do { // PinnedModelStaysResident
            let (factory, status, speech, clock) = try await loadedFactory()
            let pin = await factory.pinForSession(config.engineID, recordingSeconds: 600)
            clock.advance(10 * 60)
            let result = await factory.unloadForMemoryPressure(minimumIdleSeconds: 0)
            XCTAssertEqual(result.keptPinned, [config.engineID])
            XCTAssertTrue(result.unloaded.isEmpty)
            XCTAssertEqual(status.state(for: config.engineID), .ready)
            let unloads = await speech.unloads
            XCTAssertEqual(unloads, 0)
            await factory.releaseSessionPin(pin)
            clock.advance(10 * 60)
            let released = await factory.unloadForMemoryPressure(minimumIdleSeconds: 0)
            XCTAssertEqual(released.unloaded, [config.engineID], "Releasing the pin makes the model eligible again")
        }
    }

    func testPressureSkipsInFlightLoadAndActiveInference() async throws {
        do { // InFlightLoadIsNotInterrupted
            let speech = PressureSpeech(id: config.engineID, suspendsLoad: true)
            let status = EngineStatus()
            let clock = TestClock()
            let factory = EngineFactory(status: status, credentialReader: { _ in nil },
                                        transcriberBuilder: { _ in speech }, now: { clock.now })
            let loading = Task { try await factory.prepare(config) }
            defer { loading.cancel() }
            try await waitUntil("Load started") { await speech.isSuspended }
            clock.advance(10 * 60)
            let result = await factory.unloadForMemoryPressure(minimumIdleSeconds: 0)
            XCTAssertTrue(result.skippedBusy, "A pressure pass must not queue behind or touch an active load")
            XCTAssertTrue(result.unloaded.isEmpty)
            await speech.resume()
            try await loading.value
            XCTAssertEqual(status.state(for: config.engineID), .ready)
            let unloads = await speech.unloads
            XCTAssertEqual(unloads, 0)
            // Once the lease is free and the model idle, pressure may free it.
            clock.advance(10 * 60)
            let later = await factory.unloadForMemoryPressure(minimumIdleSeconds: 0)
            XCTAssertEqual(later.unloaded, [config.engineID])
        }

        do { // ActiveInferenceKeepsItsModel
            let speech = PressureSpeech(id: config.engineID, suspendsTranscription: true)
            let status = EngineStatus()
            let clock = TestClock()
            let factory = EngineFactory(status: status, credentialReader: { _ in nil },
                                        transcriberBuilder: { _ in speech }, now: { clock.now })
            let transcription = Task { try await factory.transcribe([0.1], hints: .init(), config: config) }
            defer { transcription.cancel() }
            try await waitUntil("Inference started") { await speech.isSuspended }
            clock.advance(10 * 60)
            let result = await factory.unloadForMemoryPressure(minimumIdleSeconds: 0)
            XCTAssertTrue(result.skippedBusy)
            await speech.resume()
            let transcript = try await transcription.value
            XCTAssertEqual(transcript.text, "Fixture words")
            let unloads = await speech.unloads
            XCTAssertEqual(unloads, 0)
            XCTAssertEqual(status.state(for: config.engineID), .ready)
            await factory.unloadAll()
        }
    }

    func testRepeatedEventsAreDebouncedAndEscalationRuns() async throws {
        let clock = TestClock()
        let source = FakePressureSource()
        var passes: [MemoryPressureLevel] = []
        let gate = PressureGate()
        let responder = MemoryPressureResponder(source: source, debounceSeconds: 60, now: { clock.now }) { level in
            passes.append(level)
            await gate.wait()
            return .completed
        }
        responder.start()
        XCTAssertTrue(source.isStarted)

        responder.receive(.warning)
        responder.receive(.warning)   // during the running pass: same level, dropped
        responder.receive(.critical)  // during the running pass: escalation, coalesced
        responder.receive(.critical)
        try await waitUntil("First pass started") { passes == [.warning] }
        await gate.open()
        try await waitUntil("Escalation ran once") { passes == [.warning, .critical] }
        await responder.currentPass?.value

        clock.advance(30)
        responder.receive(.warning)
        responder.receive(.critical)
        await Task.yield()
        XCTAssertEqual(passes, [.warning, .critical], "Repeated events inside the debounce window are ignored")

        clock.advance(31)
        responder.receive(.warning)
        try await waitUntil("A later event runs again") { passes == [.warning, .critical, .warning] }
        await responder.currentPass?.value

        // Production delivery goes through the injected source as well.
        clock.advance(61)
        source.send(.critical)
        try await waitUntil("Source events reach the responder") { passes.count == 4 }
        await responder.currentPass?.value
        responder.stop()
        XCTAssertTrue(source.isCancelled)
    }

    /// A pass skipped for busy work is not stamped, so it neither debounces the
    /// same level nor is lost: `resumeDeferred()` runs it once work ends.
    func testDeferredPassIsNotDebouncedAndResumesWhenWorkEnds() async throws {
        let clock = TestClock()
        let source = FakePressureSource()
        var passes: [MemoryPressureLevel] = []
        var busy = true
        let responder = MemoryPressureResponder(source: source, debounceSeconds: 60, now: { clock.now }) { level in
            passes.append(level)
            return busy ? .deferred : .completed
        }
        responder.start()
        responder.resumeDeferred()
        XCTAssertTrue(passes.isEmpty, "Nothing waits before the first event")

        responder.receive(.warning)
        try await waitUntil("Busy pass ran") { passes == [.warning] }
        await responder.currentPass?.value
        XCTAssertEqual(responder.deferredLevel, .warning)
        // Work is still busy: the resumed pass is deferred again.
        responder.resumeDeferred()
        try await waitUntil("Resumed pass ran") { passes.count == 2 }
        await responder.currentPass?.value
        XCTAssertEqual(responder.deferredLevel, .warning)

        // The same level inside the debounce window still runs: nothing was handled.
        busy = false
        responder.receive(.warning)
        try await waitUntil("Undebounced pass ran") { passes.count == 3 }
        await responder.currentPass?.value
        XCTAssertNil(responder.deferredLevel, "A completed pass covers the deferred level")
        responder.receive(.warning)
        await Task.yield()
        XCTAssertEqual(passes.count, 3, "A completed pass debounces as before")
        responder.resumeDeferred()
        await Task.yield()
        XCTAssertEqual(passes.count, 3, "Nothing is waiting")

        // A deferred escalation keeps its level and runs once when work ends.
        busy = true
        clock.advance(61)
        responder.receive(.warning)
        try await waitUntil("Warning deferred") { passes.count == 4 }
        await responder.currentPass?.value
        responder.receive(.critical)
        try await waitUntil("Critical deferred") { passes.count == 5 }
        await responder.currentPass?.value
        XCTAssertEqual(responder.deferredLevel, .critical, "The highest deferred level waits")
        busy = false
        responder.resumeDeferred()
        try await waitUntil("Deferred critical resumed") { passes.count == 6 }
        await responder.currentPass?.value
        XCTAssertEqual(passes.last, .critical)
        XCTAssertNil(responder.deferredLevel)
        responder.resumeDeferred()
        await Task.yield()
        XCTAssertEqual(passes.count, 6, "A resumed pass runs once")

        // Stopping forgets a deferred pass.
        busy = true
        clock.advance(61)
        responder.receive(.critical)
        try await waitUntil("Deferred before stop") { passes.count == 7 }
        await responder.currentPass?.value
        responder.stop()
        XCTAssertNil(responder.deferredLevel)
        responder.resumeDeferred()
        await Task.yield()
        XCTAssertEqual(passes.count, 7)
    }

    // MARK: Helpers

    private func loadedFactory() async throws -> (EngineFactory, EngineStatus, PressureSpeech, TestClock) {
        let speech = PressureSpeech(id: config.engineID)
        let status = EngineStatus()
        let clock = TestClock()
        let factory = EngineFactory(status: status, credentialReader: { _ in nil },
                                    transcriberBuilder: { _ in speech }, now: { clock.now })
        try await factory.prepare(config)
        XCTAssertEqual(status.state(for: config.engineID), .ready)
        return (factory, status, speech, clock)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 3,
                           condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(description + " timed out")
        throw CancellationError()
    }
}

private actor PressureSpeech: Transcriber {
    nonisolated let id: String
    private let suspendsLoad: Bool
    private let suspendsTranscription: Bool
    private var ready = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var unloads = 0
    var isSuspended: Bool { continuation != nil }

    init(id: String, suspendsLoad: Bool = false, suspendsTranscription: Bool = false) {
        self.id = id
        self.suspendsLoad = suspendsLoad
        self.suspendsTranscription = suspendsTranscription
    }

    func isReady() -> Bool { ready }
    func prepare() async throws {
        if suspendsLoad { await withCheckedContinuation { continuation = $0 } }
        ready = true
    }
    func resume() { continuation?.resume(); continuation = nil }
    func unload() { ready = false; unloads += 1 }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        if suspendsTranscription { await withCheckedContinuation { continuation = $0 } }
        guard ready else { throw TranscriberError.modelNotDownloaded }
        return Transcript(text: "Fixture words", engine: id, latencyMs: 0)
    }
}

private final class FakePressureSource: MemoryPressureSource {
    private let handler = Locked<(@Sendable (MemoryPressureLevel) -> Void)?>(nil)
    private let cancelled = Locked(false)
    var isStarted: Bool { handler.value != nil }
    var isCancelled: Bool { cancelled.value }
    func start(_ handler: @escaping @Sendable (MemoryPressureLevel) -> Void) { self.handler.withLock { $0 = handler } }
    func cancel() { cancelled.withLock { $0 = true } }
    func send(_ level: MemoryPressureLevel) { handler.value?(level) }
}

private actor PressureGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
