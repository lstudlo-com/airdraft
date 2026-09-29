import Foundation
import XCTest
@testable import AirdraftCore

@MainActor
final class PipelineAutomationTests: XCTestCase {
    func testAccessIsCheckedBeforeManualAndAutomationCaptureOrAudioProcessing() async throws {
        var checks = 0
        let fixture = try Fixture(accessCheck: { checks += 1; throw LicenseError.accessRequired })
        defer { fixture.cleanUp() }
        do { try await fixture.pipeline.startFromAutomation(); XCTFail("Must reject expired access") }
        catch {}
        XCTAssertFalse(fixture.recorder.isRecording)
        fixture.pipeline.startRecording()
        try await waitUntil("Manual access check") { checks == 2 }
        XCTAssertFalse(fixture.recorder.isRecording)
        fixture.pipeline.processSamples(Fixture.samples)
        try await waitUntil("Audio access check") { checks == 3 }
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)
        let original = try fixture.saveOriginal()
        fixture.pipeline.retranscribe(original)
        try await waitUntil("History access check") { checks == 4 }
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testExpiryCannotInterruptAnAlreadyStartedRecording() async throws {
        var allowed = true
        let fixture = try Fixture(accessCheck: { if !allowed { throw LicenseError.accessRequired } })
        defer { fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()
        allowed = false
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)
        XCTAssertEqual(fixture.probe.scripts.count, 1)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testCapturedAudioRemainsRecoverableAfterAccessExpires() async throws {
        var allowed = true
        let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered words")]),
                                  accessCheck: { if !allowed { throw LicenseError.accessRequired } })
        defer { fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Audio retained") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy }
        allowed = false
        fixture.pipeline.retryRecording()
        try await finished(fixture)
        XCTAssertEqual(fixture.probe.scripts.count, 1)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testScriptReceivesOnlyFinalTextAfterChineseConversionAndDictionary() async throws {
        let fixture = try Fixture(speech: AutomationSpeech([.text("汉语 floze")]))
        defer { fixture.cleanUp() }
        fixture.settings.asr.chineseScript = .traditional
        fixture.dictionary.add(DictionaryEntry(term: "Airdraft", aliases: ["floze"]))
        var delivered = 0
        fixture.pipeline.onOutputDelivered = {
            delivered += 1
            XCTAssertEqual(fixture.pipeline.state, .inserting)
            XCTAssertEqual(try? fixture.history.count(), 0, "Delivery feedback must not wait for history")
            XCTAssertNil(fixture.pipeline.lastOutcome)
        }

        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts, [.init(text: "漢語 Airdraft", path: fixture.firstScript.path)])
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.rawTranscript, "汉语 floze")
        XCTAssertEqual(record.refinedText, "汉语 floze")
        XCTAssertEqual(record.finalText, "漢語 Airdraft")
        XCTAssertEqual(record.outputDestination, TextOutputDestination.script.rawValue)
        XCTAssertEqual(record.outputSucceeded, true)
        XCTAssertFalse(record.inserted, "Script delivery is not insertion into the focused field")
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "漢語 Airdraft")
        XCTAssertEqual(delivered, 1)
    }

    func testScriptDestinationAndPathAreSnapshottedWhileRecording() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()

        fixture.settings.outputDestination = .cursor
        fixture.settings.outputScriptPath = fixture.secondScript.path
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts, [.init(text: "Final words", path: fixture.firstScript.path)])
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertEqual(try fixture.history.recent().first?.outputDestination, TextOutputDestination.script.rawValue)
    }

    func testCursorDestinationDoesNotTurnIntoScriptDeliveryMidRecording() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.outputDestination = .cursor
        var delivered = 0
        fixture.pipeline.onOutputDelivered = {
            delivered += 1
            XCTAssertEqual(fixture.pipeline.state, .inserting)
            XCTAssertEqual(try? fixture.history.count(), 0)
            XCTAssertNil(fixture.pipeline.lastOutcome)
        }
        try await fixture.pipeline.startFromAutomation()

        fixture.settings.outputDestination = .script
        fixture.settings.outputScriptPath = fixture.secondScript.path
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(fixture.probe.insertedTexts, ["Final words"])
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.outputDestination, TextOutputDestination.cursor.rawValue)
        XCTAssertEqual(record.outputSucceeded, true)
        XCTAssertTrue(record.inserted)
        XCTAssertEqual(delivered, 1)
    }

    func testScriptFailurePreservesFinalTextWithoutPasteOrDeliveryRetry() async throws {
        let fixture = try Fixture(scriptFails: true)
        defer { fixture.cleanUp() }
        fixture.pipeline.onOutputDelivered = { XCTFail("Failed delivery must keep recovery feedback visible") }
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts.count, 1)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertTrue(fixture.pipeline.lastIssue?.contains("script fixture failed") == true)
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.finalText, "Final words")
        XCTAssertEqual(record.outputDestination, TextOutputDestination.script.rawValue)
        XCTAssertEqual(record.outputSucceeded, false)
        XCTAssertFalse(record.inserted)
        XCTAssertNotNil(record.error)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")

        fixture.pipeline.retryRecording()
        await fixture.pipeline.retryHistorySave()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(fixture.probe.scripts.count, 1, "Saving history or retrying absent audio must never repeat a script")
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testSpeechRecoveryKeepsOriginalScriptDestinationAndPath() async throws {
        let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered words")]))
        defer { fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Speech failure retains audio") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy }
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)

        fixture.settings.outputDestination = .cursor
        fixture.settings.outputScriptPath = fixture.secondScript.path
        fixture.pipeline.retryRecording()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts, [.init(text: "Recovered words", path: fixture.firstScript.path)])
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertEqual(try fixture.history.recent().first?.outputSucceeded, true)
    }

    func testReviewOnlyRetranscriptionAndRecoveryNeverExecuteScript() async throws {
        let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Reviewed words")]))
        defer { fixture.cleanUp() }
        fixture.pipeline.onOutputDelivered = { XCTFail("Review-only text is not delivered") }
        let original = try fixture.saveOriginal()
        fixture.pipeline.retranscribe(original)
        try await waitUntil("Review speech failure retains audio") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy }
        fixture.pipeline.retryRecording()
        try await waitUntil("Review retry completes") { fixture.pipeline.reviewOutcome != nil && !fixture.pipeline.isBusy }

        XCTAssertEqual(fixture.pipeline.reviewOutcome?.final, "Reviewed words")
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertNil(fixture.pipeline.lastOutcome)
        XCTAssertEqual(try fixture.history.recent(), [original])
    }

    func testInsertionDisabledAlsoSuppressesScripts() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.pipeline.insertionEnabled = false
        fixture.pipeline.onOutputDelivered = { XCTFail("Disabled output is not delivered") }
        fixture.pipeline.processSamples(Fixture.samples)
        try await finished(fixture)

        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")
        XCTAssertFalse(try XCTUnwrap(fixture.history.recent().first).inserted)
    }

    func testAutomationCancelCannotInterruptScriptAfterDeliveryStarts() async throws {
        let gate = AutomationStartupGate()
        let fixture = try Fixture(deliveryGate: gate)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Script delivery starts") { gate.callCount == 1 }
        XCTAssertEqual(fixture.pipeline.state, .inserting)
        do {
            try fixture.pipeline.cancelFromAutomation()
            XCTFail("An external side effect already in flight cannot be cancelled safely")
        } catch {}
        XCTAssertTrue(fixture.pipeline.isBusy)
        gate.release()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts.count, 1)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertEqual(try fixture.history.recent().first?.outputSucceeded, true)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testCancelledStartupCannotReviveOrCancelNewAutomationRecording() async throws {
        let gate = AutomationStartupGate()
        let fixture = try Fixture(startupGate: gate)
        let firstStart = Task { () -> Bool in
            do { try await fixture.pipeline.startFromAutomation(); return true }
            catch { return false }
        }
        defer { gate.release(); firstStart.cancel(); fixture.cleanUp() }
        try await waitUntil("First startup reaches suspended preflight") { gate.callCount == 1 }
        do {
            try await fixture.pipeline.startFromAutomation()
            XCTFail("Concurrent automation start must fail instead of starting another microphone")
        } catch {}
        XCTAssertEqual(gate.callCount, 1)
        XCTAssertEqual(fixture.recorder.startCount, 0)

        try fixture.pipeline.cancelFromAutomation()
        try await fixture.pipeline.startFromAutomation()
        XCTAssertTrue(fixture.pipeline.isRecording)
        XCTAssertEqual(fixture.recorder.startCount, 1)
        gate.release()
        let firstSucceeded = await firstStart.value
        XCTAssertFalse(firstSucceeded, "The superseded start must not report the newer recording as its success")
        XCTAssertTrue(fixture.pipeline.isRecording, "A stale startup must not cancel the replacement recording")
        XCTAssertTrue(fixture.recorder.isRecording)
        XCTAssertEqual(fixture.recorder.startCount, 1)
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)
    }

    func testCancellingAutomationStartReturnsBeforeUncooperativePreflightFinishes() async throws {
        let gate = AutomationStartupGate()
        let fixture = try Fixture(startupGate: gate)
        let returned = expectation(description: "Cancelled automation start returns without waiting for preflight")
        let start = Task {
            do {
                try await fixture.pipeline.startFromAutomation()
                XCTFail("A cancelled startup must not report success")
            } catch {}
            returned.fulfill()
        }
        defer { gate.release(); start.cancel(); fixture.cleanUp() }
        try await waitUntil("Startup reaches uncooperative preflight") { gate.callCount == 1 }

        start.cancel()
        // The gate remains suspended throughout this deadline. Awaiting the child
        // startup directly would hang here despite cancellation of its caller.
        await fulfillment(of: [returned], timeout: 1)
        XCTAssertFalse(fixture.pipeline.isBusy)
        XCTAssertFalse(fixture.pipeline.isRecording)
        XCTAssertEqual(fixture.recorder.startCount, 0)

        gate.release()
        await start.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(fixture.pipeline.isRecording, "A late preflight response must not revive the cancelled recording")
        XCTAssertFalse(fixture.pipeline.isBusy)
        XCTAssertEqual(fixture.recorder.startCount, 0)
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)
    }

    func testMissingScriptBlocksAutomationBeforeMicrophoneStarts() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.outputScriptPath = fixture.directory.appendingPathComponent("missing-script").path
        do {
            try await fixture.pipeline.startFromAutomation()
            XCTFail("Missing script must block recording")
        } catch {}
        XCTAssertEqual(fixture.recorder.startCount, 0)
        XCTAssertFalse(fixture.pipeline.isRecording)
        XCTAssertFalse(fixture.pipeline.isBusy)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
    }

    func testSetupChangesDuringPermissionWaitBlockCapture() async throws {
        for change in ["speech", "refinement", "microphone", "profile"] {
            let gate = AutomationStartupGate()
            let fixture = try Fixture(permissionGate: gate, verbatim: change == "profile")
            let start = Task { () -> Bool in
                do { try await fixture.pipeline.startFromAutomation(); return true }
                catch { return false }
            }
            defer { gate.release(); start.cancel(); fixture.cleanUp() }
            try await waitUntil("Permission request suspends") { gate.callCount == 1 }
            switch change {
            case "speech": fixture.settings.asr.language = "zh"
            case "refinement": fixture.settings.llm.minWordsForLLM += 1
            case "profile": fixture.profiles.setActive(RefinementProfile.cleanID)
            default: fixture.settings.microphone.channelIndex = 1
            }
            gate.release()

            let succeeded = await start.value
            XCTAssertFalse(succeeded, "A changed \(change) setup must be checked again before capture")
            XCTAssertEqual(fixture.recorder.startCount, 0)
            XCTAssertFalse(fixture.pipeline.isRecording)
            XCTAssertNotNil(fixture.pipeline.lastIssue)
            XCTAssertEqual(fixture.probe.blockedRecordings, 1)
            XCTAssertTrue(fixture.probe.scripts.isEmpty)
        }
    }

    func testMicrophoneStartFailureOpensRecoveryEvenWithHiddenHUD() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.hudStyle = .none
        fixture.recorder.failOnStart = true

        do {
            try await fixture.pipeline.startFromAutomation()
            XCTFail("Recording must fail when the selected microphone disappears")
        } catch {}

        XCTAssertEqual(fixture.probe.blockedRecordings, 1)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
        XCTAssertFalse(fixture.pipeline.isRecording)
        XCTAssertFalse(fixture.pipeline.isBusy)
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)
    }

    func testPermissionRevokedDuringStartupOpensRecovery() async throws {
        let fixture = try Fixture(microphoneGranted: false)
        defer { fixture.cleanUp() }
        fixture.settings.hudStyle = .none

        do {
            try await fixture.pipeline.startFromAutomation()
            XCTFail("Revoked microphone permission must block recording")
        } catch {}

        XCTAssertEqual(fixture.recorder.startCount, 0)
        XCTAssertEqual(fixture.probe.blockedRecordings, 1)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
        XCTAssertFalse(fixture.pipeline.isBusy)
    }

    func testMicrophoneInterruptionRecoveryKeepsOriginalOutput() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()
        fixture.settings.outputDestination = .cursor
        fixture.settings.outputScriptPath = fixture.secondScript.path
        fixture.recorder.interruptionHandler?(.inputChanged)
        try await waitUntil("Interrupted audio is recoverable") {
            fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy
        }

        XCTAssertEqual(fixture.probe.blockedRecordings, 1)
        XCTAssertEqual(try fixture.history.count(), 0)
        fixture.pipeline.retryRecording()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts, [.init(text: "Final words", path: fixture.firstScript.path)])
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testVerbatimRecordingDoesNotStartConfiguredCLI() async throws {
        let fixture = try Fixture(verbatim: true)
        defer { fixture.cleanUp() }
        let fakeCLI = fixture.directory.appendingPathComponent("fake-codex")
        let marker = URL(fileURLWithPath: fakeCLI.path + ".started")
        try Data("#!/bin/sh\n/usr/bin/touch \"$0.started\"\nexit 1\n".utf8).write(to: fakeCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)
        fixture.settings.llm = LLMConfig(kind: .codex, cliPaths: ["codex": fakeCLI.path])

        try await fixture.pipeline.startFromAutomation()
        // Discovery normally starts as soon as recording begins. The local fake
        // exits immediately; no installed CLI or account is used by this test.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "Verbatim: no LLM")
    }

    func testCLIFailureDeliversRawTranscriptAndRecordsTheFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fakeCLI = fixture.directory.appendingPathComponent("failing-codex")
        try Data("#!/bin/sh\nexit 17\n".utf8).write(to: fakeCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)
        fixture.settings.llm = LLMConfig(kind: .codex, cliPaths: ["codex": fakeCLI.path], minWordsForLLM: 0)

        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertEqual(fixture.probe.scripts, [.init(text: "Final words", path: fixture.firstScript.path)])
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
        XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.llmSkippedReason, "LLM failed, using raw transcript")
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.rawTranscript, "Final words")
        XCTAssertEqual(record.finalText, "Final words")
        XCTAssertEqual(record.outputSucceeded, true)
        XCTAssertNotNil(record.error)
        XCTAssertNotNil(fixture.pipeline.lastIssue)
    }

    func testRefinementPreparationKeepsCapturedSettingsWhenSelectionChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let fakeCLI = fixture.directory.appendingPathComponent("failing-codex")
        try Data("#!/bin/sh\nexit 17\n".utf8).write(to: fakeCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)
        let captured = LLMConfig(kind: .codex, model: "captured-model",
                                 cliPaths: ["codex": fakeCLI.path], minWordsForLLM: 0)
        fixture.settings.llm = captured
        var inspected: [LLMConfig] = []
        var loaded: [LLMConfig] = []
        fixture.pipeline.llmNeedsLoad = { config in
            inspected.append(config)
            fixture.settings.llm = LLMConfig(kind: .none)
            return true
        }
        fixture.pipeline.loadLLM = { config in loaded.append(config) }

        fixture.pipeline.processSamples(Fixture.samples)
        try await finished(fixture)

        XCTAssertEqual(inspected, [captured])
        XCTAssertEqual(loaded, [captured], "Preparation and refinement must use the same settings snapshot")
        XCTAssertEqual(fixture.settings.llm.kind, .none)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")
        XCTAssertEqual(fixture.probe.scripts.count, 1)
    }

    func testRepeatedAutomationStopDeliversOnlyOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.pipeline.startFromAutomation()
        try await fixture.pipeline.startFromAutomation()
        XCTAssertEqual(fixture.recorder.startCount, 1)
        for _ in 0..<5 { try fixture.pipeline.stopFromAutomation() }
        try await finished(fixture)
        try fixture.pipeline.stopFromAutomation()

        XCTAssertEqual(fixture.probe.scripts.count, 1)
        XCTAssertEqual(try fixture.history.count(), 1)
        XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")
    }

    func testMaximumRecordingTimerStopsAndDeliversOnlyOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.maxRecordingSeconds = 10
        let started = Date()
        try await fixture.pipeline.startFromAutomation()
        try await waitUntil("Maximum recording time delivers the transcript", timeout: 13) {
            fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 9.5)
        XCTAssertFalse(fixture.recorder.isRecording)
        XCTAssertNil(fixture.pipeline.recordingStartedAt)
        try fixture.pipeline.stopFromAutomation()
        try await Task.sleep(for: .milliseconds(450))

        XCTAssertEqual(fixture.recorder.stopCount, 1)
        XCTAssertEqual(fixture.probe.scripts.count, 1)
        XCTAssertEqual(try fixture.history.count(), 1)
    }

    func testCancelledMaximumTimerCannotStopReplacementRecording() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.maxRecordingSeconds = 10
        try await fixture.pipeline.startFromAutomation()
        try await Task.sleep(for: .milliseconds(50))
        try fixture.pipeline.cancelFromAutomation()
        fixture.settings.maxRecordingSeconds = 30
        try await fixture.pipeline.startFromAutomation()
        // Pass the cancelled session's original deadline with a new session active.
        try await Task.sleep(for: .milliseconds(10_250))

        XCTAssertTrue(fixture.pipeline.isRecording)
        XCTAssertTrue(fixture.recorder.isRecording)
        XCTAssertEqual(fixture.recorder.stopCount, 0)
        XCTAssertTrue(fixture.probe.scripts.isEmpty)
        XCTAssertEqual(try fixture.history.count(), 0)
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)
        XCTAssertEqual(fixture.recorder.stopCount, 1)
        XCTAssertEqual(fixture.probe.scripts.count, 1)
    }

    func testPipelineExecutesScriptOnceAndStoresMatchingAudioAndText() async throws {
        let text = "繁體中文🙂\n'quoted' \"double\" $HOME; $(touch injected) `touch injected`\nlast line"
        let fixture = try Fixture(speech: AutomationSpeech([.text(text)]), executeScript: true)
        defer { fixture.cleanUp() }
        fixture.settings.audioRetention = .week
        try Data("#!/bin/sh\n/bin/cat > received.txt\nprintf 'attempt\\n' >> attempts.txt\n".utf8).write(to: fixture.firstScript)
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await finished(fixture)

        XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent("received.txt")), Data(text.utf8))
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("attempts.txt"), encoding: .utf8), "attempt\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("injected").path))
        let record = try XCTUnwrap(fixture.history.recent().first)
        XCTAssertEqual(record.finalText, text)
        XCTAssertEqual(record.outputSucceeded, true)
        XCTAssertFalse(record.inserted)
        XCTAssertEqual(try fixture.history.audioSamples(for: record).count, Fixture.samples.count)
        XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
    }

    private func finished(_ fixture: Fixture) async throws {
        try await waitUntil("Dictation delivery and history finish") { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy }
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 3,
                           file: StaticString = #filePath, line: UInt = #line,
                           condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(description + " timed out", file: file, line: line)
        throw AutomationTestError.timedOut
    }

    @MainActor
    private struct Fixture {
        static let samples = [Float](repeating: 0.125, count: 16_000)
        let suite: String
        let directory: URL
        let firstScript: URL
        let secondScript: URL
        let settings: AppSettings
        let history: HistoryStore
        let dictionary: DictionaryStore
        let profiles: ProfileStore
        let recorder: AutomationTestRecorder
        let pipeline: DictationPipeline
        let probe: AutomationDeliveryProbe

        init(speech: AutomationSpeech = AutomationSpeech([.text("Final words")]), scriptFails: Bool = false,
             startupGate: AutomationStartupGate? = nil, deliveryGate: AutomationStartupGate? = nil,
             permissionGate: AutomationStartupGate? = nil, microphoneGranted: Bool = true, executeScript: Bool = false,
             verbatim: Bool = false, accessCheck: @escaping @MainActor () async throws -> Void = {}) throws {
            suite = "airdraft.pipeline-automation.\(UUID().uuidString)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            firstScript = directory.appendingPathComponent("first.sh")
            secondScript = directory.appendingPathComponent("second.sh")
            for url in [firstScript, secondScript] {
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.asr = ASRConfig(kind: .parakeet)
            settings.llm = LLMConfig(kind: .none)
            settings.useAppContext = false
            settings.livePreviewEnabled = false
            settings.outputDestination = .script
            settings.outputScriptPath = firstScript.path
            history = try HistoryStore(directory: directory)
            dictionary = DictionaryStore(directory: directory)
            recorder = AutomationTestRecorder()
            let probe = AutomationDeliveryProbe(failing: scriptFails)
            self.probe = probe
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Automation tests must not read credentials")
                return nil
            }, transcriberBuilder: { _ in speech })
            let profiles = ProfileStore(directory: directory)
            if verbatim { profiles.setActive(RefinementProfile.verbatimID) }
            self.profiles = profiles
            pipeline = DictationPipeline(settings: settings, dictionary: dictionary,
                profiles: profiles, history: history, factory: factory, recorder: recorder,
                insertText: { text, _, _ in
                    probe.insert(text)
                    return InsertionResult(method: .accessibility, notice: nil)
                }, sendScript: { text, path in
                    if executeScript { try await ScriptDelivery.send(text: text, to: path) }
                    else { try probe.send(text, path: path) }
                    await deliveryGate?.enter()
                },
                recordingPreflight: { _, _, _, _, _ in await startupGate?.enter() },
                accessCheck: accessCheck,
                requestMicrophoneAccess: { await permissionGate?.enter(); return microphoneGranted })
            pipeline.onRecordingBlocked = { probe.blockedRecordings += 1 }
        }

        func saveOriginal() throws -> DictationRecord {
            try history.save(DictationRecord(mode: "clean", family: "document", rawTranscript: "Original words",
                refinedText: "Original words", finalText: "Original words", asrEngine: "original",
                audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: true), samples: Self.samples)
            return try XCTUnwrap(history.recent().first)
        }

        func cleanUp() {
            pipeline.cancel()
            pipeline.onOutputDelivered = nil
            do {
                try history.close()
                try FileManager.default.removeItem(at: directory)
            } catch { XCTFail("Fixture cleanup failed: \(error)") }
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }
}

private enum AutomationTestError: Error, LocalizedError {
    case timedOut, scriptFailed
    var errorDescription: String? {
        switch self {
        case .timedOut: return "Automation test timed out"
        case .scriptFailed: return "script fixture failed"
        }
    }
}

private final class AutomationDeliveryProbe: @unchecked Sendable {
    struct ScriptCall: Equatable { let text: String; let path: String }
    private let lock = NSLock()
    private let failing: Bool
    var blockedRecordings = 0
    private var calls: [ScriptCall] = []
    private var insertions: [String] = []
    var scripts: [ScriptCall] { lock.withLock { calls } }
    var insertedTexts: [String] { lock.withLock { insertions } }
    init(failing: Bool) { self.failing = failing }
    func insert(_ text: String) { lock.withLock { insertions.append(text) } }
    func send(_ text: String, path: String) throws {
        lock.withLock { calls.append(ScriptCall(text: text, path: path)) }
        if failing { throw AutomationTestError.scriptFailed }
    }
}

private final class AutomationTestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var startCount = 0
    var stopCount = 0
    var failOnStart = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws {
        startCount += 1
        if failOnStart { throw AudioRecorderError.microphoneUnavailable("Disconnected test input") }
        isRecording = true
    }
    func stop() -> [Float] { stopCount += 1; isRecording = false; return [Float](repeating: 0.125, count: 16_000) }
    func cancel() { isRecording = false }
}

private actor AutomationSpeech: Transcriber {
    enum Response: Sendable { case text(String), failure }
    nonisolated let id = "automation-test-speech"
    private let responses: [Response]
    private var index = 0
    init(_ responses: [Response]) { self.responses = responses }
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard index < responses.count else { throw AutomationTestError.timedOut }
        let response = responses[index]
        index += 1
        switch response {
        case .failure: throw TranscriberError.timedOut
        case let .text(text): return Transcript(text: text, engine: id, latencyMs: 1)
        }
    }
}

/// Deliberately ignores task cancellation to model a late permission/preflight response.
private final class AutomationStartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    var callCount: Int { lock.withLock { calls } }

    func enter() async {
        await withCheckedContinuation { pending in
            let shouldWait = lock.withLock {
                calls += 1
                guard calls == 1, !released else { return false }
                continuation = pending
                return true
            }
            if !shouldWait { pending.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume()
    }
}
