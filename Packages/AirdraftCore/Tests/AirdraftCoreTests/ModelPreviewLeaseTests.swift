import XCTest
@testable import AirdraftCore

/// AD-084: display-only preview decodes share the factory lease, never load a
/// model, drop when the engine is busy, and yield to final inference.
@MainActor
final class ModelPreviewLeaseTests: XCTestCase {
    private let config = ASRConfig(kind: .parakeet)
    private let hints = TranscriptionHints(language: nil, vocabulary: ["Airdraft"])

    /// Preview never loads an unloaded engine, decodes with a loaded one using the same
    /// hints, and never decodes unsupported or cloud configs.
    func testPreviewDecodesOnlyWithLoadedSupportedEngineAndSameHints() async throws {
        do { // PreviewNeverLoadsAnUnloadedEngine
            let engine = LeaseTestSpeech(ready: false)
            let factory = makeFactory(engine)
            let text = try await factory.transcribePreview([0.1, 0.2], hints: hints, config: config)
            XCTAssertNil(text, "An engine that is not loaded yet drops the preview")
            let prepares = await engine.prepareCount
            XCTAssertEqual(prepares, 0)
            let calls = await engine.calls
            XCTAssertTrue(calls.isEmpty)
        }

        do { // PreviewDecodesWithLoadedEngineAndSameHints
            let engine = LeaseTestSpeech(ready: true)
            let factory = makeFactory(engine)
            _ = await factory.transcriber(for: config)
            let text = try await factory.transcribePreview([Float](repeating: 0.1, count: 800), hints: hints, config: config)
            XCTAssertEqual(text, "heard 800")
            let calls = await engine.calls
            XCTAssertEqual(calls.map(\.count), [800])
            XCTAssertEqual(calls.first?.vocabulary, ["Airdraft"])
            let prepares = await engine.prepareCount
            XCTAssertEqual(prepares, 0)
        }

        do { // UnsupportedOrCloudConfigNeverDecodes
            let engine = LeaseTestSpeech(ready: true)
            let factory = makeFactory(engine)
            for kind in [ASRProviderKind.whisperKit, .qwen3, .openAI] {
                let other = ASRConfig(kind: kind)
                _ = await factory.transcriber(for: other)
                let text = try await factory.transcribePreview([0.1], hints: hints, config: other)
                XCTAssertNil(text, kind.rawValue)
            }
            let calls = await engine.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }

    /// Preview drops while final inference holds the lease, and final inference preempts a
    /// queued or running preview.
    func testPreviewYieldsToFinalInferenceInEitherOrder() async throws {
        do { // PreviewDropsWhileFinalInferenceHoldsTheLease
            let engine = LeaseTestSpeech(ready: true)
            let factory = makeFactory(engine)
            _ = await factory.transcriber(for: config)
            await engine.holdNextDecode()
            let full = [Float](repeating: 0.2, count: 32_000)
            let final = Task { try await factory.transcribe(full, hints: self.hints, config: self.config) }
            try await waitUntil { await engine.isHolding }
            let preview = try await factory.transcribePreview([0.1, 0.1], hints: hints, config: config)
            XCTAssertNil(preview, "Preview never queues behind final inference")
            await engine.releaseHeld()
            let result = try await final.value
            XCTAssertEqual(result.text, "heard 32000")
            let calls = await engine.calls
            XCTAssertEqual(calls.map(\.count), [32_000], "Only the final decode ran")
        }

        do { // FinalInferencePreemptsQueuedOrRunningPreview
            let engine = LeaseTestSpeech(ready: true)
            let factory = makeFactory(engine)
            _ = await factory.transcriber(for: config)
            // The preview decode sleeps cooperatively, so preemption cancels it.
            await engine.setPreviewDelay(.seconds(5))
            let preview = Task { try await factory.transcribePreview([Float](repeating: 0.1, count: 1_600), hints: self.hints, config: self.config) }
            try await waitUntil { await engine.calls.count == 1 }
            await engine.setPreviewDelay(nil)
            let started = ContinuousClock.now
            let full = [Float](repeating: 0.3, count: 48_000)
            let result = try await factory.transcribe(full, hints: hints, config: config)
            let waited = started.duration(to: .now)
            XCTAssertEqual(result.text, "heard 48000")
            XCTAssertLessThan(waited, .seconds(2), "Final inference does not wait out the preview decode")
            do {
                _ = try await preview.value
                XCTFail("A preempted preview must not return text")
            } catch is CancellationError {}
            let calls = await engine.calls
            XCTAssertEqual(calls.last?.count, 48_000, "Final inference always receives the full capture")
        }
    }

    func testFinalResultIsIdenticalWithAndWithoutPreviewTraffic() async throws {
        let full = (0..<64_000).map { Float(sin(Double($0) * 0.01)) * 0.3 }
        let quiet = LeaseTestSpeech(ready: true)
        let quietFactory = makeFactory(quiet)
        _ = await quietFactory.transcriber(for: config)
        let baseline = try await quietFactory.transcribe(full, hints: hints, config: config)

        let busy = LeaseTestSpeech(ready: true)
        let busyFactory = makeFactory(busy)
        _ = await busyFactory.transcriber(for: config)
        let session = ModelSpeechPreview.start(policy: ModelPreviewPolicy(minimumInterval: 0, minimumNewAudioSeconds: 0.05, pollSeconds: 0.001),
            decode: ModelSpeechPreview.decoder(factory: busyFactory, request: ModelPreviewRequest(asr: config, hints: hints)),
            onText: { _ in }, onIssue: { XCTFail("Unexpected preview issue: \($0)") })
        // Preview never sees the last chunk, so the only full-length decode is final inference.
        for offset in stride(from: 0, to: full.count - 3_200, by: 1_600) {
            session.append(Array(full[offset..<(offset + 1_600)]))
            try await Task.sleep(for: .milliseconds(2))
        }
        try await waitUntil { session.metrics.decodes >= 2 }
        let withPreview = try await busyFactory.transcribe(full, hints: hints, config: config)
        session.cancel()
        XCTAssertEqual(withPreview.text, baseline.text)
        XCTAssertEqual(withPreview.language, baseline.language)
        XCTAssertEqual(withPreview.adjustments, baseline.adjustments)
        let finalCalls = await busy.calls.filter { $0.count == full.count }
        XCTAssertEqual(finalCalls.count, 1)
        XCTAssertEqual(finalCalls.first?.checksum, full.reduce(0, +))
    }

    // MARK: - Helpers

    private func makeFactory(_ engine: LeaseTestSpeech) -> EngineFactory {
        EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("Preview lease tests must not read credentials")
            return nil
        }, transcriberBuilder: { _ in engine })
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out", file: file, line: line)
    }
}

private actor LeaseTestSpeech: Transcriber {
    struct Call: Sendable { let count: Int; let vocabulary: [String]; let checksum: Float }
    nonisolated let id = "lease-test-speech"
    private var ready: Bool
    private(set) var prepareCount = 0
    private(set) var calls: [Call] = []
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var previewDelay: Duration?

    init(ready: Bool) { self.ready = ready }

    var isHolding: Bool { held != nil }
    func holdNextDecode() { holdNext = true }
    func releaseHeld() { held?.resume(); held = nil }
    func setPreviewDelay(_ delay: Duration?) { previewDelay = delay }

    func isReady() async -> Bool { ready }
    func prepare() async throws { prepareCount += 1; ready = true }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        calls.append(Call(count: samples.count, vocabulary: hints.vocabulary, checksum: samples.reduce(0, +)))
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        if let previewDelay { try await Task.sleep(for: previewDelay) }
        return Transcript(text: "heard \(samples.count)", engine: id, latencyMs: 1)
    }
}
