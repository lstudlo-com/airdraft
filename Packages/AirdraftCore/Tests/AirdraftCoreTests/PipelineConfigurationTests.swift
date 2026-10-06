import AppKit
import ApplicationServices
import Foundation
import XCTest
@testable import AirdraftCore

/// All engines, capture and delivery are injected. These tests never use a
/// microphone, general clipboard, executable, network session or credential value.
@MainActor
final class PipelineConfigurationTests: XCTestCase {
    func testRecordingUsesPreflightedRefinerForPrewarmAndProcessingThenNextSelection() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.close() }
        let original = fixture.settings.llm
        try await fixture.pipeline.startFromAutomation()
        try await wait { !fixture.probe.built.isEmpty }
        XCTAssertEqual(fixture.preflightLLM, original)
        fixture.settings.llm = fixture.nextLLM
        fixture.pipeline.stopAndProcess()
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(try fixture.history.recent().first?.llmEngine, original.model)
        XCTAssertTrue(fixture.probe.built.allSatisfy { $0 == original })

        fixture.probe.clear()
        try await fixture.pipeline.startFromAutomation()
        fixture.pipeline.stopAndProcess()
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(fixture.preflightLLM, fixture.nextLLM)
        XCTAssertEqual(try fixture.history.recent().first?.llmEngine, fixture.nextLLM.model)
        XCTAssertTrue(fixture.probe.built.allSatisfy { $0 == fixture.nextLLM })
    }

    func testSampleProcessingCapturesRefinerBeforeItsFirstAwait() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.close() }
        let original = fixture.settings.llm
        fixture.pipeline.processSamples(ConfigurationFixture.samples)
        fixture.settings.llm = fixture.nextLLM
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(try fixture.history.recent().first?.llmEngine, original.model)
        XCTAssertTrue(fixture.probe.built.allSatisfy { $0 == original })
    }

    func testRetranscriptionCapturesRefinerAndDoesNotDeliverOrAddHistory() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.close() }
        let original = fixture.settings.llm
        let saved = try fixture.history.save(fixture.record, samples: ConfigurationFixture.samples)
        fixture.pipeline.retranscribe(saved)
        fixture.settings.llm = fixture.nextLLM
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertNotNil(fixture.pipeline.reviewOutcome)
        XCTAssertEqual(fixture.probe.built, [original])
        XCTAssertTrue(fixture.deliveries.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testRetryCapturesCurrentRefinerAndRetainsOriginalOutputPolicy() async throws {
        let fixture = try ConfigurationFixture(failSpeechOnce: true)
        defer { fixture.close() }
        fixture.pipeline.insertionEnabled = true
        fixture.settings.outputDestination = .script
        fixture.settings.outputScriptPath = fixture.script.path
        try await fixture.pipeline.startFromAutomation()
        fixture.pipeline.stopAndProcess()
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)
        fixture.settings.llm = fixture.nextLLM
        fixture.settings.outputDestination = .cursor
        fixture.pipeline.retryRecording()
        fixture.settings.llm = LLMConfig(kind: .none)
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(try fixture.history.recent().first?.llmEngine, fixture.nextLLM.model)
        XCTAssertEqual(fixture.deliveries, [fixture.script.path])
        XCTAssertEqual(try fixture.history.recent().first?.outputDestination, "script")
    }

    func testCancellationBeforeProcessingCannotDeliverLateSnapshot() async throws {
        let fixture = try ConfigurationFixture()
        defer { fixture.close() }
        fixture.pipeline.processSamples(ConfigurationFixture.samples)
        fixture.pipeline.cancel()
        fixture.settings.llm = fixture.nextLLM
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(try fixture.history.count(), 0)
        XCTAssertNil(fixture.pipeline.lastOutcome)
        fixture.pipeline.processSamples(ConfigurationFixture.samples)
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(try fixture.history.recent().first?.llmEngine, fixture.nextLLM.model)
    }

    func testRetryKeepsOriginalCapturedCursorTargetAndInsertionMethod() async throws {
        let target = ConfigurationTarget()
        defer { target.close() }
        let fixture = try ConfigurationFixture(failSpeechOnce: true, target: target)
        defer { fixture.close() }
        fixture.pipeline.insertionEnabled = true
        fixture.settings.insertionMethod = .paste
        try await fixture.pipeline.startFromAutomation()
        fixture.pipeline.stopAndProcess()
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)
        target.currentPID = 202
        fixture.settings.insertionMethod = .auto
        fixture.settings.llm = fixture.nextLLM
        fixture.pipeline.retryRecording()
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(target.deliveries.count, 1)
        XCTAssertEqual(target.deliveries.first?.0, .paste)
        XCTAssertEqual(target.deliveries.first?.1?.processID, 101)
        XCTAssertEqual(target.deliveries.first?.1?.selection?.location, 0)
        XCTAssertEqual(try fixture.history.recent().first?.llmEngine, fixture.nextLLM.model)
    }

    func testCapturedRefinerFailureStillKeepsRawTranscript() async throws {
        let fixture = try ConfigurationFixture(failRefinement: true)
        defer { fixture.close() }
        fixture.pipeline.processSamples(ConfigurationFixture.samples)
        fixture.settings.llm = LLMConfig(kind: .none)
        try await wait { !fixture.pipeline.isBusy }
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Recorded words")
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "LLM failed, using raw transcript")
        XCTAssertNotNil(try fixture.history.recent().first?.error)
    }

    func testPracticeUsesChosenSpeechInPreflightAndProcessingWithoutChangingBinding() async throws {
        for (selected, bound) in [(ASRProviderKind.senseVoice, ASRProviderKind.openAI), (.openAI, .senseVoice), (.senseVoice, .groq)] {
            let fixture = try ConfigurationFixture()
            defer { fixture.close() }
            fixture.settings.asr = ASRConfig(kind: selected, language: "en")
            var binding = ASRConfig(kind: bound)
            if bound == .groq { binding.model = "retired-model" }
            var profile = fixture.profiles.activeProfile
            profile.speechModel = ProfileSpeechModel(config: binding)
            fixture.profiles.update(profile)
            let savedProfiles = try Data(contentsOf: fixture.directory.appendingPathComponent("profiles.json"))
            fixture.settings.beginOnboardingPractice()
            try await fixture.pipeline.startFromAutomation()
            XCTAssertEqual(fixture.preflightASR?.kind, selected)
            XCTAssertFalse(fixture.preflightUsesLLM ?? true)
            fixture.pipeline.stopAndProcess()
            try await wait { !fixture.pipeline.isBusy }
            XCTAssertEqual(try fixture.history.recent().first?.asrEngine, fixture.settings.asr.engineID)
            XCTAssertTrue(fixture.probe.built.isEmpty)
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent("profiles.json")), savedProfiles)
            fixture.settings.endOnboardingPractice()
            XCTAssertEqual(fixture.pipeline.speechConfig.kind, bound)
            XCTAssertEqual(fixture.profiles.activeProfile, profile)
        }
    }

    private func wait(_ condition: @escaping () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "Injected pipeline operation did not complete")
    }
}

@MainActor
private final class ConfigurationFixture {
    static let samples = [Float](repeating: 0.1, count: 16_000)
    let suite = "airdraft.configuration.\(UUID())"
    let directory: URL
    let script: URL
    let settings: AppSettings
    let profiles: ProfileStore
    let history: HistoryStore
    let probe = ConfigurationProbe()
    var pipeline: DictationPipeline!
    var preflightASR: ASRConfig?
    var preflightLLM: LLMConfig?
    var preflightUsesLLM: Bool?
    var deliveries: [String] = []
    let nextLLM = LLMConfig(kind: .claudeCode, model: "next-refiner", minWordsForLLM: 0)
    var record: DictationRecord { DictationRecord(mode: "fixture", family: "general", rawTranscript: "Stored words",
        refinedText: "Stored words", finalText: "Stored words", asrEngine: "fixture", audioSeconds: 1,
        asrMs: 0, llmMs: 0, inserted: false) }

    init(failSpeechOnce: Bool = false, failRefinement: Bool = false, target: ConfigurationTarget? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        script = directory.appendingPathComponent("delivery-fixture")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .senseVoice, language: "en")
        settings.llm = LLMConfig(kind: .claudeCode, model: "original-refiner", minWordsForLLM: 0)
        settings.livePreviewEnabled = false
        settings.useAppContext = false
        profiles = ProfileStore(directory: directory)
        history = try HistoryStore(directory: directory)
        let probe = probe
        let failure = SpeechFailure(remaining: failSpeechOnce ? 1 : 0)
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("Configuration tests must not read credentials"); return nil
        }, transcriberBuilder: { ConfigurationSpeech(id: $0.engineID, failure: failure) }, refinerBuilder: { config in
            probe.append(config)
            return ConfigurationRefiner(id: config.model, fails: failRefinement)
        })
        pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory), profiles: profiles,
            history: history, factory: factory, recorder: ConfigurationRecorder(), inserter: target?.inserter(),
            insertText: { _, method, captured in
                guard let target else { XCTFail("The original script policy must survive retry"); return InsertionResult(method: .clipboardOnly, notice: nil) }
                target.deliveries.append((method, captured))
                return InsertionResult(method: .paste, notice: nil)
            },
            sendScript: { [weak self] _, path in await MainActor.run { self?.deliveries.append(path) } },
            recordingPreflight: { [weak self] asr, llm, usesLLM, _, _ in
                self?.preflightASR = asr; self?.preflightLLM = llm; self?.preflightUsesLLM = usesLLM
            }, requestMicrophoneAccess: { true })
        pipeline.insertionEnabled = false
    }
    func close() {
        pipeline.cancel()
        try? history.close()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ConfigurationTarget {
    let clipboard = NSPasteboard.withUniqueName()
    let field = AXUIElementCreateApplication(101)
    var currentPID: Int32 = 101
    var deliveries: [(InsertionMethod, InsertionTarget?)] = []
    func close() { clipboard.releaseGlobally() }
    func inserter() -> TextInserter {
        TextInserter(environment: .init(frontmostApplication: { .init(processID: self.currentPID, bundleID: "fixture.editor") },
            application: { .init(processID: $0, bundleID: "fixture.editor") }, activate: { _ in false }, isTrusted: { true },
            applicationFocus: { _ in self.field }, systemFocus: { self.field }, focusedWindow: { _ in nil },
            processID: { _ in self.currentPID }, readAttribute: { _, attribute in
                switch attribute as String {
                case kAXRoleAttribute as String: return (.success, kAXTextAreaRole as CFString)
                case kAXSelectedTextRangeAttribute as String:
                    var range = CFRange(location: self.currentPID == 101 ? 0 : 7, length: 0)
                    return (.success, AXValueCreate(.cfRange, &range))
                default: return (.attributeUnsupported, nil)
                }
            }, enableWebAccessibility: { _ in false }, postPaste: { XCTFail("Injected delivery must not post keys"); return false },
            pasteboard: clipboard))
    }
}

private final class ConfigurationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LLMConfig] = []
    var built: [LLMConfig] { lock.withLock { values } }
    func append(_ value: LLMConfig) { lock.withLock { values.append(value) } }
    func clear() { lock.withLock { values.removeAll() } }
}
private actor SpeechFailure {
    var remaining: Int
    init(remaining: Int) { self.remaining = remaining }
    func check() throws { if remaining > 0 { remaining -= 1; throw TranscriberError.timedOut } }
}
private struct ConfigurationSpeech: Transcriber {
    let id: String
    let failure: SpeechFailure
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try await failure.check()
        return Transcript(text: "Recorded words", engine: id, latencyMs: 0)
    }
}
private struct ConfigurationRefiner: Refiner {
    let id: String
    let fails: Bool
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        if fails { throw RefinerError.invalidResponse }
        return RefineResult(text: request.transcript, engine: id, latencyMs: 0, promptVersion: "fixture")
    }
}
private final class ConfigurationRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.1, count: 16_000) }
    func cancel() { isRecording = false }
}
