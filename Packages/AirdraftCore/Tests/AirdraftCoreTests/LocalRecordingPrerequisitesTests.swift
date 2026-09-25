import XCTest
@testable import AirdraftCore

@MainActor
final class LocalRecordingPrerequisitesTests: XCTestCase {
    private func environment() -> RecordingPrerequisites.Environment {
        .init(microphoneAuthorized: true, accessibilityAuthorized: true,
              devices: [.init(id: 7, uid: "local-test-input", name: "Test input", inputChannelCount: 2)],
              defaultDeviceID: 7,
              readCredential: { _ in XCTFail("Local recording must not access credentials"); return nil },
              installed: { _ in true }, appleIntelligenceUnavailable: { nil })
    }

    func testUnavailableLocalPrerequisitesBlockBeforeCapture() async throws {
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

    func testInvalidChannelsAreRejectedWithoutChoosingAnotherInput() {
        for channel in [-1, 2] {
            XCTAssertThrowsError(try RecordingPrerequisites.check(asr: .init(kind: .parakeet),
                llm: .init(kind: .none), refinementEnabled: false,
                microphone: .init(uid: "local-test-input", name: "Test input", channelIndex: channel),
                insertionEnabled: false, environment: environment())) { error in
                XCTAssertTrue(error.localizedDescription.contains("Input channel unavailable"))
            }
        }
    }

    func testScriptOutputDoesNotRequireAccessibilityPermission() throws {
        var environment = environment()
        environment.accessibilityAuthorized = false
        try RecordingPrerequisites.check(asr: .init(kind: .parakeet), llm: .init(kind: .none),
            refinementEnabled: false, microphone: .systemDefault, insertionEnabled: false,
            environment: environment)
    }

    func testAppleRefinementAvailabilityOnlyBlocksProfilesThatUseIt() throws {
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

private final class LocalPrerequisiteRecorder: AudioRecording, @unchecked Sendable {
    var starts = 0
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { starts += 1; isRecording = true }
    func stop() -> [Float] { isRecording = false; return [] }
    func cancel() { isRecording = false }
}
