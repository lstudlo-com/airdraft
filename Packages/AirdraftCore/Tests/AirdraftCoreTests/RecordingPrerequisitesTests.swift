import XCTest
@testable import AirdraftCore

@MainActor
final class RecordingPrerequisitesTests: XCTestCase {
    private func environment() -> RecordingPrerequisites.Environment {
        .init(microphoneAuthorized: true, accessibilityAuthorized: true,
              devices: [.init(id: 7, uid: "mic", name: "Test input", inputChannelCount: 2)], defaultDeviceID: 7,
              readCredential: { _ in "fixture-key" }, installed: { _ in true })
    }

    func testEachKnownPrerequisiteBlocksBeforeCaptureOrMicrophonePrompt() async throws {
        let failures: [(String, (inout RecordingPrerequisites.Environment) -> Void)] = [
            ("microphone", { $0.microphoneAuthorized = false }),
            ("Accessibility", { $0.accessibilityAuthorized = false }),
            ("unavailable", { $0.devices = [] }),
            ("API key", { $0.readCredential = { _ in nil } }),
            ("locked", { $0.readCredential = { _ in throw CocoaError(.fileReadNoPermission) } }),
        ]
        for (expected, modify) in failures {
            var env = environment()
            modify(&env)
            let fixture = env
            let suite = "airdraft.preflight.\(UUID().uuidString)"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .groq)
            settings.llm = LLMConfig(kind: .none)
            let recorder = NeverStartRecorder()
            let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
                profiles: ProfileStore(directory: directory), history: nil, factory: EngineFactory(status: EngineStatus()),
                recorder: recorder, recordingPreflight: { asr, llm, refining, mic, insert in
                    try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: refining,
                        microphone: mic, insertionEnabled: insert, environment: fixture)
                }, requestMicrophoneAccess: { XCTFail("Must fail before requesting capture permission"); return true })
            var blocked = false
            pipeline.onRecordingBlocked = { blocked = true }
            pipeline.startRecording()
            for _ in 0..<100 where pipeline.isBusy { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertFalse(pipeline.isRecording)
            XCTAssertTrue(blocked)
            XCTAssertTrue(pipeline.lastIssue?.contains(expected) == true, pipeline.lastIssue ?? "Missing issue")
            XCTAssertEqual(recorder.starts, 0)
            XCTAssertNil(pipeline.recordingStartedAt)
            pipeline.cancel()
        }
    }

    func testMissingModelInvalidChannelAndEndpointAreRejected() {
        var env = environment()
        env.installed = { _ in false }
        XCTAssertThrowsError(try check(.init(kind: .qwen3), env: env))
        env = environment()
        XCTAssertThrowsError(try check(.init(kind: .apple), mic: .init(uid: "mic", name: "Test", channelIndex: 3), env: env))
        var config = ASRConfig(kind: .openAICompatible)
        config.baseURL = "not a URL"
        XCTAssertThrowsError(try check(config, env: env))
    }

    func testRefinementOffNeedsNoRefinementKeyButEnabledCloudDoes() {
        var env = environment()
        env.readCredential = { $0.hasPrefix("llm.") ? nil : "speech-key" }
        XCTAssertNoThrow(try check(.init(kind: .groq), env: env))
        XCTAssertThrowsError(try check(.init(kind: .groq), llm: .init(kind: .anthropic), env: env))
    }

    func testReadySetupPassesWithoutRecordingOrNetwork() throws {
        try check(.init(kind: .groq), env: environment())
    }

    private func check(_ asr: ASRConfig, llm: LLMConfig = .init(kind: .none),
                       mic: MicrophonePreference = .systemDefault, env: RecordingPrerequisites.Environment) throws {
        try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: true,
            microphone: mic, insertionEnabled: true, environment: env)
    }
}

private final class NeverStartRecorder: AudioRecording, @unchecked Sendable {
    var starts = 0
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { starts += 1; isRecording = true }
    func stop() -> [Float] { isRecording = false; return [] }
    func cancel() { isRecording = false }
}
