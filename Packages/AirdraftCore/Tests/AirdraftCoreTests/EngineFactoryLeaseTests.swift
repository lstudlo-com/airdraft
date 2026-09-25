import XCTest
@testable import AirdraftCore

@MainActor
final class EngineFactoryLeaseTests: XCTestCase {
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

    private func factory(status: EngineStatus,
                         builder: @escaping @Sendable (ASRConfig) -> any Transcriber) -> EngineFactory {
        EngineFactory(status: status, credentialReader: { _ in
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
