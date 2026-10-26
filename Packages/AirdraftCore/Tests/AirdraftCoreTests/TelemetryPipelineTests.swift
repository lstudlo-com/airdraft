import XCTest
@testable import AirdraftCore

/// Pipeline, onboarding, download and license events through the real consent
/// gate and a fake client. Nothing is sent anywhere.
@MainActor
final class TelemetryPipelineTests: XCTestCase {
    private var cleanups: [() -> Void] = []

    override func tearDown() async throws {
        for cleanup in cleanups { cleanup() }
        cleanups = []
    }

    private func granted() -> TelemetryHarness {
        let harness = TelemetryHarness(consent: .granted)
        harness.telemetry.start()
        cleanups.append { harness.tearDown() }
        return harness
    }

    private func pipeline(speech: any Transcriber = TelemetrySpeech(text: "Ship the quarterly report to Alice today"),
                          insert: InsertionResult = InsertionResult(method: .paste, notice: nil),
                          preflight: (@MainActor (ASRConfig, LLMConfig, Bool, MicrophonePreference, Bool) async throws -> Void)? = { _, _, _, _, _ in },
                          access: @escaping @MainActor () async throws -> Void = {}) -> DictationPipeline {
        let suite = "airdraft.telemetry.pipeline.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        cleanups.append {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .parakeet)
        settings.llm = LLMConfig(kind: .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("Telemetry tests must not read credentials")
            return nil
        }, transcriberBuilder: { _ in speech })
        let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: ProfileStore(directory: directory), history: nil, factory: factory,
            recorder: TelemetryRecorder(), insertText: { _, _, _ in insert },
            recordingPreflight: preflight, accessCheck: access, requestMicrophoneAccess: { true })
        return pipeline
    }

    private func settle(_ pipeline: DictationPipeline) async throws {
        for _ in 0..<400 where pipeline.isBusy || pipeline.isFinishingDelivery { try await Task.sleep(for: .milliseconds(5)) }
    }

    /// Each phase uses its own harness and pipeline: a completed dictation reports only
    /// enumerated fields, telemetry never changes pipeline results, undelivered text counts
    /// as completed plus delivery_failed, a speech failure reports speech_error, and
    /// refinement fallback and latency map to buckets.
    func testDictationOutcomesReportEnumeratedEventsWithoutChangingResults() async throws {
        do {
            let harness = granted()
            let pipeline = pipeline()
            pipeline.telemetry = harness.telemetry
            pipeline.processSamples([Float](repeating: 0.1, count: 16_000))
            try await settle(pipeline)
            XCTAssertEqual(pipeline.lastOutcome?.final, "Ship the quarterly report to Alice today")
            XCTAssertEqual(harness.captured.map(\.event), ["dictation_completed"])
            XCTAssertEqual(harness.captured.first?.properties, [
                "app": "airdraft-mac", "speech_engine": "parakeet", "speech_location": "local",
                "refinement_provider": "none", "profile": "clean", "recording_duration": "0-5s",
                "stop_to_delivery": "unknown", "delivery_status": "delivered", "refinement_outcome": "none",
            ])
            let values = harness.captured.flatMap { $0.properties.values }.joined(separator: " ")
            for word in ["Ship", "quarterly", "Alice"] { XCTAssertFalse(values.contains(word), word) }
        }

        do {
            let without = pipeline()
            without.processSamples([Float](repeating: 0.1, count: 16_000))
            try await settle(without)
            let harness = granted()
            let with = pipeline()
            with.telemetry = harness.telemetry
            with.processSamples([Float](repeating: 0.1, count: 16_000))
            try await settle(with)
            XCTAssertEqual(without.lastOutcome?.final, with.lastOutcome?.final)
            XCTAssertEqual(without.state, with.state)
            XCTAssertEqual(without.lastIssue, with.lastIssue)
            XCTAssertFalse(harness.captured.isEmpty)
        }

        do {
            let harness = granted()
            let pipeline = pipeline(insert: InsertionResult(method: .clipboardOnly, notice: "Copied. Paste it."))
            pipeline.telemetry = harness.telemetry
            pipeline.processSamples([Float](repeating: 0.1, count: 16_000))
            try await settle(pipeline)
            XCTAssertEqual(harness.captured.map(\.event), ["dictation_completed", "dictation_failed"])
            XCTAssertEqual(harness.captured.first?.properties["delivery_status"], "notDelivered")
            XCTAssertEqual(harness.captured.last?.properties["category"], "delivery_failed")
        }

        do {
            let harness = granted()
            let pipeline = pipeline(speech: FailingTelemetrySpeech())
            pipeline.telemetry = harness.telemetry
            pipeline.processSamples([Float](repeating: 0.1, count: 16_000))
            try await settle(pipeline)
            XCTAssertTrue(pipeline.hasRecoverableRecording)
            XCTAssertEqual(harness.captured.map(\.event), ["dictation_failed"])
            XCTAssertEqual(harness.captured.first?.properties["category"], "speech_error")
        }

        do {
            let harness = granted()
            let pipeline = pipeline()
            pipeline.telemetry = harness.telemetry
            var timings = DictationTimings()
            timings.stopToDeliveryMs = 700
            let snapshot = pipeline.recordingSnapshot()
            pipeline.reportCompletion(.init(inserted: true, outputSucceeded: true),
                                      refinement: .init(refined: "raw", llmError: "timed out"),
                                      snapshot: snapshot, seconds: 42, timings: timings)
            pipeline.reportCompletion(.init(outputSucceeded: true, sentUnverified: true),
                                      refinement: .init(refined: "tidy", llmEngine: "apple-intelligence"),
                                      snapshot: snapshot, seconds: 3, timings: DictationTimings())
            pipeline.reportCompletion(.init(cancelledBeforeWriting: true), refinement: .init(refined: "x"),
                                      snapshot: snapshot, seconds: 3, timings: timings)
            XCTAssertEqual(harness.captured.map { $0.properties["refinement_outcome"] }, ["fallback", "applied"])
            XCTAssertEqual(harness.captured.map { $0.properties["stop_to_delivery"] }, ["500ms-1s", "unknown"])
            XCTAssertEqual(harness.captured.map { $0.properties["recording_duration"] }, ["30-60s", "0-5s"])
            XCTAssertEqual(harness.captured.map { $0.properties["delivery_status"] }, ["delivered", "sentUnverified"])
        }
    }

    /// Start failures use categories and skip setup changes and cancellation; the
    /// prerequisite checks tag their kinds.
    func testStartFailuresUseCategoriesAndPrerequisiteChecksTagTheirKinds() async throws {
        let cases: [(any Error, String?)] = [
            (RecordingPrerequisiteError("Allow microphone access in Settings.", kind: .permission), "permission"),
            (RecordingPrerequisiteError("Microphone unavailable.", kind: .microphone), "microphone_unavailable"),
            (RecordingPrerequisiteError("Install the speech model in Models.", kind: .modelMissing), "model_missing"),
            (RecordingPrerequisiteError("Add a speech API key in Models.", kind: .credential), "credential_missing"),
            (RecordingPrerequisiteError("Check the speech endpoint in Models.", kind: .setup), "setup_invalid"),
            (RecordingPrerequisiteError("Setup changed.", kind: .setupChanged), nil),
            (CancellationError(), nil),
            (URLError(.notConnectedToInternet), "other"),
        ]
        for (error, expected) in cases {
            let harness = granted()
            let pipeline = pipeline(preflight: { _, _, _, _, _ in throw error })
            pipeline.telemetry = harness.telemetry
            pipeline.startRecording()
            try await settle(pipeline)
            XCTAssertFalse(pipeline.isRecording)
            XCTAssertEqual(harness.captured.map { $0.properties["category"] }, expected.map { [$0] } ?? [], "\(error)")
        }
        let harness = granted()
        let licensed = pipeline(access: { throw LicenseError.accessRequired })
        licensed.telemetry = harness.telemetry
        licensed.startRecording()
        try await settle(licensed)
        XCTAssertEqual(harness.captured.map { $0.properties["category"] }, ["license_required"])

        let environment = RecordingPrerequisites.Environment(microphoneAuthorized: false, accessibilityAuthorized: true,
            devices: [], defaultDeviceID: nil, readCredential: { _ in nil }, installed: { _ in false })
        XCTAssertThrowsError(try RecordingPrerequisites.check(asr: ASRConfig(kind: .parakeet), llm: LLMConfig(kind: .none),
            refinementEnabled: false, microphone: .systemDefault, insertionEnabled: false, environment: environment)) {
            XCTAssertEqual(DictationPipeline.failureCategory(for: $0), .permission)
        }
        var ready = environment
        ready.microphoneAuthorized = true
        ready.devices = [Microphone(id: 1, uid: "fixture", name: "Fixture")]
        ready.defaultDeviceID = 1
        XCTAssertThrowsError(try RecordingPrerequisites.check(asr: ASRConfig(kind: .parakeet), llm: LLMConfig(kind: .none),
            refinementEnabled: false, microphone: .systemDefault, insertionEnabled: false, environment: ready)) {
            XCTAssertEqual(DictationPipeline.failureCategory(for: $0), .modelMissing)
        }
    }

    /// Onboarding counts only its first completion or skip, downloads report allowlisted
    /// catalogue IDs and outcomes, and a license trial start is counted; each phase has
    /// its own harness.
    func testOnboardingDownloadAndLicenseEventsAreCounted() async throws {
        do {
            let harness = granted()
            let suite = "airdraft.telemetry.onboarding.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            cleanups.append { defaults.removePersistentDomain(forName: suite) }
            let progress = OnboardingProgress(defaults: defaults, existingSetup: false)
            progress.telemetry = harness.telemetry
            progress.present()
            progress.dismiss()
            progress.present()
            progress.dismiss()
            XCTAssertEqual(harness.captured.map { $0.properties["outcome"] }, ["skipped"])
            progress.present()
            progress.move(to: .practice)
            progress.noteDelivery()
            XCTAssertTrue(progress.complete())
            progress.finish()
            progress.present()
            progress.move(to: .practice)
            progress.noteDelivery()
            progress.complete()
            progress.dismiss()
            XCTAssertEqual(harness.captured.map { $0.properties["outcome"] }, ["skipped", "completed"])
            let existing = OnboardingProgress(defaults: UserDefaults(suiteName: suite + ".existing")!, existingSetup: true)
            cleanups.append { UserDefaults(suiteName: suite + ".existing")?.removePersistentDomain(forName: suite + ".existing") }
            existing.telemetry = harness.telemetry
            existing.present()
            existing.dismiss()
            XCTAssertEqual(harness.captured.count, 2, "Existing setups are never counted as skipped")
        }

        do {
            let harness = granted()
            let outcomes = Locked<[Bool?]>([true, false, nil])
            let store = ModelDownloadStore(download: { _, _ in
                let next = outcomes.withLock { $0.removeFirst() }
                switch next {
                case true?: return
                case false?: throw ModelDownloader.DownloadError.emptyListing
                case nil: throw CancellationError()
                }
            }, installed: { _ in true })
            store.telemetry = harness.telemetry
            store.telemetryModelID = { $0.kind == .parakeet ? "qwen3:1.7b" : "mlx-community/private-model" }
            for kind in [ASRProviderKind.parakeet, .parakeet, .senseVoice] {
                store.start(ASRConfig(kind: kind))
                for _ in 0..<200 where store.isBusy { try await Task.sleep(for: .milliseconds(5)) }
            }
            // The unknown ID is refused by the allowlist, whatever its outcome.
            XCTAssertEqual(harness.captured.map { $0.properties["outcome"] }, ["ok", "failed"])
            XCTAssertEqual(harness.captured.map { $0.properties["model"] }, ["qwen3:1.7b", "qwen3:1.7b"])
        }

        do {
            let harness = granted()
            let configuration = PolarConfiguration(organizationID: UUID(), benefitIDs: [UUID()],
                checkoutURL: URL(string: "https://polar.sh/checkout/test-only")!, portalURL: URL(string: "https://polar.sh/test-only/portal")!)
            let store = LicenseStore(distribution: .official, configuration: configuration, storage: TelemetryLicenseStorage())
            store.telemetry = harness.telemetry
            await store.load()
            await store.startTrial()
            XCTAssertEqual(harness.captured.map { $0.properties["action"] }, ["trial_started"])
            XCTAssertEqual(TelemetryEvent.LicenseState(store.access), .trial)
        }
    }
}

private struct TelemetrySpeech: Transcriber {
    let text: String
    let id = "telemetry-speech"
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        Transcript(text: text, engine: id, latencyMs: 0)
    }
}

private struct FailingTelemetrySpeech: Transcriber {
    let id = "telemetry-failing"
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript { throw TranscriberError.timedOut }
}

/// Unchecked: driven only by the MainActor pipeline under test.
private final class TelemetryRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.1, count: 16_000) }
    func cancel() { isRecording = false }
}

private actor TelemetryLicenseStorage: LicenseStorage {
    var value: LicenseRecord? = LicenseRecord()
    func read(allowInteraction: Bool) throws -> LicenseRecord? { value }
    func write(_ record: LicenseRecord) throws { value = record }
}
