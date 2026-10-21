import Foundation
import XCTest
@testable import AirdraftCore

/// Real pipeline scheduling with injected capture, engines and delivery. These
/// fixtures never open a microphone, read a key, call a provider or paste text.
@MainActor
final class PipelinePreparationTests: XCTestCase {
    func testRecordingPreparationIsJoinedOnceAfterSpeechCompletes() async throws {
        let fixture = try Fixture()
        let gate = PreparationGate()
        defer { fixture.cleanUp(); Task { await gate.release() } }
        fixture.pipeline.prepareRefinement = { config in
            fixture.probe.prepared(config)
            await gate.enter()
            return .unmanaged
        }

        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Preparation starts during capture") { await gate.callCount == 1 }
        XCTAssertTrue(fixture.recorder.isRecording)
        XCTAssertEqual(fixture.probe.builtConfigs, [fixture.settings.llm])
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        let callsBeforeStop = await fixture.speech.callCount
        XCTAssertEqual(callsBeforeStop, 0)

        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Speech completes while preparation is pending") {
            await fixture.speech.callCount == 1 && fixture.pipeline.state == .refining
        }
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        let preparationsAfterStop = await gate.callCount
        XCTAssertEqual(preparationsAfterStop, 1)
        await gate.release()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.builtConfigs.count, 1)
        XCTAssertEqual(fixture.probe.preparedConfigs.count, 1)
        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testPreparationAndFinalRequestUseRecordingSnapshotAfterEdits() async throws {
        let fixture = try Fixture(text: "Final words floze")
        defer { fixture.cleanUp() }
        let entry = DictionaryEntry(term: "Airdraft", aliases: ["floze"])
        fixture.dictionary.add(entry)
        fixture.profiles.setBaseRules("Captured base rules")
        let capturedProfile = fixture.profiles.activeProfile
        let capturedConfig = fixture.settings.llm
        fixture.pipeline.prepareRefinement = { config in fixture.probe.prepared(config); return .unmanaged }
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Captured refiner is prepared") { !fixture.probe.preparedConfigs.isEmpty }

        fixture.settings.llm = LLMConfig(kind: .none)
        fixture.settings.asr.chineseScript = .simplified
        fixture.settings.useAppContext = true
        fixture.profiles.setActive(RefinementProfile.verbatimID)
        fixture.profiles.setBaseRules("New base rules")
        var edited = entry
        edited.term = "Changed"
        fixture.dictionary.update(edited)
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        let request = try XCTUnwrap(fixture.probe.requests.first)
        XCTAssertEqual(fixture.probe.builtConfigs, [capturedConfig])
        XCTAssertEqual(fixture.probe.preparedConfigs, [capturedConfig])
        XCTAssertEqual(request.profile, capturedProfile)
        XCTAssertEqual(request.baseRules, "Captured base rules")
        XCTAssertEqual(request.dictionary, [entry])
        XCTAssertEqual(request.chineseScript, .traditional)
        let capturedVocabulary = await fixture.speech.lastVocabulary
        XCTAssertEqual(capturedVocabulary, ["Airdraft"])
        XCTAssertEqual(fixture.probe.deliveries, ["Final words Airdraft"])

        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Next capture uses edited settings") { fixture.probe.deliveries.count == 2 && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        XCTAssertEqual(fixture.probe.builtConfigs.count, 1)
        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertEqual(fixture.probe.deliveries.last, "Final words Changed")
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "Verbatim: no LLM")
    }

    func testCancelledLatePreparationCannotReplaceTheNextSession() async throws {
        let fixture = try Fixture()
        let gate = PreparationGate()
        defer { fixture.cleanUp(); Task { await gate.release() } }
        let original = fixture.settings.llm
        fixture.pipeline.prepareRefinement = { config in
            fixture.probe.prepared(config)
            if config.model == original.model { await gate.enter() }
            return .unmanaged
        }
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Old preparation is suspended") { await gate.callCount == 1 }
        try fixture.pipeline.cancelFromAutomation()
        fixture.settings.llm.model = "replacement-model"
        let replacement = fixture.settings.llm
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(fixture.probe.builtConfigs, [original, replacement])
        XCTAssertEqual(fixture.probe.preparedConfigs, [original, replacement])
        XCTAssertEqual(fixture.probe.requestModels, [replacement.model])
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertEqual(try fixture.history.count(), 1)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")
    }

    func testPromptPrefixPreparationAndFinalRefinementShareTheCapturedRequest() async throws {
        let gate = PreparationGate()
        let fixture = try Fixture(text: "Final words floze", prefixWork: { _ in await gate.enter() })
        defer { fixture.cleanUp(); Task { await gate.release() } }
        let entry = DictionaryEntry(term: "Airdraft", aliases: ["floze"])
        fixture.dictionary.add(entry)
        fixture.profiles.setBaseRules("Captured prefix rules")
        let captured = fixture.settings.llm
        fixture.pipeline.prepareRefinement = { config in fixture.probe.prepared(config); return .lmStudio }
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Prompt prefix starts during recording") { await gate.callCount == 1 }
        XCTAssertTrue(fixture.recorder.isRecording)
        let prefix = try XCTUnwrap(fixture.probe.prefixRequests.first)
        XCTAssertTrue(prefix.transcript.isEmpty, "Prefix preparation must not contain unfinished speech")

        fixture.settings.llm.kind = .none
        fixture.profiles.setActive(RefinementProfile.verbatimID)
        fixture.profiles.setBaseRules("Changed rules")
        var edited = entry
        edited.term = "Changed"
        fixture.dictionary.update(edited)
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)
        let stillPending = await gate.waitingCount
        XCTAssertEqual(stillPending, 1, "A prefix operation that ignores cancellation must not block final refinement")

        let final = try XCTUnwrap(fixture.probe.requests.first)
        XCTAssertEqual(PromptBuilder.systemPrompt(for: prefix), PromptBuilder.systemPrompt(for: final))
        XCTAssertEqual(prefix.context, final.context)
        XCTAssertEqual(prefix.baseRules, "Captured prefix rules")
        XCTAssertEqual(prefix.dictionary, [entry])
        XCTAssertEqual(fixture.probe.preparedConfigs, [captured])
        XCTAssertEqual(fixture.probe.prefixBackends, [.lmStudio])
        XCTAssertEqual(fixture.probe.requestUsedPreparedValue, [true],
                       "Refinement must use the refiner returned by prepare, rather than rebuild it")
        XCTAssertEqual(fixture.probe.deliveries, ["Final words Airdraft"])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(fixture.pipeline.lastOutcome).timings.promptPrefixMs, 300)
        XCTAssertEqual(try fixture.history.count(), 1)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fixture.probe.deliveries.count, 1)
    }

    func testCancelledPromptPrefixCannotRefineOrPublishIntoTheReplacementRecording() async throws {
        let gate = PreparationGate()
        let originalModel = Fixture.config.model
        let fixture = try Fixture(prefixWork: { config in
            if config.model == originalModel { await gate.enter() }
        })
        defer { fixture.cleanUp(); Task { await gate.release() } }
        fixture.pipeline.prepareRefinement = { _ in .lmStudio }
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Old prompt prefix is pending") { await gate.callCount == 1 }
        try fixture.pipeline.cancelFromAutomation()
        fixture.settings.llm.model = "replacement-prefix-model"
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(fixture.probe.prefixRequests.count, 2)
        XCTAssertEqual(Set(fixture.probe.prefixOwners).count, 2, "Preparation belongs to a distinct recording owner")
        XCTAssertEqual(fixture.probe.requestModels, ["replacement-prefix-model"])
        XCTAssertEqual(fixture.probe.requestUsedPreparedValue, [true])
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testTimedOutPromptPrefixDoesNotConsumeTheFinalRequestBudgetOrDeliverLateOutput() async throws {
        let gate = PreparationGate()
        let fixture = try Fixture(refineDelay: .milliseconds(10), prefixWork: { _ in await gate.enter() })
        defer { fixture.cleanUp(); Task { await gate.release() } }
        fixture.settings.llm.timeoutSeconds = 0.08
        fixture.pipeline.prepareRefinement = { _ in .lmStudio }
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Prompt prefix starts") { await gate.callCount == 1 }
        try await Task.sleep(for: .milliseconds(100))
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        let outcome = try XCTUnwrap(fixture.pipeline.lastOutcome)
        XCTAssertGreaterThanOrEqual(outcome.timings.promptPrefixMs, 70)
        XCTAssertLessThan(outcome.timings.preparationWaitMs, 70)
        XCTAssertLessThan(outcome.llmMs, 80)
        XCTAssertNil(outcome.llmSkippedReason)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        let stillPending = await gate.waitingCount
        XCTAssertEqual(stillPending, 1)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertEqual(fixture.probe.deliveries.count, 1)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testFailedPreparationDeliversRawTranscriptAndPersistsItsError() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.pipeline.prepareRefinement = { _ in throw PreparationError.unavailable }
        fixture.pipeline.processSamples(Fixture.samples)
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.builtConfigs.count, 1)
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "LLM failed, using raw transcript")
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.finalText, "Final words")
        XCTAssertEqual(record.outputSucceeded, true)
        XCTAssertTrue(record.error?.contains("preparation fixture unavailable") == true)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
    }

    func testPreparationDeadlineCanAbandonAnUncooperativeLoaderWithoutLateDelivery() async throws {
        let fixture = try Fixture()
        let gate = PreparationGate()
        defer { fixture.cleanUp(); Task { await gate.release() } }
        fixture.settings.llm.timeoutSeconds = 0.08
        fixture.pipeline.prepareRefinement = { _ in await gate.enter(); return .unmanaged }
        fixture.pipeline.processSamples(Fixture.samples)
        try await waitUntil("Loader starts") { await gate.callCount == 1 }
        try await finished(fixture)
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "LLM failed, using raw transcript")
        let timedOut = try XCTUnwrap(fixture.pipeline.lastOutcome)
        XCTAssertGreaterThanOrEqual(timedOut.timings.modelPreparationMs, 70,
                                    "An unfinished loader still contributes its elapsed preparation time")
        XCTAssertGreaterThanOrEqual(timedOut.timings.preparationWaitMs, 70)
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        XCTAssertEqual(fixture.probe.deliveries.count, 1)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testRecordingPreparationCanOutlastFinalRequestBudgetWithoutAnEarlyTimeout() async throws {
        let fixture = try Fixture(refineDelay: .milliseconds(10))
        defer { fixture.cleanUp() }
        fixture.settings.llm.timeoutSeconds = 0.08
        fixture.pipeline.prepareRefinement = { _ in try await Task.sleep(for: .milliseconds(250)); return .unmanaged }
        try await fixture.pipeline.startFromAutomation()
        try await Task.sleep(for: .milliseconds(300))
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertNil(fixture.pipeline.lastOutcome?.llmSkippedReason)
        let outcome = try XCTUnwrap(fixture.pipeline.lastOutcome)
        XCTAssertGreaterThanOrEqual(outcome.timings.modelPreparationMs, 240)
        XCTAssertLessThan(outcome.llmMs, 80,
                          "Work completed while recording must not consume the final request budget")
    }

    func testDisabledAndVerbatimRefinementNeverBuildOrPrepare() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.pipeline.prepareRefinement = { _ in XCTFail("Disabled refinement must not prepare"); return .unmanaged }
        fixture.settings.llm.kind = .none
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        fixture.settings.llm = Fixture.config
        fixture.profiles.setActive(RefinementProfile.verbatimID)
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Verbatim output completes") { fixture.probe.deliveries.count == 2 && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        XCTAssertTrue(fixture.probe.builtConfigs.isEmpty)
        XCTAssertTrue(fixture.probe.requests.isEmpty)
    }

    func testSkippedShortUtteranceDoesNotReportSpeculativePreparationFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.llm.minWordsForLLM = 10
        fixture.pipeline.prepareRefinement = { _ in throw PreparationError.unavailable }
        fixture.pipeline.processSamples(Fixture.samples)
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        XCTAssertNil(fixture.pipeline.lastIssue)
        XCTAssertNil(try fixture.history.recent().first?.error)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "short utterance (2 words)")
    }

    func testDiscardedTooShortRecordingCannotKeepItsPreparedRefinerForTheNextCapture() async throws {
        let fixture = try Fixture()
        let gate = PreparationGate()
        defer { fixture.cleanUp(); Task { await gate.release() } }
        fixture.recorder.samples = Array(Fixture.samples.prefix(1_600))
        fixture.pipeline.prepareRefinement = { config in
            fixture.probe.prepared(config)
            await gate.enter()
            return .unmanaged
        }
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Short capture prepares") { await gate.callCount == 1 }
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Short capture is discarded") { !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        XCTAssertTrue(fixture.probe.requests.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)
        await gate.release()
        fixture.recorder.samples = Fixture.samples
        fixture.pipeline.prepareRefinement = { config in fixture.probe.prepared(config); return .unmanaged }
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)
        XCTAssertEqual(fixture.probe.builtConfigs.count, 2)
        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertEqual(fixture.probe.deliveries.count, 1)
    }

    func testSpeechRetryPreparesTheCurrentRefinerAndKeepsDeliverySingle() async throws {
        let fixture = try Fixture(speechResponses: [.failure, .text("Recovered words")])
        defer { fixture.cleanUp() }
        fixture.pipeline.prepareRefinement = { config in fixture.probe.prepared(config); return .unmanaged }
        fixture.pipeline.processSamples(Fixture.samples)
        try await waitUntil("Speech audio becomes recoverable") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        fixture.settings.llm.model = "retry-model"
        fixture.pipeline.retryRecording()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.requestModels, ["retry-model"])
        XCTAssertEqual(fixture.probe.deliveries, ["Recovered words"])
        XCTAssertEqual(try fixture.history.count(), 1)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
    }

    func testReviewRetranscriptionPreparesButNeverDeliversOrDuplicatesHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.pipeline.prepareRefinement = { config in fixture.probe.prepared(config); return .unmanaged }
        let record = DictationRecord(mode: "clean", family: "document", rawTranscript: "Original words",
            refinedText: "Original words", finalText: "Original words", asrEngine: "fixture",
            audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: false)
        let saved = try fixture.history.save(record, samples: Fixture.samples)
        XCTAssertNotNil(saved.audioFilename)
        XCTAssertEqual(try fixture.history.audioSamples(for: saved).count, Fixture.samples.count)
        fixture.pipeline.retranscribe(saved)
        try await waitUntil("Review finishes") { fixture.pipeline.reviewOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
        XCTAssertEqual(fixture.probe.builtConfigs.count, 1)
        XCTAssertEqual(fixture.probe.preparedConfigs.count, 1)
        XCTAssertEqual(fixture.probe.requests.count, 1)
        XCTAssertTrue(fixture.probe.deliveries.isEmpty)
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    /// A service with fixed preparation/decode/refine delays runs through the
    /// production pipeline twice. The control starts service preparation on its
    /// first refine call; the optimized run starts the same work during capture.
    /// Captured audio, grace period, decode, refine, delivery and history match.
    func testRecordingOverlapReducesMeasuredStopToDeliveryWithTheSameServiceWork() async throws {
        var measurements: [String: Double] = [:]
        for warm in [false, true] {
            let service = PreparationService(delay: .milliseconds(600))
            let fixture = try Fixture(decodeDelay: .milliseconds(120), refineDelay: .milliseconds(80), service: service)
            defer { fixture.cleanUp() }
            if warm { fixture.pipeline.prepareRefinement = { _ in try await service.prepare(); return .unmanaged } }
            try await fixture.pipeline.startFromAutomation()
            // Equal speaking time in both runs; the samples remain identical.
            try await Task.sleep(for: .milliseconds(700))
            let stopped = ProcessInfo.processInfo.systemUptime
            var deliveredAt: TimeInterval?
            fixture.pipeline.onOutputDelivered = { deliveredAt = ProcessInfo.processInfo.systemUptime }
            try fixture.pipeline.stopFromAutomation()
            try await finished(fixture)
            let delivery = try XCTUnwrap(deliveredAt)
            let measured = (delivery - stopped) * 1_000
            measurements[warm ? "overlappedStopToDeliveryMs" : "controlStopToDeliveryMs"] = measured
            let outcome = try XCTUnwrap(fixture.pipeline.lastOutcome)
            let reportedStop = try XCTUnwrap(outcome.timings.stopToDeliveryMs)
            XCTAssertEqual(Double(reportedStop), measured, accuracy: 30,
                           "Timing must end at actual delivery feedback, including the key-release grace period")
            XCTAssertGreaterThanOrEqual(outcome.timings.refinementRequestMs, 70)
            XCTAssertGreaterThanOrEqual(outcome.timings.processingMs, outcome.asrMs + outcome.llmMs - 5)
            if warm {
                XCTAssertGreaterThanOrEqual(outcome.timings.modelPreparationMs, 550)
                XCTAssertLessThan(outcome.timings.preparationWaitMs, 100,
                                  "Preparation already completed while speaking must not count as final waiting")
            }
            let servicePreparations = await service.prepareCount
            XCTAssertEqual(servicePreparations, 1, "Both paths must do exactly the same service preparation")
            XCTAssertEqual(fixture.probe.builtConfigs.count, 1)
            XCTAssertEqual(fixture.probe.deliveries, ["Final words"])
            XCTAssertEqual(try fixture.history.count(), 1)
        }
        let control = try XCTUnwrap(measurements["controlStopToDeliveryMs"])
        let overlapped = try XCTUnwrap(measurements["overlappedStopToDeliveryMs"])
        measurements["reductionMs"] = control - overlapped
        measurements["reductionPercent"] = (control - overlapped) / control * 100
        XCTAssertGreaterThan(control - overlapped, 400, "Provider preparation must be removed from the stop-to-delivery critical path")
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "refinement-preparation-overlap.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("REFINEMENT_OVERLAP_BENCHMARK " + String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\n", with: " "))
    }

    private func finished(_ fixture: Fixture) async throws {
        try await waitUntil("Delivery and history complete") { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 4,
                           file: StaticString = #filePath, line: UInt = #line,
                           condition: () async -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(description + " timed out", file: file, line: line)
        throw PreparationError.timedOut
    }

    @MainActor
    private struct Fixture {
        static let samples = [Float](repeating: 0.125, count: 16_000)
        static var config: LLMConfig { LLMConfig(kind: .openAICompatible, baseURL: "http://localhost:1234/v1",
                                                model: "captured-model", minWordsForLLM: 0) }
        let suite: String
        let directory: URL
        let settings: AppSettings
        let dictionary: DictionaryStore
        let profiles: ProfileStore
        let history: HistoryStore
        let recorder: PreparationRecorder
        let speech: PreparationSpeech
        let pipeline: DictationPipeline
        let probe: PreparationProbe

        init(text: String = "Final words", speechResponses: [PreparationSpeech.Response]? = nil,
             decodeDelay: Duration = .zero, refineDelay: Duration = .zero,
             service: PreparationService? = nil,
             prefixWork: (@Sendable (LLMConfig) async throws -> Void)? = nil) throws {
            suite = "airdraft.pipeline-preparation.\(UUID().uuidString)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let script = directory.appendingPathComponent("output.sh")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet, chineseScript: .traditional)
            settings.llm = Self.config
            settings.useAppContext = false
            settings.livePreviewEnabled = false
            settings.outputDestination = .script
            settings.outputScriptPath = script.path
            history = try HistoryStore(directory: directory)
            dictionary = DictionaryStore(directory: directory)
            profiles = ProfileStore(directory: directory)
            recorder = PreparationRecorder(samples: Self.samples)
            let speech = PreparationSpeech(responses: speechResponses ?? [.text(text)], delay: decodeDelay)
            self.speech = speech
            let probe = PreparationProbe()
            self.probe = probe
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Preparation fixtures must not read credentials")
                return nil
            }, transcriberBuilder: { _ in speech }, refinerBuilder: { config in
                probe.built(config)
                return PreparationRefiner(config: config, probe: probe, delay: refineDelay, service: service, prefixWork: prefixWork)
            })
            pipeline = DictationPipeline(settings: settings, dictionary: dictionary, profiles: profiles,
                history: history, factory: factory, recorder: recorder,
                sendScript: { text, _ in probe.delivered(text) },
                recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
        }

        func cleanUp() {
            pipeline.cancel()
            pipeline.onOutputDelivered = nil
            do { try history.close(); try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Preparation fixture cleanup failed: \(error)") }
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }
}

private enum PreparationError: Error, LocalizedError {
    case unavailable, timedOut
    var errorDescription: String? {
        switch self {
        case .unavailable: return "preparation fixture unavailable"
        case .timedOut: return "preparation fixture timed out"
        }
    }
}

/// Ignores cancellation deliberately, like an already accepted native load.
private actor PreparationGate {
    private var waits: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0
    var waitingCount: Int { waits.count }
    func enter() async {
        callCount += 1
        await withCheckedContinuation { waits.append($0) }
    }
    func release() { let current = waits; waits.removeAll(); current.forEach { $0.resume() } }
}

private final class PreparationProbe: Sendable {
    private struct State: Sendable {
        var builds: [LLMConfig] = []
        var preparations: [LLMConfig] = []
        var refinements: [(LLMConfig, RefineRequest)] = []
        var prefixPreparations: [(LLMConfig, RefineRequest, RefinementPreparationBackend, UUID)] = []
        var preparedValueUsed: [Bool] = []
        var outputs: [String] = []
    }
    private let state = Locked(State())
    var builtConfigs: [LLMConfig] { state.value.builds }
    var preparedConfigs: [LLMConfig] { state.value.preparations }
    var requests: [RefineRequest] { state.value.refinements.map(\.1) }
    var requestModels: [String] { state.value.refinements.map { $0.0.model } }
    var deliveries: [String] { state.value.outputs }
    var prefixRequests: [RefineRequest] { state.value.prefixPreparations.map(\.1) }
    var prefixBackends: [RefinementPreparationBackend] { state.value.prefixPreparations.map(\.2) }
    var prefixOwners: [UUID] { state.value.prefixPreparations.map(\.3) }
    var requestUsedPreparedValue: [Bool] { state.value.preparedValueUsed }
    func built(_ config: LLMConfig) { state.withLock { $0.builds.append(config) } }
    func prepared(_ config: LLMConfig) { state.withLock { $0.preparations.append(config) } }
    func prefixPrepared(_ request: RefineRequest, config: LLMConfig, backend: RefinementPreparationBackend, owner: UUID) {
        state.withLock { $0.prefixPreparations.append((config, request, backend, owner)) }
    }
    func refined(_ request: RefineRequest, config: LLMConfig, prepared: Bool) {
        state.withLock { $0.refinements.append((config, request)); $0.preparedValueUsed.append(prepared) }
    }
    func delivered(_ text: String) { state.withLock { $0.outputs.append(text) } }
}

private struct PreparationRefiner: Refiner {
    let config: LLMConfig
    let probe: PreparationProbe
    let delay: Duration
    let service: PreparationService?
    let prefixWork: (@Sendable (LLMConfig) async throws -> Void)?
    var preparedValueBound = false
    var preparationOwner: UUID?
    var id: String { "preparation-fixture:\(config.model)" }
    func prepare(_ request: RefineRequest, backend: RefinementPreparationBackend, owner: UUID) async throws -> any Refiner {
        try Task.checkCancellation()
        var prepared = self
        prepared.preparedValueBound = true
        prepared.preparationOwner = owner
        return prepared
    }
    func prewarmPrompt(_ request: RefineRequest, backend: RefinementPreparationBackend) async throws {
        guard let preparationOwner else { throw PreparationError.unavailable }
        probe.prefixPrepared(request, config: config, backend: backend, owner: preparationOwner)
        try await prefixWork?(config)
        try Task.checkCancellation()
    }
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        if let service { try await service.prepare() }
        if delay > .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        probe.refined(request, config: config, prepared: preparedValueBound)
        return RefineResult(text: request.transcript, engine: id, latencyMs: 0, promptVersion: "fixture")
    }
}

private actor PreparationSpeech: Transcriber {
    enum Response: Sendable { case text(String), failure }
    nonisolated let id = "preparation-fixture-speech"
    private let responses: [Response]
    private let delay: Duration
    private(set) var callCount = 0
    private(set) var lastVocabulary: [String] = []
    init(responses: [Response], delay: Duration) { self.responses = responses; self.delay = delay }
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        let index = min(callCount, responses.count - 1)
        callCount += 1
        lastVocabulary = hints.vocabulary
        if delay > .zero { try await Task.sleep(for: delay) }
        switch responses[index] {
        case .failure: throw TranscriberError.timedOut
        case .text(let text): return Transcript(text: text, engine: id, latencyMs: 0)
        }
    }
}

/// Unchecked: test double driven only by the MainActor pipeline under test;
/// it never touches its fields or handlers from another thread.
private final class PreparationRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var samples: [Float]
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    init(samples: [Float]) { self.samples = samples }
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return samples }
    func cancel() { isRecording = false }
}

private actor PreparationService {
    private let delay: Duration
    private var task: Task<Void, Error>?
    private(set) var prepareCount = 0
    init(delay: Duration) { self.delay = delay }
    func prepare() async throws {
        let current: Task<Void, Error>
        if let task { current = task }
        else {
            prepareCount += 1
            let delay = delay
            current = Task { try await Task.sleep(for: delay) }
            task = current
        }
        try await current.value
        try Task.checkCancellation()
    }
}
