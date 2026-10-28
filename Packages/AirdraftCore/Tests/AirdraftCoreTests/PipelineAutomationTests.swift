import Foundation
import AppKit
import XCTest
@testable import AirdraftCore

@MainActor
final class PipelineAutomationTests: XCTestCase {
    /// Access is checked before manual and automation capture or audio processing; expiry
    /// neither interrupts a started recording nor makes captured audio unrecoverable.
    func testAccessIsCheckedBeforeNewWorkButNeverInterruptsStartedOrCapturedAudio() async throws {
        do { // AccessIsCheckedBeforeManualAndAutomationCaptureOrAudioProcessing
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

        do { // ExpiryCannotInterruptAnAlreadyStartedRecording
            let allowed = Locked(true)
            let fixture = try Fixture(accessCheck: { if !allowed.value { throw LicenseError.accessRequired } })
            defer { fixture.cleanUp() }
            try await fixture.pipeline.startFromAutomation()
            allowed.value = false
            try fixture.pipeline.stopFromAutomation()
            try await finished(fixture)
            XCTAssertEqual(fixture.probe.scripts.count, 1)
            XCTAssertEqual(try fixture.history.count(), 1)
        }

        do { // CapturedAudioRemainsRecoverableAfterAccessExpires
            let allowed = Locked(true)
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered words")]),
                                      accessCheck: { if !allowed.value { throw LicenseError.accessRequired } })
            defer { fixture.cleanUp() }
            try await fixture.pipeline.startFromAutomation()
            try fixture.pipeline.stopFromAutomation()
            try await waitUntil("Audio retained") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            allowed.value = false
            fixture.pipeline.retryRecording()
            try await finished(fixture)
            XCTAssertEqual(fixture.probe.scripts.count, 1)
            XCTAssertEqual(try fixture.history.count(), 1)
        }
    }

    /// Japanese kanji survive the Traditional script setting, the script receives only the
    /// final text after conversion and dictionary, and a real script runs once with literal
    /// stdin while audio and text are stored.
    func testScriptReceivesOnlyFinalConvertedTextOnceAsLiteralInput() async throws {
        // Kanji-only Japanese has no kana for the converter's guard; with Japanese
        // selected, the Traditional script setting must not rewrite it (review #1).
        do { // JapaneseSpeechKeepsKanjiUnderTraditionalScript
            let fixture = try Fixture(speech: AutomationSpeech([.text("会議室検索")]))
            defer { fixture.cleanUp() }
            fixture.settings.asr = ASRConfig(kind: .whisperKit, language: "ja", chineseScript: .traditional)

            try await fixture.pipeline.startFromAutomation()
            try fixture.pipeline.stopFromAutomation()
            try await finished(fixture)

            XCTAssertEqual(fixture.probe.scripts.map(\.text), ["会議室検索"])
            fixture.settings.asr = ASRConfig(kind: .whisperKit, language: "ja", chineseScript: .traditional)
            XCTAssertEqual(fixture.settings.asr.effectiveChineseScript, .auto)
        }

        do { // ScriptReceivesOnlyFinalTextAfterChineseConversionAndDictionary
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

        do { // PipelineExecutesScriptOnceAndStoresMatchingAudioAndText
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
    }

    /// Script and cursor destinations are snapshotted while recording, and speech or
    /// microphone-interruption recovery keeps the original output.
    func testOutputDestinationIsSnapshottedThroughRecordingAndRecovery() async throws {
        do { // ScriptDestinationAndPathAreSnapshottedWhileRecording
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

        do { // CursorDestinationDoesNotTurnIntoScriptDeliveryMidRecording
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

        do { // SpeechRecoveryKeepsOriginalScriptDestinationAndPath
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered words")]))
            defer { fixture.cleanUp() }
            try await fixture.pipeline.startFromAutomation()
            try fixture.pipeline.stopFromAutomation()
            try await waitUntil("Speech failure retains audio") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
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

        do { // MicrophoneInterruptionRecoveryKeepsOriginalOutput
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            try await fixture.pipeline.startFromAutomation()
            fixture.settings.outputDestination = .cursor
            fixture.settings.outputScriptPath = fixture.secondScript.path
            fixture.recorder.interruptionHandler?(.inputChanged)
            try await waitUntil("Interrupted audio is recoverable") {
                fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery
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
    }

    /// A failed script keeps the final text without paste or retry, review-only
    /// retranscription and recovery never run it, and disabled insertion suppresses it.
    func testFailedReviewOnlyOrDisabledOutputNeverRepeatsOrRunsScripts() async throws {
        do { // ScriptFailurePreservesFinalTextWithoutPasteOrDeliveryRetry
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

        do { // ReviewOnlyRetranscriptionAndRecoveryNeverExecuteScript
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Reviewed words")]))
            defer { fixture.cleanUp() }
            fixture.pipeline.onOutputDelivered = { XCTFail("Review-only text is not delivered") }
            let original = try fixture.saveOriginal()
            fixture.pipeline.retranscribe(original)
            try await waitUntil("Review speech failure retains audio") { fixture.pipeline.hasRecoverableRecording && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            fixture.pipeline.retryRecording()
            try await waitUntil("Review retry completes") { fixture.pipeline.reviewOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }

            XCTAssertEqual(fixture.pipeline.reviewOutcome?.final, "Reviewed words")
            XCTAssertTrue(fixture.probe.scripts.isEmpty)
            XCTAssertTrue(fixture.probe.insertedTexts.isEmpty)
            XCTAssertNil(fixture.pipeline.lastOutcome)
            XCTAssertEqual(try fixture.history.recent(), [original])
        }

        do { // InsertionDisabledAlsoSuppressesScripts
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
    }

    /// Cancel cannot interrupt a script already delivering, a cancelled startup cannot revive
    /// or cancel a newer recording, and cancelling a start returns before an uncooperative
    /// preflight finishes.
    func testAutomationCancelRacesNeverInterruptDeliveryReviveOrCancelNewerRecordings() async throws {
        do { // AutomationCancelCannotInterruptScriptAfterDeliveryStarts
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

        do { // CancelledStartupCannotReviveOrCancelNewAutomationRecording
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

        do { // CancellingAutomationStartReturnsBeforeUncooperativePreflightFinishes
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
    }

    /// A missing script, setup changed during the permission wait, a microphone start failure
    /// with a hidden HUD and revoked permission all block capture and open recovery.
    func testBlockedStartupNeverCapturesAndOpensRecovery() async throws {
        do { // MissingScriptBlocksAutomationBeforeMicrophoneStarts
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

        do { // SetupChangesDuringPermissionWaitBlockCapture
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

        do { // MicrophoneStartFailureOpensRecoveryEvenWithHiddenHUD
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

        do { // PermissionRevokedDuringStartupOpensRecovery
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
    }

    func testRefinementSkipsVerbatimFallsBackOnCLIFailureAndUsesCapturedSettings() async throws {
        do { // VerbatimRecordingDoesNotStartConfiguredCLI
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

        do { // CLIFailureDeliversRawTranscriptAndRecordsTheFailure
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

        do { // RefinementPreparationKeepsCapturedSettingsWhenSelectionChanges
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
            fixture.pipeline.prepareRefinement = { config in
                inspected.append(config)
                fixture.settings.llm = LLMConfig(kind: .none)
                loaded.append(config)
                return .unmanaged
            }

            fixture.pipeline.processSamples(Fixture.samples)
            try await finished(fixture)

            XCTAssertEqual(inspected, [captured])
            XCTAssertEqual(loaded, [captured], "Preparation and refinement must use the same settings snapshot")
            XCTAssertEqual(fixture.settings.llm.kind, .none)
            XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Final words")
            XCTAssertEqual(fixture.probe.scripts.count, 1)
        }
    }

    func testRepeatedStopsAndMaximumTimerDeliverOnceAndNeverStopAReplacement() async throws {
        do { // RepeatedAutomationStopDeliversOnlyOnce
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

        do { // MaximumRecordingTimerStopsAndDeliversOnlyOnce
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            // The injected limit stands in for the 10-second setting minimum.
            fixture.pipeline.recordingLimitSeconds = { _, _ in 1 }
            let started = Date()
            try await fixture.pipeline.startFromAutomation()
            try await waitUntil("Maximum recording time delivers the transcript", timeout: 4) {
                fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery
            }
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.9)
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertNil(fixture.pipeline.recordingStartedAt)
            try fixture.pipeline.stopFromAutomation()
            try await Task.sleep(for: .milliseconds(450))

            XCTAssertEqual(fixture.recorder.stopCount, 1)
            XCTAssertEqual(fixture.probe.scripts.count, 1)
            XCTAssertEqual(try fixture.history.count(), 1)
        }

        do { // CancelledMaximumTimerCannotStopReplacementRecording
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            fixture.pipeline.recordingLimitSeconds = { _, _ in 1 }
            try await fixture.pipeline.startFromAutomation()
            try await Task.sleep(for: .milliseconds(50))
            try fixture.pipeline.cancelFromAutomation()
            fixture.pipeline.recordingLimitSeconds = { _, _ in 30 }
            try await fixture.pipeline.startFromAutomation()
            // Pass the cancelled session's original deadline with a new session active.
            try await Task.sleep(for: .milliseconds(1_250))

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
    }

    // MARK: - Pending recordings (AD-063)

    private func recordOnce(_ fixture: Fixture) async throws {
        try await fixture.pipeline.startFromAutomation()
        try fixture.pipeline.stopFromAutomation()
        try await waitUntil("Recording processed") { !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
    }

    func testKeptRecordingsAllowNewDictationAndRetryToTheirOwnTargets() async throws {
        do { // FailedRecordingNoLongerBlocksNewDictation
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("New words"), .text("Recovered words")]))
            defer { fixture.cleanUp() }
            try await recordOnce(fixture)
            let kept = try XCTUnwrap(fixture.pipeline.latestPendingDictation)
            XCTAssertTrue(kept.issue.contains("Captured audio is kept for retry"))
            XCTAssertEqual(fixture.probe.blockedRecordings, 1, "A kept recording still opens its recovery")

            // A new dictation records and delivers with the current destination.
            fixture.settings.outputScriptPath = fixture.secondScript.path
            try await recordOnce(fixture)
            XCTAssertEqual(fixture.recorder.startCount, 2)
            XCTAssertEqual(fixture.probe.scripts, [.init(text: "New words", path: fixture.secondScript.path)])
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), [kept.id], "The earlier recording stays available")
            XCTAssertEqual(fixture.pipeline.latestPendingDictation?.issue, kept.issue, "Its own failure text survives the success")
            XCTAssertNil(fixture.pipeline.lastIssue)
            XCTAssertTrue(fixture.pipeline.hasRecoverableRecording, "Quit still warns about the kept recording")

            // Explicit retry keeps the original destination.
            fixture.pipeline.retryRecording(kept.id)
            try await waitUntil("Retry delivers") { fixture.probe.scripts.count == 2 && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertEqual(fixture.probe.scripts.last, .init(text: "Recovered words", path: fixture.firstScript.path))
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
            XCTAssertEqual(try fixture.history.count(), 2)
        }

        do { // SecondFailureKeepsBothAndOlderItemRetriesToItsOwnTarget
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .failure, .text("Older words"), .failure, .text("Newer words")]))
            defer { fixture.cleanUp() }
            try await recordOnce(fixture)
            fixture.settings.outputScriptPath = fixture.secondScript.path
            try await recordOnce(fixture)
            let pending = fixture.pipeline.pendingRecordings
            XCTAssertEqual(pending.count, 2)
            XCTAssertEqual(fixture.pipeline.latestPendingDictation?.id, pending[1].id)
            XCTAssertEqual(fixture.probe.blockedRecordings, 2)

            fixture.pipeline.retryRecording(pending[0].id)
            try await waitUntil("Older retry delivers") { fixture.probe.scripts.count == 1 && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertEqual(fixture.probe.scripts, [.init(text: "Older words", path: fixture.firstScript.path)])
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), [pending[1].id])

            // A failed retry keeps the same audio entry and its target.
            fixture.pipeline.retryRecording(pending[1].id)
            try await waitUntil("Failed retry keeps audio") { !fixture.pipeline.isBusy && fixture.pipeline.lastIssue != nil }
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), [pending[1].id])
            fixture.settings.outputScriptPath = fixture.firstScript.path
            fixture.pipeline.retryRecording()
            try await waitUntil("Newer retry delivers") { fixture.probe.scripts.count == 2 && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertEqual(fixture.probe.scripts.last, .init(text: "Newer words", path: fixture.secondScript.path))
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        }
    }

    func testFullQueueAndCancellationNeverDropKeptAudio() async throws {
        do { // FullRecoveryQueueBlocksNewRecordingInsteadOfDroppingAudio
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .failure, .failure, .text("After discard")]))
            defer { fixture.cleanUp() }
            for _ in 0..<DictationPipeline.maximumPendingRecordings { try await recordOnce(fixture) }
            let kept = fixture.pipeline.pendingRecordings
            XCTAssertEqual(kept.count, DictationPipeline.maximumPendingRecordings)
            XCTAssertFalse(fixture.pipeline.canKeepAnotherRecording)
            let blocked = fixture.probe.blockedRecordings

            fixture.pipeline.startRecording()
            XCTAssertEqual(fixture.recorder.startCount, DictationPipeline.maximumPendingRecordings, "No capture starts")
            XCTAssertEqual(fixture.probe.blockedRecordings, blocked + 1, "Home opens with the kept recordings")
            XCTAssertNotNil(fixture.pipeline.lastIssue)
            do { try await fixture.pipeline.startFromAutomation(); XCTFail("Automation must not exceed the bound") } catch {}
            XCTAssertEqual(fixture.pipeline.pendingRecordings, kept, "No kept audio is dropped")

            fixture.pipeline.discardRecording(kept[0].id)
            XCTAssertTrue(fixture.pipeline.canKeepAnotherRecording)
            try await recordOnce(fixture)
            XCTAssertEqual(fixture.probe.scripts.map(\.text), ["After discard"])
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), Array(kept.dropFirst()).map(\.id))
        }

        do { // CancellingANewRecordingOrRetryKeepsEarlierAudio
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered words")]))
            defer { fixture.cleanUp() }
            try await recordOnce(fixture)
            let kept = try XCTUnwrap(fixture.pipeline.latestPendingDictation)
            try await fixture.pipeline.startFromAutomation()
            try fixture.pipeline.cancelFromAutomation()
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), [kept.id])
            fixture.pipeline.retryRecording(kept.id)
            fixture.pipeline.cancel()
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), [kept.id], "Only an explicit discard removes audio")
            fixture.pipeline.discardRecording(kept.id)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        }
    }

    func testDataCleanupCoversEveryKeptRecordingAndReviewRecoveryStaysSeparate() async throws {
        do { // DataCleanupAppliesToEveryKeptRecording
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .failure, .text("Review words"), .text("Review words")]))
            defer { fixture.cleanUp() }
            try await recordOnce(fixture)
            try await recordOnce(fixture)
            try fixture.pipeline.beginDataMaintenance()
            try await fixture.pipeline.prepareDataRemoval(.history)
            fixture.pipeline.endDataMaintenance()
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 2, "History cleanup keeps audio for review")
            let first = fixture.pipeline.pendingRecordings[0].id
            fixture.pipeline.retryRecording(first)
            try await waitUntil("Review-only retry finishes") { fixture.pipeline.reviewOutcome != nil && !fixture.pipeline.isBusy }
            XCTAssertTrue(fixture.probe.scripts.isEmpty, "Cleaned recordings never deliver to their old destination")
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 1)

            try fixture.pipeline.beginDataMaintenance()
            try await fixture.pipeline.prepareDataRemoval(.audio)
            fixture.pipeline.endDataMaintenance()
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        }

        do { // ReviewRecoveryIsSeparateFromDictationRecoveries
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .failure]))
            defer { fixture.cleanUp() }
            try await recordOnce(fixture)
            let original = try fixture.saveOriginal()
            fixture.pipeline.retranscribe(original)
            try await waitUntil("Review failure kept") { fixture.pipeline.pendingRecordings.count == 2 && !fixture.pipeline.isBusy }
            XCTAssertEqual(fixture.pipeline.pendingRecordings.filter(\.isReview).count, 1)
            XCTAssertFalse(fixture.pipeline.latestPendingDictation?.isReview ?? true)
            fixture.pipeline.dismissReview()
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 1)
            XCTAssertFalse(fixture.pipeline.pendingRecordings[0].isReview)
        }
    }

    func testKeptAudioBoundShortensNextRecordingAndRefusesWithoutRoom() async throws {
        // AD-063 review, revised: the kept-audio bound stays hard, but a long
        // recording limit no longer blocks dictation. A new recording may capture
        // the budget that remains (900 s minus kept audio), so its own failure can
        // still be kept; recording is refused only when less than 10 s remain.
        do { // KeptAudioBoundShortensTheNextRecordingInsteadOfBlockingIt
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Fits")]))
            defer { fixture.cleanUp() }
            fixture.recorder.sampleCount = 400 * 16_000
            try await recordOnce(fixture)
            XCTAssertEqual(fixture.pipeline.pendingRecordings.first?.seconds, 400)
            fixture.recorder.sampleCount = 16_000
            fixture.settings.maxRecordingSeconds = 600
            XCTAssertTrue(fixture.pipeline.canKeepAnotherRecording, "One long kept recording no longer blocks dictation")
            XCTAssertEqual(fixture.pipeline.availableRecordingSeconds, 500, "400 s kept leaves 500 s of a 600 s limit")
            XCTAssertTrue(fixture.pipeline.keptAudioShortensNextRecording)
            fixture.settings.maxRecordingSeconds = 300
            XCTAssertEqual(fixture.pipeline.availableRecordingSeconds, 300)
            XCTAssertFalse(fixture.pipeline.keptAudioShortensNextRecording)
            try await recordOnce(fixture)
            XCTAssertEqual(fixture.probe.scripts.map(\.text), ["Fits"])
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 1, "No kept audio is dropped")
        }

        // Recording is refused, visibly and before capture, once less than the
        // shortest recording limit (10 s) remains within the bound.
        do { // KeptAudioBoundRefusesRecordingWithoutRoomLeft
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .failure]))
            defer { fixture.cleanUp() }
            fixture.recorder.sampleCount = 600 * 16_000
            try await recordOnce(fixture)
            fixture.recorder.sampleCount = 295 * 16_000
            try await recordOnce(fixture)
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.seconds), [600, 295])
            XCTAssertEqual(fixture.pipeline.availableRecordingSeconds, 5)
            XCTAssertFalse(fixture.pipeline.canKeepAnotherRecording)
            let starts = fixture.recorder.startCount
            fixture.pipeline.startRecording()
            XCTAssertEqual(fixture.recorder.startCount, starts, "No capture starts past the bound")
            guard case .failed = fixture.pipeline.state else { return XCTFail("The refusal must be visible") }
            do { try await fixture.pipeline.startFromAutomation(); XCTFail("Automation must not exceed the bound") } catch {}
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 2, "No kept audio is dropped")
            fixture.pipeline.discardRecording(fixture.pipeline.pendingRecordings[1].id)
            XCTAssertTrue(fixture.pipeline.canKeepAnotherRecording)
        }
    }

    func testBudgetStopExplainsItselfOnSuccessAndSpeechFailure() async throws {
        // A recording shortened by kept audio stops at the remaining budget, is
        // processed normally and says why it stopped.
        do { // RecordingStopsAtRemainingBudgetWithANotice
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Budget words")]))
            defer { fixture.cleanUp() }
            fixture.recorder.sampleCount = 400 * 16_000
            try await recordOnce(fixture)
            fixture.recorder.sampleCount = 16_000
            // Leave half a second of budget so the auto-stop fires quickly.
            fixture.pipeline.keptAudioBudgetSeconds = 400.5
            fixture.pipeline.minimumRecordingWithinBudget = 0.1
            XCTAssertEqual(fixture.pipeline.availableRecordingSeconds, 0.5, accuracy: 0.001)
            try await fixture.pipeline.startFromAutomation()
            try await waitUntil("The budget stops capture") { !fixture.pipeline.isRecording }
            try await waitUntil("Recording processed") { !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertEqual(fixture.probe.scripts.map(\.text), ["Budget words"])
            if case .notice(let message, let attention) = fixture.pipeline.state {
                XCTAssertTrue(message.hasPrefix("Recording stopped at 0:01"), message)
                XCTAssertTrue(attention)
            } else {
                XCTFail("The early stop must be explained")
            }
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 1)
        }

        // AD-077: a budget-shortened recording whose speech recognition fails keeps
        // the reason it stopped early in the failure and in its recovery issue.
        do { // BudgetStopReasonSurvivesASpeechFailure
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .failure]))
            defer { fixture.cleanUp() }
            fixture.recorder.sampleCount = 400 * 16_000
            try await recordOnce(fixture)
            fixture.recorder.sampleCount = 16_000
            fixture.pipeline.keptAudioBudgetSeconds = 400.5
            fixture.pipeline.minimumRecordingWithinBudget = 0.1
            try await fixture.pipeline.startFromAutomation()
            try await waitUntil("The budget stops capture") { !fixture.pipeline.isRecording }
            try await waitUntil("Recording processed") { !fixture.pipeline.isBusy }
            guard case .failed(let message) = fixture.pipeline.state else {
                return XCTFail("The speech failure must be visible")
            }
            XCTAssertTrue(message.hasPrefix("Transcription failed:"), message)
            XCTAssertTrue(message.contains("Recording stopped at 0:01"), "The early stop must be explained: \(message)")
            XCTAssertEqual(fixture.pipeline.pendingRecordings.count, 2)
            XCTAssertTrue(try XCTUnwrap(fixture.pipeline.pendingRecordings.last).issue.contains("Recording stopped at 0:01"))
            XCTAssertNil(fixture.pipeline.keptBudgetStop, "The reason is reported once")
            XCTAssertTrue(fixture.probe.scripts.isEmpty)
        }
    }

    func testRetryKeepsRecordingWhenCancelledInRefinementAndOnlyCopiesDuringPractice() async throws {
        // AD-063 review: a retry resolves its kept recording only once the result
        // is delivered and held for History. Cancelling during refinement keeps it.
        do { // CancellingRetryDuringRefinementKeepsTheRecording
            let refiner = GatedRefiner()
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered three words"), .text("Recovered three words")]),
                                      refiner: refiner)
            defer { fixture.cleanUp() }
            fixture.settings.llm = LLMConfig(kind: .openAICompatible)
            try await recordOnce(fixture)
            let kept = try XCTUnwrap(fixture.pipeline.latestPendingDictation)
            fixture.pipeline.retryRecording(kept.id)
            try await waitUntil("Retry reaches refinement") { fixture.pipeline.state == .refining && refiner.started }
            fixture.pipeline.cancel()
            try await waitUntil("Cancelled retry settles") { !fixture.pipeline.isBusy }
            XCTAssertEqual(fixture.pipeline.pendingRecordings.map(\.id), [kept.id], "Audio survives a cancelled retry after ASR")
            XCTAssertTrue(fixture.probe.scripts.isEmpty)
            XCTAssertEqual(try fixture.history.count(), 0)

            refiner.release = true
            fixture.pipeline.retryRecording(kept.id)
            try await waitUntil("Second retry delivers") { fixture.probe.scripts.count == 1 && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording, "A delivered retry resolves the recording")
            XCTAssertEqual(try fixture.history.count(), 1)
        }

        // Practice never runs a saved script: a retry while it runs copies only,
        // even when the kept recording's own destination was a script.
        do { // RetryDuringPracticeNeverRunsTheSavedScript
            let fixture = try Fixture(speech: AutomationSpeech([.failure, .text("Recovered words")]))
            defer { fixture.cleanUp() }
            try await recordOnce(fixture)
            let kept = try XCTUnwrap(fixture.pipeline.latestPendingDictation)
            fixture.settings.beginOnboardingPractice()
            defer { fixture.settings.endOnboardingPractice() }
            fixture.pipeline.retryRecording(kept.id)
            try await waitUntil("Practice retry finishes") { !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery && (try? fixture.history.count()) == 1 }
            XCTAssertTrue(fixture.probe.scripts.isEmpty, "The kept recording's script never runs during practice")
            XCTAssertTrue(fixture.probe.insertedTexts.isEmpty, "Nothing is pasted")
            XCTAssertEqual(fixture.clipboard.string(forType: .string), "Recovered words")
            XCTAssertEqual(fixture.pipeline.state, .notice("Dictation copied", requiresAttention: false))
            let record = try XCTUnwrap(fixture.history.recent().first)
            XCTAssertEqual(record.outputSucceeded, false)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        }
    }

    // MARK: - Session pins (AD-063)

    func testSessionPinKeepsSpeechModelUntilRecordingEndsOrIsCancelled() async throws {
        do { // LongRecordingKeepsItsSpeechModelPastTheIdleTimeout
            let clock = TestClock()
            let engine = PinnedSpeech()
            let fixture = try Fixture(engine: engine, clock: clock)
            defer { fixture.cleanUp() }
            await fixture.factory.setIdleUnloadMinutes(5)
            defer { Task { await fixture.factory.setIdleUnloadMinutes(0) } }

            try await fixture.pipeline.startFromAutomation()
            clock.advance(9 * 60)  // longer than the 5-minute idle setting
            await fixture.factory.unloadIdle()
            var counts = await engine.counts
            XCTAssertEqual(counts.unloads, 0, "The recording's model stays resident")
            try fixture.pipeline.stopFromAutomation()
            try await finished(fixture)
            counts = await engine.counts
            XCTAssertEqual(counts.prepares, 1, "Stop must not reload the model")
            XCTAssertEqual(fixture.probe.scripts.map(\.text), ["Pinned words"])

            // The pin ends with the session; the idle countdown then applies again.
            try await Task.sleep(for: .milliseconds(50))
            clock.advance(6 * 60)
            await fixture.factory.unloadIdle()
            counts = await engine.counts
            XCTAssertEqual(counts.unloads, 1)
        }

        do { // CancelledRecordingReleasesItsSpeechModelPin
            let clock = TestClock()
            let engine = PinnedSpeech()
            let fixture = try Fixture(engine: engine, clock: clock)
            defer { fixture.cleanUp() }
            await fixture.factory.setIdleUnloadMinutes(5)
            defer { Task { await fixture.factory.setIdleUnloadMinutes(0) } }
            try await fixture.pipeline.startFromAutomation()
            fixture.pipeline.cancel()
            try await Task.sleep(for: .milliseconds(50))
            clock.advance(6 * 60)
            await fixture.factory.unloadIdle()
            let counts = await engine.counts
            XCTAssertEqual(counts.unloads, 1)
        }
    }

    private func finished(_ fixture: Fixture) async throws {
        try await waitUntil("Dictation delivery and history finish") { fixture.pipeline.lastOutcome != nil && !fixture.pipeline.isBusy && !fixture.pipeline.isFinishingDelivery }
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
        let factory: EngineFactory
        /// Disposable: copy-only delivery never touches the user's clipboard.
        let clipboard = NSPasteboard.withUniqueName()

        init(speech: AutomationSpeech = AutomationSpeech([.text("Final words")]), engine: (any Transcriber)? = nil,
             refiner: (any Refiner)? = nil,
             clock: TestClock? = nil, scriptFails: Bool = false,
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
            let transcriber: any Transcriber = engine ?? speech
            var refinerBuilder: (@Sendable (LLMConfig) -> (any Refiner)?)?
            if let refiner { refinerBuilder = { _ in refiner } }
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Automation tests must not read credentials")
                return nil
            }, transcriberBuilder: { _ in transcriber }, refinerBuilder: refinerBuilder,
               now: { clock?.now ?? Date() })
            self.factory = factory
            let profiles = ProfileStore(directory: directory)
            if verbatim { profiles.setActive(RefinementProfile.verbatimID) }
            self.profiles = profiles
            pipeline = DictationPipeline(settings: settings, dictionary: dictionary,
                profiles: profiles, history: history, factory: factory, recorder: recorder,
                inserter: TextInserter(pasteboard: clipboard),
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
            clipboard.releaseGlobally()
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

private final class AutomationDeliveryProbe: Sendable {
    struct ScriptCall: Equatable, Sendable { let text: String; let path: String }
    private let failing: Bool
    private let blocked = Locked(0)
    private let calls = Locked<[ScriptCall]>([])
    private let insertions = Locked<[String]>([])
    var blockedRecordings: Int {
        get { blocked.value }
        set { blocked.value = newValue }
    }
    var scripts: [ScriptCall] { calls.value }
    var insertedTexts: [String] { insertions.value }
    init(failing: Bool) { self.failing = failing }
    func insert(_ text: String) { insertions.withLock { $0.append(text) } }
    func send(_ text: String, path: String) throws {
        calls.withLock { $0.append(ScriptCall(text: text, path: path)) }
        if failing { throw AutomationTestError.scriptFailed }
    }
}

/// Unchecked: test double driven only by the MainActor pipeline under test;
/// it never touches its fields or handlers from another thread.
private final class AutomationTestRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var startCount = 0
    var stopCount = 0
    var failOnStart = false
    var sampleCount = 16_000
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws {
        startCount += 1
        if failOnStart { throw AudioRecorderError.microphoneUnavailable("Disconnected test input") }
        isRecording = true
    }
    func stop() -> [Float] { stopCount += 1; isRecording = false; return [Float](repeating: 0.125, count: sampleCount) }
    func cancel() { isRecording = false }
}

/// Holds refinement until released; cancellation ends the wait.
private final class GatedRefiner: Refiner, Sendable {
    let id = "automation-gated-refiner"
    private let _started = Locked(false)
    private let _release = Locked(false)
    var started: Bool { _started.value }
    var release: Bool {
        get { _release.value }
        set { _release.value = newValue }
    }
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        _started.value = true
        while !release {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
        return RefineResult(text: request.transcript, engine: id, latencyMs: 0, promptVersion: "fixture")
    }
}

private actor PinnedSpeech: Transcriber {
    nonisolated let id = "automation-pinned-speech"
    private var ready = false
    private var prepares = 0
    private var unloads = 0
    var counts: (prepares: Int, unloads: Int) { (prepares, unloads) }
    func isReady() -> Bool { ready }
    func prepare() async throws { ready = true; prepares += 1 }
    func unload() async { ready = false; unloads += 1 }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        Transcript(text: "Pinned words", engine: id, latencyMs: 1)
    }
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
private final class AutomationStartupGate: Sendable {
    private struct State: Sendable {
        var calls = 0
        var released = false
        var continuation: CheckedContinuation<Void, Never>?
    }
    private let state = Locked(State())
    var callCount: Int { state.value.calls }

    func enter() async {
        await withCheckedContinuation { pending in
            let shouldWait = state.withLock { state in
                state.calls += 1
                guard state.calls == 1, !state.released else { return false }
                state.continuation = pending
                return true
            }
            if !shouldWait { pending.resume() }
        }
    }

    func release() {
        let pending = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released = true
            let pending = state.continuation
            state.continuation = nil
            return pending
        }
        pending?.resume()
    }
}
