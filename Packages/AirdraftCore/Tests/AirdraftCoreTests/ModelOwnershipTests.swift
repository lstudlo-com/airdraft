import XCTest
@testable import AirdraftCore

@MainActor
final class ModelOwnershipTests: XCTestCase {
    func testSwitchWaitsForInferenceBeforeUnloadingEngine() async throws {
        let a = LeasedSpeech(id: "qwen3-asr:a")
        let b = LeasedSpeech(id: "qwen3-asr:b")
        let factory = EngineFactory(status: EngineStatus(), transcriberBuilder: { $0.qwen3Model == "a" ? a : b })
        let first = ASRConfig(kind: .qwen3, qwen3Model: "a")
        let second = ASRConfig(kind: .qwen3, qwen3Model: "b")
        let inference = Task { try await factory.transcribe([0.2], hints: .init(), config: first) }
        for _ in 0..<200 {
            if await a.isTranscribing { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let started = await a.isTranscribing
        XCTAssertTrue(started)
        let switching = Task { try await factory.prepare(second) }
        try await Task.sleep(for: .milliseconds(30))
        let unloadsDuring = await a.unloads
        let secondReady = await b.isReady()
        XCTAssertEqual(unloadsDuring, 0)
        XCTAssertFalse(secondReady)
        await a.finish()
        _ = try await inference.value
        try await switching.value
        let unloadsAfter = await a.unloads
        XCTAssertEqual(unloadsAfter, 1)
        let nowReady = await b.isReady()
        XCTAssertTrue(nowReady)
    }

    func testCancelledDownloadCannotReportCompletionOrStartDuplicate() async throws {
        let operation = DownloadGate()
        var completions = 0
        let store = ModelDownloadStore(download: { _, progress in
            await operation.run(progress)
        }, installed: { _ in true })
        let config = ASRConfig(kind: .qwen3)
        store.start(config) { completions += 1 }
        for _ in 0..<200 {
            if await operation.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        store.start(config) { completions += 1 }
        XCTAssertNotNil(store.jobs[config.engineID]?.progress)
        store.cancel(config)
        await operation.finish()
        for _ in 0..<200 {
            if !store.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(completions, 0)
        XCTAssertNil(store.jobs[config.engineID]?.progress)
        XCTAssertTrue(store.jobs[config.engineID]?.error?.contains("cancelled") == true)
        let calls = await operation.calls
        XCTAssertEqual(calls, 1)
    }

    func testIncompleteDownloadDoesNotSelectModel() async throws {
        let store = ModelDownloadStore(download: { _, _ in }, installed: { _ in false })
        var completed = false
        let config = ASRConfig(kind: .whisperKit)
        store.start(config) { completed = true }
        for _ in 0..<200 {
            if !store.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(completed)
        XCTAssertTrue(store.jobs[config.engineID]?.error?.contains("incomplete") == true)
    }

    func testTokenizerRequiresEveryFileNotOnlyFirstFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("{}".utf8).write(to: dir.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(LocalModels.hasWhisperTokenizer(at: dir))
        for file in LocalModels.whisperTokenizerFiles {
            try Data("{}".utf8).write(to: dir.appendingPathComponent(file))
        }
        XCTAssertTrue(LocalModels.hasWhisperTokenizer(at: dir))
    }

    func testAppleLanguageAndLocaleUseSameEngineIdentity() async {
        var config = ASRConfig(kind: .apple)
        config.appleLocale = "zh-TW"
        config.language = "en"
        let factory = EngineFactory(status: EngineStatus())
        let engine = await factory.transcriber(for: config)
        XCTAssertEqual(config.engineID, "apple-speech:en-US")
        XCTAssertEqual(engine.id, config.engineID)
    }
}

private actor LeasedSpeech: Transcriber {
    nonisolated let id: String
    var isTranscribing = false
    var unloads = 0
    private var ready = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(id: String) { self.id = id }
    func prepare() async throws { ready = true }
    func isReady() async -> Bool { ready }
    func unload() async { ready = false; unloads += 1 }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        isTranscribing = true
        await withCheckedContinuation { continuation = $0 }
        isTranscribing = false
        return Transcript(text: "complete", language: nil, engine: id, latencyMs: 1)
    }
    func finish() { continuation?.resume(); continuation = nil }
}

private actor DownloadGate {
    var calls = 0
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    func run(_ progress: ModelDownloader.ProgressHandler) async {
        calls += 1
        started = true
        progress(.init(fraction: 0.5, currentFile: "weights"))
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
