import XCTest
import os
@testable import AirdraftCore

@MainActor
final class EngineFactoryLeaseTests: XCTestCase {
    func testUncachedTranscriptionUsesThePreparedInstanceOnce() async throws {
        let config = ASRConfig(kind: .openAICompatible, model: "fixture")
        let builds = OSAllocatedUnfairLock(initialState: 0)
        let preparing = OSAllocatedUnfairLock(initialState: 0)
        let factory = factory(status: EngineStatus()) { config in
            builds.withLock { $0 += 1 }
            return TimedSpeech(id: config.engineID)
        }
        let result = try await factory.transcribe([0.1], hints: .init(), config: config) {
            preparing.withLock { $0 += 1 }
        }
        XCTAssertEqual(result.text, "Complete words")
        XCTAssertEqual(builds.withLock { $0 }, 1, "Prepare and decode must use one request-scoped engine")
        XCTAssertEqual(preparing.withLock { $0 }, 1)
        XCTAssertGreaterThanOrEqual(result.latencyMs, 75, "ASR time must include model preparation")
        _ = try await factory.transcribe([0.1], hints: .init(), config: config)
        XCTAssertEqual(builds.withLock { $0 }, 2, "Remote engines must still resolve fresh settings per call")
        await factory.unloadAll()
    }

    func testWarmTranscriptionSkipsPreparation() async throws {
        let config = ASRConfig(kind: .parakeet)
        let engine = TimedSpeech(id: config.engineID)
        let factory = factory(status: EngineStatus()) { _ in engine }
        try await factory.prepare(config)
        let warm = try await factory.transcribe([0.1], hints: .init(), config: config) {
            XCTFail("A warm model must not show Loading")
        }
        XCTAssertEqual(warm.text, "Complete words")
        let preparations = await engine.preparations
        XCTAssertEqual(preparations, 1)
        await factory.unloadAll()
    }

    func testCancelledLoadDoesNotBlockAnotherModelOrPublishLateReadiness() async throws {
        let firstConfig = ASRConfig(kind: .parakeet)
        let secondConfig = ASRConfig(kind: .qwen3, qwen3Model: "fixture/replacement")
        let first = SuspendedLoadSpeech(id: firstConfig.engineID)
        let second = LeaseSpeech(id: secondConfig.engineID)
        let status = EngineStatus()
        let factory = factory(status: status) { config in
            if config.kind == .parakeet { return first }
            return second
        }
        var loadFinished = false
        let loading = Task {
            defer { loadFinished = true }
            try await factory.prepare(firstConfig)
        }
        defer { loading.cancel(); Task { await first.release() } }
        try await waitUntil("First load started") { await first.isLoading }
        loading.cancel()
        let switching = Task { try await factory.prepare(secondConfig) }
        defer { switching.cancel() }
        try await waitUntil("Cancelled load releases selection without waiting for the SDK") {
            loadFinished && status.state(for: secondConfig.engineID) == .ready
        }
        try await switching.value
        guard case .failure(let error) = await loading.result, error is CancellationError else {
            return XCTFail("Cancelled preparation must report cancellation")
        }
        XCTAssertEqual(status.state(for: firstConfig.engineID), .notLoaded)
        XCTAssertTrue(status.hasPendingLoad(for: firstConfig.engineID), "Files stay protected until native work ends")
        let unloadedWhileLoading = await first.unloadedWhileLoading
        XCTAssertFalse(unloadedWhileLoading, "Do not unload a model while its SDK is still loading")

        await first.release()
        try await waitUntil("Abandoned model is unloaded after its SDK returns") {
            await first.unloaded && !status.hasPendingLoad(for: firstConfig.engineID)
        }
        XCTAssertEqual(status.state(for: firstConfig.engineID), .notLoaded)
        XCTAssertEqual(status.state(for: secondConfig.engineID), .ready)
        await factory.unloadAll()
    }

    func testLoadTimeoutAllowsSwitchingButPreventsDuplicateNativeLoads() async throws {
        let config = ASRConfig(kind: .parakeet)
        let otherConfig = ASRConfig(kind: .qwen3, qwen3Model: "fixture/replacement")
        let stalled = SuspendedLoadSpeech(id: config.engineID)
        let retry = LeaseSpeech(id: config.engineID)
        let other = LeaseSpeech(id: otherConfig.engineID)
        let builds = OSAllocatedUnfairLock(initialState: 0)
        let status = EngineStatus()
        let factory = factory(status: status, timeout: 0.1) { config in
            if config.kind != .parakeet { return other }
            let count = builds.withLock { count in count += 1; return count }
            if count == 1 { return stalled }
            return retry
        }
        defer { Task { await stalled.release() } }
        do {
            try await factory.prepare(config)
            XCTFail("A stalled load must time out")
        } catch TranscriberError.modelLoadTimedOut {}
        XCTAssertEqual(status.state(for: config.engineID), .failed(TranscriberError.modelLoadTimedOut.localizedDescription))
        XCTAssertTrue(status.hasPendingLoad(for: config.engineID))
        do {
            try await factory.prepare(config)
            XCTFail("Do not start a second copy of the same native load")
        } catch TranscriberError.modelLoadStillStopping {}
        XCTAssertEqual(builds.withLock { $0 }, 1)
        try await factory.prepare(otherConfig)
        XCTAssertEqual(status.state(for: otherConfig.engineID), .ready)

        await stalled.release()
        try await waitUntil("Native cleanup finishes") { !status.hasPendingLoad(for: config.engineID) }
        XCTAssertEqual(status.state(for: otherConfig.engineID), .ready)
        try await factory.prepare(config)
        XCTAssertEqual(builds.withLock { $0 }, 2, "Retry must use a fresh engine")
        XCTAssertEqual(status.state(for: config.engineID), .ready)
        XCTAssertEqual(status.state(for: otherConfig.engineID), .notLoaded)
        await factory.unloadAll()
    }

    func testUnloadAllWaitsForRetiredLoadWithoutBlockingAnotherSelection() async throws {
        let config = ASRConfig(kind: .parakeet)
        let otherConfig = ASRConfig(kind: .qwen3, qwen3Model: "fixture/replacement")
        let stalled = SuspendedLoadSpeech(id: config.engineID)
        let other = LeaseSpeech(id: otherConfig.engineID)
        let status = EngineStatus()
        let factory = factory(status: status, timeout: 0.1) { config in
            if config.kind == .parakeet { return stalled }
            return other
        }
        defer { Task { await stalled.release() } }
        do { try await factory.prepare(config); XCTFail("Expected load timeout") }
        catch TranscriberError.modelLoadTimedOut {}
        var cleanupFinished = false
        let cleanup = Task { await factory.unloadAll(); cleanupFinished = true }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(cleanupFinished, "Reset must not delete files still used by a retired loader")
        try await factory.prepare(otherConfig)
        XCTAssertEqual(status.state(for: otherConfig.engineID), .ready)
        XCTAssertFalse(cleanupFinished)
        await stalled.release()
        await cleanup.value
        let unloadedWhileLoading = await stalled.unloadedWhileLoading
        XCTAssertFalse(unloadedWhileLoading)
        XCTAssertFalse(status.hasPendingLoad(for: config.engineID))
        XCTAssertEqual(status.state(for: otherConfig.engineID), .ready)
        await factory.unloadAll()
    }

    func testUnloadWaitsForActiveTranscription() async throws {
        let config = ASRConfig(kind: .parakeet)
        let speech = LeaseSpeech(id: config.engineID)
        let status = EngineStatus()
        let factory = factory(status: status) { _ in speech }
        let transcription = Task { try await factory.transcribe([0.1], hints: .init(), config: config) }
        defer { transcription.cancel(); Task { await speech.release() } }
        try await waitUntil("Transcription started") { await speech.isTranscribing }
        var unloaded = false
        let cleanup = Task { await factory.unloadAll(); unloaded = true }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(unloaded)
        let beforeRelease = await speech.snapshot()
        XCTAssertEqual(beforeRelease, [.prepare, .transcribeStarted])

        await speech.release()
        _ = try await transcription.value
        await cleanup.value
        let afterRelease = await speech.snapshot()
        XCTAssertEqual(afterRelease, [.prepare, .transcribeStarted, .transcribeFinished, .unload])
        XCTAssertEqual(status.state(for: config.engineID), .notLoaded)
    }

    func testModelSwitchWaitsForActiveTranscription() async throws {
        let firstConfig = ASRConfig(kind: .parakeet)
        let secondConfig = ASRConfig(kind: .qwen3, qwen3Model: "fixture/replacement")
        let first = LeaseSpeech(id: firstConfig.engineID)
        let second = LeaseSpeech(id: secondConfig.engineID)
        let status = EngineStatus()
        let factory = factory(status: status) { $0.kind == .parakeet ? first : second }
        let transcription = Task { try await factory.transcribe([0.1], hints: .init(), config: firstConfig) }
        defer { transcription.cancel(); Task { await first.release() } }
        try await waitUntil("Transcription started") { await first.isTranscribing }
        let switching = Task { try await factory.prepare(secondConfig) }
        try await Task.sleep(for: .milliseconds(50))
        let secondBeforeRelease = await second.snapshot()
        let firstBeforeRelease = await first.snapshot()
        XCTAssertTrue(secondBeforeRelease.isEmpty)
        XCTAssertEqual(firstBeforeRelease, [.prepare, .transcribeStarted])

        await first.release()
        _ = try await transcription.value
        try await switching.value
        let firstAfterRelease = await first.snapshot()
        let secondAfterRelease = await second.snapshot()
        XCTAssertEqual(firstAfterRelease, [.prepare, .transcribeStarted, .transcribeFinished, .unload])
        XCTAssertEqual(secondAfterRelease, [.prepare])
        XCTAssertEqual(status.state(for: firstConfig.engineID), .notLoaded)
        XCTAssertEqual(status.state(for: secondConfig.engineID), .ready)
        await factory.unloadAll()
    }

    /// Uses the real one-minute setting and 30-second timer; normally takes 60 seconds.
    func testIdleTimerUnloadsExpiredEngineButCannotInterruptActiveInference() async throws {
        let config = ASRConfig(kind: .parakeet)
        let idleSpeech = LeaseSpeech(id: config.engineID, ready: true)
        let idleStatus = EngineStatus()
        // Establish real use before the factory starts its polling clock so the
        // second tick is unambiguously older than one minute, without fake time.
        idleStatus.set(config.engineID, .ready)
        try await Task.sleep(for: .milliseconds(100))
        let idleFactory = factory(status: idleStatus) { _ in idleSpeech }
        _ = await idleFactory.transcriber(for: config)
        await idleFactory.setIdleUnloadMinutes(1)

        let busySpeech = LeaseSpeech(id: config.engineID)
        let busyStatus = EngineStatus()
        let busyFactory = factory(status: busyStatus) { _ in busySpeech }
        await busyFactory.setIdleUnloadMinutes(1)
        let transcription = Task { try await busyFactory.transcribe([0.1], hints: .init(), config: config) }
        defer {
            transcription.cancel()
            Task {
                await busySpeech.release()
                await idleFactory.setIdleUnloadMinutes(0)
                await busyFactory.setIdleUnloadMinutes(0)
            }
        }
        try await waitUntil("Busy transcription started") { await busySpeech.isTranscribing }
        try await waitUntil("Idle engine unloads after one minute", timeout: 90) {
            let events = await idleSpeech.snapshot()
            return events.contains(.unload) && idleStatus.state(for: config.engineID) == .notLoaded
        }
        XCTAssertEqual(idleStatus.state(for: config.engineID), .notLoaded)
        let beforeRelease = await busySpeech.snapshot()
        XCTAssertEqual(beforeRelease, [.prepare, .transcribeStarted])
        XCTAssertEqual(busyStatus.state(for: config.engineID), .ready)

        await busySpeech.release()
        _ = try await transcription.value
        // Queue behind the pending idle check. It must see the use timestamp
        // refreshed by completed inference and leave this engine resident.
        try await busyFactory.prepare(config)
        let afterRelease = await busySpeech.snapshot()
        XCTAssertEqual(afterRelease, [.prepare, .transcribeStarted, .transcribeFinished])
        XCTAssertEqual(busyStatus.state(for: config.engineID), .ready)
        await busyFactory.setIdleUnloadMinutes(0)
        await busyFactory.unloadAll()
    }

    /// Recordings longer than the idle setting must keep their speech model.
    func testSessionPinKeepsRecordingEngineResidentPastIdleTimeout() async throws {
        let config = ASRConfig(kind: .parakeet)
        let speech = LeaseSpeech(id: config.engineID)
        let status = EngineStatus()
        let clock = TestClock()
        let factory = EngineFactory(status: status, credentialReader: { _ in nil },
                                    transcriberBuilder: { _ in speech }, now: { clock.now })
        try await factory.prepare(config)
        await factory.setIdleUnloadMinutes(5)
        defer { Task { await factory.setIdleUnloadMinutes(0) } }

        let pin = await factory.pinForSession(config.engineID, recordingSeconds: 600)
        clock.advance(9 * 60)
        await factory.unloadIdle()
        var events = await speech.snapshot()
        XCTAssertFalse(events.contains(.unload), "A pinned engine survives the idle timeout")
        XCTAssertEqual(status.state(for: config.engineID), .ready)

        // The idle countdown restarts when the session ends.
        await factory.releaseSessionPin(pin)
        clock.advance(4 * 60)
        await factory.unloadIdle()
        events = await speech.snapshot()
        XCTAssertFalse(events.contains(.unload), "Release refreshes the use timestamp")
        clock.advance(2 * 60)
        await factory.unloadIdle()
        events = await speech.snapshot()
        XCTAssertEqual(events.filter { $0 == .unload }.count, 1)
        XCTAssertEqual(status.state(for: config.engineID), .notLoaded)
    }

    func testLeakedSessionPinExpiresAfterLoadRecordingAndProcessingBounds() async throws {
        let config = ASRConfig(kind: .parakeet)
        let speech = LeaseSpeech(id: config.engineID)
        let status = EngineStatus()
        let clock = TestClock()
        let factory = EngineFactory(status: status, modelLoadTimeout: 120, credentialReader: { _ in nil },
                                    transcriberBuilder: { _ in speech }, now: { clock.now })
        try await factory.prepare(config)
        await factory.setIdleUnloadMinutes(5)
        defer { Task { await factory.setIdleUnloadMinutes(0) } }

        _ = await factory.pinForSession(config.engineID, recordingSeconds: 600)
        clock.advance(120 + 600 + EngineFactory.sessionPinProcessingSeconds - 1)
        await factory.unloadIdle()
        XCTAssertEqual(status.state(for: config.engineID), .ready)
        clock.advance(2)
        await factory.unloadIdle()
        XCTAssertEqual(status.state(for: config.engineID), .notLoaded, "A pin never holds a model indefinitely")
        // Explicit unloads (model switch, reset, quit) are never blocked by pins.
        let second = await factory.pinForSession(config.engineID, recordingSeconds: 600)
        try await factory.prepare(config)
        await factory.unloadAll()
        XCTAssertEqual(status.state(for: config.engineID), .notLoaded)
        await factory.releaseSessionPin(second)
    }

    private func factory(status: EngineStatus, timeout: TimeInterval = 120,
                         builder: @escaping @Sendable (ASRConfig) -> any Transcriber) -> EngineFactory {
        EngineFactory(status: status, modelLoadTimeout: timeout, credentialReader: { _ in
            XCTFail("Local lifecycle tests must not read credentials")
            return nil
        }, transcriberBuilder: builder)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 3,
                           condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail(description + " timed out")
        throw LeaseFailure.timedOut
    }
}

private enum LeaseFailure: Error { case timedOut }

private actor TimedSpeech: Transcriber {
    nonisolated let id: String
    private var ready = false
    private(set) var preparations = 0
    init(id: String) { self.id = id }
    func isReady() -> Bool { ready }
    func prepare() async throws {
        preparations += 1
        try await Task.sleep(for: .milliseconds(80))
        ready = true
    }
    func unload() { ready = false }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard ready else { throw TranscriberError.modelNotDownloaded }
        return .init(text: "Complete words", engine: id, latencyMs: 1)
    }
}

/// Deliberately ignores cancellation, like a synchronous native model compiler.
private actor SuspendedLoadSpeech: Transcriber {
    nonisolated let id: String
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready = false
    var isLoading: Bool { continuation != nil }
    private(set) var unloaded = false
    private(set) var unloadedWhileLoading = false
    init(id: String) { self.id = id }
    func isReady() -> Bool { ready }
    func prepare() async throws {
        await withCheckedContinuation { continuation = $0 }
        ready = true
    }
    func release() { continuation?.resume(); continuation = nil }
    func unload() {
        unloadedWhileLoading = isLoading
        ready = false
        unloaded = true
    }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        XCTFail("The abandoned model must never transcribe")
        throw LeaseFailure.timedOut
    }
}

private actor LeaseSpeech: Transcriber {
    enum Event: Equatable { case prepare, transcribeStarted, transcribeFinished, unload }
    nonisolated let id: String
    private var ready: Bool
    private var events: [Event] = []
    private var continuation: CheckedContinuation<Void, Never>?
    var isTranscribing: Bool { continuation != nil }

    init(id: String, ready: Bool = false) { self.id = id; self.ready = ready }
    func snapshot() -> [Event] { events }
    func isReady() -> Bool { ready }
    func prepare() async throws { ready = true; events.append(.prepare) }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        events.append(.transcribeStarted)
        await withCheckedContinuation { continuation = $0 }
        events.append(.transcribeFinished)
        return Transcript(text: "Local fixture", engine: id, latencyMs: 0)
    }
    func release() { continuation?.resume(); continuation = nil }
    func unload() async { ready = false; events.append(.unload) }
}
