import XCTest
@testable import AirdraftCore

@MainActor
final class LocalRecordingPrerequisitesTests: XCTestCase {
    func testInstalledModelLoadsOnceBeforeTheMicrophoneOpens() async throws {
        // An unloaded model shows Loading, then starts recording.
        do {
            let fixture = try StartupFixture()
            defer { fixture.cleanUp() }
            var states: [PipelineState] = []
            fixture.pipeline.onStateChange = { states.append($0) }
            let start = Task { try await fixture.pipeline.startFromAutomation() }
            await fixture.speech.waitForPreparation()
            XCTAssertEqual(fixture.pipeline.state, .preparingModel)
            XCTAssertEqual(fixture.recorder.starts, 0)
            XCTAssertEqual(fixture.microphoneRequests, 0)
            await fixture.speech.finishPreparation()
            try await start.value
            XCTAssertEqual(states, [.preparingModel, .recording])
            XCTAssertEqual(fixture.recorder.starts, 1)
            XCTAssertEqual(fixture.microphoneRequests, 1)
            XCTAssertNil(fixture.pipeline.lastIssue)
        }

        // An already loaded model starts without the Loading HUD.
        do {
            let fixture = try StartupFixture(ready: true)
            defer { fixture.cleanUp() }
            var states: [PipelineState] = []
            fixture.pipeline.onStateChange = { states.append($0) }
            try await fixture.pipeline.startFromAutomation()
            XCTAssertEqual(states, [.recording])
            let loads = await fixture.speech.loads
            XCTAssertEqual(loads, 0)
            XCTAssertEqual(fixture.recorder.starts, 1)
        }

        // Dictation joins an existing model load.
        do {
            let fixture = try StartupFixture()
            defer { fixture.cleanUp() }
            let load = Task { try await fixture.factory.prepare(fixture.settings.asr) }
            await fixture.speech.waitForPreparation()
            let start = Task { try await fixture.pipeline.startFromAutomation() }
            for _ in 0..<100 where fixture.pipeline.state != .preparingModel {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(fixture.pipeline.state, .preparingModel)
            await fixture.speech.finishPreparation()
            try await load.value
            try await start.value
            let loads = await fixture.speech.loads
            XCTAssertEqual(loads, 1)
            XCTAssertEqual(fixture.recorder.starts, 1)
        }
    }

    func testReleaseSetupChangeOrLoadFailureDuringLoadingNeverOpensTheMicrophone() async throws {
        // Release during loading cancels without starting the microphone.
        do {
            let fixture = try StartupFixture()
            defer { fixture.cleanUp() }
            let start = Task { try await fixture.pipeline.startFromAutomation() }
            await fixture.speech.waitForPreparation()
            fixture.pipeline.stopAndProcess()
            await fixture.speech.finishPreparation()
            do { try await start.value; XCTFail("Released startup must stay cancelled") }
            catch is CancellationError {}
            XCTAssertEqual(fixture.pipeline.state, .idle)
            XCTAssertEqual(fixture.recorder.starts, 0)
            XCTAssertEqual(fixture.microphoneRequests, 0)
            XCTAssertNil(fixture.pipeline.lastIssue)
        }

        // A setup change during loading cannot start the old recording.
        do {
            let fixture = try StartupFixture()
            defer { fixture.cleanUp() }
            let start = Task { try await fixture.pipeline.startFromAutomation() }
            await fixture.speech.waitForPreparation()
            fixture.settings.asr.kind = .senseVoice
            await fixture.speech.finishPreparation()
            do { try await start.value; XCTFail("Changed setup must reject the old request") }
            catch { XCTAssertTrue(error.localizedDescription.contains("setup changed")) }
            XCTAssertEqual(fixture.recorder.starts, 0)
            XCTAssertEqual(fixture.microphoneRequests, 0)
        }

        // A load failure reports its reason without opening the microphone.
        do {
            let fixture = try StartupFixture()
            defer { fixture.cleanUp() }
            let start = Task { try await fixture.pipeline.startFromAutomation() }
            await fixture.speech.waitForPreparation()
            await fixture.speech.finishPreparation(fail: true)
            do { try await start.value; XCTFail("Load failure must stop startup") }
            catch { XCTAssertTrue(error.localizedDescription.contains("Fixture model failed to load")) }
            XCTAssertEqual(fixture.recorder.starts, 0)
            XCTAssertEqual(fixture.microphoneRequests, 0)
        }
    }

    func testPrerequisitesBlockBeforeCaptureOnlyWhenTheyApply() async throws {
        // Unavailable local prerequisites block before capture.
        do {
            let cases: [(String, (inout RecordingPrerequisites.Environment) -> Void)] = [
                ("microphone", { $0.microphoneAuthorized = false }),
                ("Accessibility", { $0.accessibilityAuthorized = false }),
                ("unavailable", { $0.devices = [] }),
                ("speech model", { $0.installed = { _ in false } }),
            ]
            for (message, modify) in cases {
                var environment = environment()
                modify(&environment)
                let snapshot = environment
                let suite = "airdraft.local-prerequisites.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
                defer {
                    defaults.removePersistentDomain(forName: suite)
                    try? FileManager.default.removeItem(at: directory)
                }
                let settings = AppSettings(defaults: defaults)
                settings.asr = ASRConfig(kind: .parakeet)
                settings.llm = LLMConfig(kind: .none)
                settings.useAppContext = false
                settings.livePreviewEnabled = false
                settings.hudStyle = .none
                let recorder = LocalPrerequisiteRecorder()
                let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                    XCTFail("Blocked recording must not access credentials")
                    return nil
                })
                let pipeline = DictationPipeline(settings: settings,
                    dictionary: DictionaryStore(directory: directory), profiles: ProfileStore(directory: directory),
                    history: nil, factory: factory, recorder: recorder,
                    recordingPreflight: { asr, llm, refining, microphone, insertion in
                        try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: refining,
                            microphone: microphone, insertionEnabled: insertion, environment: snapshot)
                    }, requestMicrophoneAccess: {
                        XCTFail("A failed prerequisite must stop before requesting the microphone")
                        return true
                    })
                var blockedCount = 0
                pipeline.onRecordingBlocked = { blockedCount += 1 }

                do {
                    try await pipeline.startFromAutomation()
                    XCTFail("Missing \(message) must block recording")
                } catch {}

                XCTAssertEqual(recorder.starts, 0)
                XCTAssertEqual(blockedCount, 1)
                XCTAssertFalse(pipeline.isBusy)
                XCTAssertFalse(pipeline.isRecording)
                XCTAssertNil(pipeline.recordingStartedAt)
                XCTAssertTrue(pipeline.lastIssue?.localizedCaseInsensitiveContains(message) == true,
                              pipeline.lastIssue ?? "Missing issue")
                pipeline.cancel()
            }
        }

        // Invalid channels are rejected without choosing another input.
        do {
            for channel in [-1, 2] {
                XCTAssertThrowsError(try RecordingPrerequisites.check(asr: .init(kind: .parakeet),
                    llm: .init(kind: .none), refinementEnabled: false,
                    microphone: .init(uid: "local-test-input", name: "Test input", channelIndex: channel),
                    insertionEnabled: false, environment: environment())) { error in
                    XCTAssertTrue(error.localizedDescription.contains("Input channel unavailable"))
                }
            }
        }

        // Script output does not require Accessibility permission.
        do {
            var environment = environment()
            environment.accessibilityAuthorized = false
            try RecordingPrerequisites.check(asr: .init(kind: .parakeet), llm: .init(kind: .none),
                refinementEnabled: false, microphone: .systemDefault, insertionEnabled: false,
                environment: environment)
        }

        // Apple refinement availability only blocks profiles that use it.
        do {
            var environment = environment()
            environment.appleIntelligenceUnavailable = { "Apple model not ready" }
            XCTAssertThrowsError(try RecordingPrerequisites.check(asr: .init(kind: .apple),
                llm: .init(kind: .appleIntelligence), refinementEnabled: true,
                microphone: .systemDefault, insertionEnabled: true, environment: environment))
            try RecordingPrerequisites.check(asr: .init(kind: .apple), llm: .init(kind: .appleIntelligence),
                refinementEnabled: false, microphone: .systemDefault, insertionEnabled: true,
                environment: environment)
            environment.appleIntelligenceUnavailable = { nil }
            try RecordingPrerequisites.check(asr: .init(kind: .apple), llm: .init(kind: .appleIntelligence),
                refinementEnabled: true, microphone: .systemDefault, insertionEnabled: true,
                environment: environment)
        }
    }

    private func environment() -> RecordingPrerequisites.Environment {
        .init(microphoneAuthorized: true, accessibilityAuthorized: true,
              devices: [.init(id: 7, uid: "local-test-input", name: "Test input", inputChannelCount: 2)],
              defaultDeviceID: 7,
              readCredential: { _ in XCTFail("Local recording must not access credentials"); return nil },
              installed: { _ in true }, appleIntelligenceUnavailable: { nil })
    }

}

@MainActor
private final class StartupFixture {
    let suite = "airdraft.model-startup.\(UUID().uuidString)"
    let directory: URL
    let defaults: UserDefaults
    let settings: AppSettings
    let speech: StartupSpeech
    let factory: EngineFactory
    let recorder = LocalPrerequisiteRecorder()
    var microphoneRequests = 0
    var pipeline: DictationPipeline!

    init(ready: Bool = false) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        settings = AppSettings(defaults: defaults)
        settings.asr = ASRConfig(kind: .parakeet)
        settings.llm = LLMConfig(kind: .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        speech = StartupSpeech(id: settings.asr.engineID, ready: ready)
        factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("Local model startup must not access credentials"); return nil
        }, transcriberBuilder: { [speech] _ in speech })
        pipeline = DictationPipeline(settings: settings,
            dictionary: DictionaryStore(directory: directory), profiles: ProfileStore(directory: directory),
            history: nil, factory: factory, recorder: recorder,
            recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { [weak self] in
                await MainActor.run { self?.microphoneRequests += 1 }
                return true
            })
        pipeline.insertionEnabled = false
    }

    func cleanUp() {
        pipeline.cancel()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor StartupSpeech: Transcriber {
    nonisolated let id: String
    private var ready: Bool
    private(set) var loads = 0
    private var continuation: CheckedContinuation<Void, Error>?

    init(id: String, ready: Bool) { self.id = id; self.ready = ready }
    func isReady() -> Bool { ready }
    func prepare() async throws {
        loads += 1
        try await withCheckedThrowingContinuation { continuation = $0 }
        ready = true
    }
    func waitForPreparation() async {
        for _ in 0..<200 {
            if continuation != nil { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Model preparation did not start")
    }
    func finishPreparation(fail: Bool = false) {
        if fail { continuation?.resume(throwing: RecordingPrerequisiteError("Fixture model failed to load")) }
        else { continuation?.resume() }
        continuation = nil
    }
    func unload() async { ready = false }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        Transcript(text: "Fixture speech", engine: id, latencyMs: 0)
    }
}

/// Unchecked: test double driven only by the MainActor pipeline under test;
/// it never touches its fields or handlers from another thread.
private final class LocalPrerequisiteRecorder: AudioRecording, @unchecked Sendable {
    var starts = 0
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { starts += 1; isRecording = true }
    func stop() -> [Float] { isRecording = false; return [] }
    func cancel() { isRecording = false }
}
