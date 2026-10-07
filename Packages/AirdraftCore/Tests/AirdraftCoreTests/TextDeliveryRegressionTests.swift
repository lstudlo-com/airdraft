import AppKit
import ApplicationServices
import XCTest
@testable import AirdraftCore

/// These tests call the production capture and insert entry points. Only OS
/// reads and the posted key event are replaced by a disposable editor.
@MainActor
final class TextDeliveryRegressionTests: XCTestCase {
    func testIgnoredPasteKeepsRecoveryTextAndDoesNotReportDelivery() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.dropPaste = true
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        var delivered = 0
        let result = await inserter.insert(Editor.dictation, target: target) { delivered += 1 }
        XCTAssertFalse(result.didInsert, "Posting a key event is not proof that the editor received text")
        XCTAssertNotNil(result.notice)
        XCTAssertTrue(result.noticeRequiresAttention)
        XCTAssertEqual(delivered, 0, "Unconfirmed delivery must not dismiss the HUD")
        XCTAssertEqual(editor.posts, 1, "Never retry an uncertain paste")
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testDelayedPasteReportsDeliveryOnlyAfterExpectedTextArrives() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.pasteDelay = .milliseconds(100)
        let inserter = editor.inserter()
        inserter.confirmationTimeout = .milliseconds(300)
        let target = await inserter.captureTarget()
        var delivered = 0
        let result = await inserter.insert(Editor.dictation, target: target) {
            delivered += 1
            XCTAssertEqual(editor.value, Editor.dictation)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        }
        XCTAssertTrue(result.didInsert)
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(editor.posts, 1)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
    }

    func testPartialPasteOrCaretMovementCannotConfirmDelivery() async throws {
        for changedText in ["Dictated text", "something else", "cat"] {
            let editor = Editor()
            defer { editor.close() }
            editor.replacement = changedText
            let inserter = editor.inserter()
            let target = await inserter.captureTarget()
            let result = await inserter.insert(Editor.dictation, target: target) {
                XCTFail("A changed value/caret alone must not report success")
            }
            XCTAssertFalse(result.didInsert)
            XCTAssertNotNil(result.notice)
            XCTAssertEqual(editor.posts, 1)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        }
    }

    func testSlowReceiverCanReadClipboardAfterConfirmationDeadline() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.pasteDelay = .milliseconds(200)
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertNotNil(result.notice)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        for _ in 0..<100 where editor.pasted.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(editor.value, Editor.dictation)
        XCTAssertEqual(editor.posts, 1)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testUnobservablePasteKeepsRecoveryTextEvenWhenItWasPosted() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.unreadableValue = true
        editor.unreadableTextRange = true
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertNotNil(result.notice)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testConfirmedPasteReplacesUTF16SelectionAndPreservesSurroundingText() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.value = "前🙂cat後"
        editor.range = CFRange(location: 3, length: 3)
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertTrue(result.didInsert)
        XCTAssertEqual(editor.value, "前🙂" + Editor.dictation + "後")
        XCTAssertEqual(editor.posts, 1)
    }

    func testAlwaysPasteCapturesAndDeliversToNativeEditor() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        var delivered = 0
        let result = await inserter.insert(Editor.dictation, method: .paste, target: target) { delivered += 1 }
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
    }

    func testEveryPersistedMethodPastesExactlyOnceWithoutAXTextWrites() async throws {
        for method in InsertionMethod.allCases {
            let editor = Editor()
            defer { editor.close() }
            let inserter = editor.inserter()
            let captured = await inserter.captureTarget()
            let target = try XCTUnwrap(captured)
            var delivered = 0
            let result = await inserter.insert(Editor.dictation, method: method, target: target) { delivered += 1 }
            XCTAssertEqual(result.method, .paste)
            XCTAssertNil(result.notice)
            XCTAssertEqual(editor.pasted, [Editor.dictation])
            XCTAssertEqual(delivered, 1)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
        }
    }

    func testDefaultMethodDoesNotRequireAXValueOrWritableSelectedText() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.unreadableValue = true
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testAlternateSelectionRangeStillDelivers() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.alternateRangeOnly = true
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let result = await inserter.insert(Editor.dictation, method: .paste, target: target)
        XCTAssertTrue(result.didInsert)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testWebEditorCaptureWaitsForItsFieldThenDelivers() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.focusAvailable = false
        editor.canEnableWebAccessibility = true
        editor.onFocusRead = {
            if editor.webEnabled && editor.focusReads >= 3 { editor.focusAvailable = true }
        }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let result = await inserter.insert(Editor.dictation, method: .paste, target: target)
        XCTAssertTrue(editor.webEnabled)
        XCTAssertTrue(result.didInsert)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testApplicationWindowFallsBackToSystemEditorFocus() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.applicationReportsWindow = true
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let result = await inserter.insert(Editor.dictation, method: .paste, target: target)
        XCTAssertTrue(result.didInsert)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testNativeEditorCaptureWaitsWhenWebAccessibilityIsUnsupported() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.focusAvailable = false
        editor.onFocusRead = { if editor.focusReads >= 3 { editor.focusAvailable = true } }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(editor.webEnabled)
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testFrontmostEditorWaitsForTemporarilyUnavailableAXFocus() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.focusAvailable = false
        editor.focusReads = 0
        editor.onFocusRead = { if editor.focusReads >= 3 { editor.focusAvailable = true } }
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.activations, 0)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testAppActivationWaitsForOriginalFieldBeforePaste() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        editor.frontmostPID = 999
        editor.focusAvailable = false
        editor.focusReads = 0
        editor.onFocusRead = { if editor.activations > 0 && editor.focusReads >= 3 { editor.focusAvailable = true } }
        let result = await inserter.insert(Editor.dictation, method: .paste, target: target)
        XCTAssertTrue(result.didInsert)
        XCTAssertEqual(editor.activations, 1)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testCaptureFollowsAppSwitchBeforeRecordingStarts() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.frontmostPID = 999
        editor.onFocusRead = { editor.frontmostPID = 101 }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        XCTAssertEqual(target?.processID, 101)
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertEqual(editor.activations, 0)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testCaptureUsesSystemEditorWhenApplicationFocusIsStaleAfterSwitch() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.systemField = editor.otherField
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.currentField = editor.otherField // The app's cached focus finally catches up.
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testRestorationUsesSystemEditorWhileApplicationFocusIsStale() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.frontmostPID = 999
        editor.systemField = editor.field
        editor.currentField = editor.otherField
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.activations, 1)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testTransientFocusLossAtFinalValidationRetriesBeforePostingPaste() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.focusReads = 0
        editor.onFocusRead = { editor.focusAvailable = editor.focusReads != 2 }
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertNil(result.notice)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testCaptureWaitsForInitiallyValidButUnsettledEditor() async throws {
        let editor = Editor()
        defer { editor.close() }
        let switchTask = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(20))
            editor.currentField = editor.otherField
        }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        try await switchTask.value
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testSlowAppActivationKeepsOriginalDestinationAndPastesOnce() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.frontmostPID = 999
        editor.activationDelay = .milliseconds(650)
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertEqual(editor.activations, 1)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testForeignSystemFocusCannotUseCachedApplicationEditor() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.systemField = editor.foreignField
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testChangedFieldOrSelectionPreservesRecoveryTextWithoutPasting() async throws {
        for changeField in [false, true] {
            let editor = Editor()
            defer { editor.close() }
            let inserter = editor.inserter()
            let captured = await inserter.captureTarget()
            let target = try XCTUnwrap(captured)
            if changeField { editor.currentField = editor.otherField }
            else { editor.range = CFRange(location: 1, length: 0) }
            let result = await inserter.insert(Editor.dictation, target: target)
            XCTAssertFalse(result.didInsert)
            XCTAssertTrue(editor.pasted.isEmpty)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        }
    }

    func testForeignSystemFocusCannotAuthorizeCaretlessPaste() async throws {
        for foreignAtCapture in [false, true] {
            let editor = Editor()
            defer { editor.close() }
            editor.range = nil
            if foreignAtCapture { editor.applicationReportsWindow = true; editor.systemOwnerPID = 999 }
            let inserter = editor.inserter()
            let target = await inserter.captureTarget()
            if !foreignAtCapture { editor.systemField = editor.foreignField }
            let result = await inserter.insert(Editor.dictation, method: .paste, target: target)
            XCTAssertFalse(result.didInsert)
            XCTAssertTrue(editor.pasted.isEmpty)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        }
    }

    /// Zed, Warp and other editors that draw their own text publish no caret:
    /// no focused element, a container without selection attributes, or a
    /// text role without a readable range. Each must still receive one paste.
    func testCaretlessEditorPastesIntoItsFocusedWindow() async throws {
        for shape in ["no focused element", "container", "text without range"] {
            let editor = Editor()
            defer { editor.close() }
            switch shape {
            case "no focused element": editor.focusAvailable = false
            case "container": editor.applicationReportsWindow = true; editor.systemField = editor.window
            default: editor.range = nil
            }
            let inserter = editor.inserter()
            let started = ContinuousClock.now
            let captured = await inserter.captureTarget()
            let target = try XCTUnwrap(captured, shape)
            XCTAssertLessThan(started.duration(to: .now), .milliseconds(1000),
                              "\(shape): a caretless editor must not hold recording for the full capture deadline")
            XCTAssertFalse(editor.webEnabled, shape)
            XCTAssertNil(target.selection, shape)
            var delivered = 0
            let result = await inserter.insert(Editor.dictation, target: target) { delivered += 1 }
            XCTAssertFalse(result.didInsert, shape)
            XCTAssertNotNil(result.notice, shape)
            XCTAssertEqual(editor.activations, 0, shape)
            XCTAssertEqual(editor.pasted, [Editor.dictation], shape)
            XCTAssertEqual(delivered, 0, shape)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation, shape)
        }
    }

    func testCaretlessEditorIsReactivatedBeforePaste() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.focusAvailable = false
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.frontmostPID = 999
        editor.activationDelay = .milliseconds(100)
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertNotNil(result.notice)
        XCTAssertEqual(editor.activations, 1)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testCaretlessEditorRefusesAnotherWindow() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.focusAvailable = false
        let inserter = editor.inserter()
        let target = await inserter.captureTarget()
        editor.focusedWindow = editor.otherWindow
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertEqual(result.notice, "Destination changed. Text copied; paste it where you want.")
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testWebEditorStillWaitsForItsCaretAfterCaretlessSettleTime() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.focusAvailable = false
        editor.canEnableWebAccessibility = true
        let started = ContinuousClock.now
        editor.onFocusRead = {
            if editor.webEnabled, started.duration(to: .now) >= .milliseconds(400) { editor.focusAvailable = true }
        }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        XCTAssertNotNil(target.selection, "Electron editors publish their caret after the caretless settle time")
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertEqual(result.method, .paste)
        XCTAssertEqual(editor.pasted, [Editor.dictation])
    }

    func testCancelledInsertionNeverChangesClipboardOrDestination() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let task = Task { @MainActor in await inserter.insert(Editor.dictation, target: target) }
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.didInsert)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
    }

    func testCancellationWhileRestoringFocusNeverCopiesOrPastes() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        editor.frontmostPID = 999
        editor.focusAvailable = false
        let waiting = expectation(description: "Waiting for restored focus")
        var first = true
        editor.onFocusRead = { if first { first = false; waiting.fulfill() } }
        let task = Task { @MainActor in await inserter.insert(Editor.dictation, target: target) }
        await fulfillment(of: [waiting], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.didInsert)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
    }

    func testPermissionLossDoesNotDeliverText() async throws {
        let editor = Editor()
        defer { editor.close() }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        editor.trusted = false
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testPipelineWithContextOffCapturesPastesAndSavesDeliveredHistory() async throws {
        try await verifyPipelineDelivery()
    }

    func testCopyWithinAirdraftProducesTemporaryNoticeAndUndeliveredHistory() async throws {
        try await verifyPipelineDelivery(copyWithinApp: true)
    }

    func testPermissionRecoveryCopyKeepsAttentionNoticeAndUndeliveredHistory() async throws {
        try await verifyPipelineDelivery(permissionLost: true)
    }

    func testCopyWithinAirdraftAfterRefinementFailureStillProducesTemporaryNotice() async throws {
        try await verifyPipelineDelivery(copyWithinApp: true, refinementFails: true)
    }

    func testIgnoredPasteThroughPipelineKeepsNoticeClipboardAndUndeliveredHistory() async throws {
        try await verifyPipelineDelivery(dropPaste: true)
    }

    func testIgnoredPasteAfterRefinementKeepsFinalTextAndRecoveryNotice() async throws {
        try await verifyPipelineDelivery(dropPaste: true, refinementEnabled: true)
    }

    func testCaretlessIgnoredPasteAfterRefinementKeepsRecovery() async throws {
        try await verifyPipelineDelivery(dropPaste: true, refinementEnabled: true, caretless: true)
    }

    private func verifyPipelineDelivery(copyWithinApp: Bool = false, permissionLost: Bool = false,
                                        refinementFails: Bool = false, dropPaste: Bool = false,
                                        refinementEnabled: Bool = false, caretless: Bool = false) async throws {
        let editor = Editor()
        defer { editor.close() }
        if copyWithinApp { editor.bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier) }
        editor.dropPaste = dropPaste
        if caretless { editor.range = nil }
        let suite = "airdraft.delivery-regression.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .parakeet)
        settings.llm.select(refinementFails || refinementEnabled ? .appleIntelligence : .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        let history = try HistoryStore(directory: directory)
        let recorder = DeliveryRecorder()
        let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: ProfileStore(directory: directory), history: history,
            factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Delivery regression tests must not read credentials"); return nil
            }, transcriberBuilder: { _ in DeliverySpeech() },
               refinerBuilder: { _ in DeliveryRefiner(fails: refinementFails) }), recorder: recorder,
            inserter: editor.inserter(), recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
        defer {
            pipeline.cancel()
            try? history.close()
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        var delivered = 0
        pipeline.onOutputDelivered = { delivered += 1 }
        pipeline.startRecording()
        for _ in 0..<100 where !pipeline.isRecording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(pipeline.isRecording)
        if permissionLost { editor.trusted = false }
        pipeline.stopAndProcess()
        for _ in 0..<200 where pipeline.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        let copiedOnly = copyWithinApp || permissionLost || dropPaste
        XCTAssertEqual(editor.pasted, copiedOnly ? [] : [Editor.dictation])
        XCTAssertEqual(delivered, copiedOnly ? 0 : 1)
        if copiedOnly {
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
            let notice = dropPaste
                ? "Paste couldn't be confirmed. Text kept on clipboard; check the destination before pasting again."
                : (copyWithinApp ? "Copied to clipboard" : "Accessibility is off, text copied")
            XCTAssertEqual(pipeline.state, .notice(notice,
                                                  requiresAttention: !copyWithinApp))
            if dropPaste {
                XCTAssertEqual(editor.posts, 1)
                XCTAssertEqual(try history.recent(limit: 1).first?.error, notice)
            }
            try await Task.sleep(for: .milliseconds(3200))
            XCTAssertEqual(pipeline.state, .idle, "The notice timer must reset after three seconds")
        } else {
            XCTAssertNil(pipeline.lastIssue)
        }
        let record = try XCTUnwrap(history.recent(limit: 1).first)
        XCTAssertEqual(record.inserted, !copiedOnly)
        XCTAssertEqual(record.outputSucceeded, !copiedOnly)
        XCTAssertEqual(record.rawTranscript, Editor.dictation)
        XCTAssertEqual(record.finalText, Editor.dictation)
        if refinementEnabled { XCTAssertEqual(record.refinedText, Editor.dictation) }
        if refinementFails {
            XCTAssertEqual(record.error, RefinerError.timeout.localizedDescription)
            XCTAssertEqual(pipeline.lastOutcome?.llmSkippedReason, "LLM failed, using raw transcript")
        }
    }
}

private final class DeliveryRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.1, count: 16000) }
    func cancel() { isRecording = false }
}

private struct DeliverySpeech: Transcriber {
    let id = "delivery-regression-speech"
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        Transcript(text: "Dictated text 中文🙂", engine: id, latencyMs: 0)
    }
}

private struct DeliveryRefiner: Refiner {
    let id = "delivery-regression-refiner"
    let fails: Bool
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        if fails { throw RefinerError.timeout }
        return RefineResult(text: "Dictated text 中文🙂", engine: id, latencyMs: 0, promptVersion: "fixture")
    }
}

@MainActor
private final class Editor {
    static let dictation = "Dictated text 中文🙂"
    static let previousClipboard = "Disposable previous clipboard"
    let clipboard = NSPasteboard.withUniqueName()
    let field = AXUIElementCreateApplication(101)
    let otherField = AXUIElementCreateApplication(102)
    let window = AXUIElementCreateApplication(103)
    let mainWindow = AXUIElementCreateApplication(104)
    let otherWindow = AXUIElementCreateApplication(105)
    let foreignField = AXUIElementCreateApplication(999)
    var currentField: AXUIElement
    var systemField: AXUIElement?
    var focusedWindow: AXUIElement?
    var frontmostPID: Int32 = 101
    var bundleID = "test.editor"
    var systemOwnerPID: Int32 = 101
    var range: CFRange? = CFRange(location: 0, length: 3)
    var trusted = true
    var focusAvailable = true
    var applicationReportsWindow = false
    var alternateRangeOnly = false
    var canEnableWebAccessibility = false
    var webEnabled = false
    var focusReads = 0
    var activations = 0
    var activationDelay: Duration?
    var unreadableValue = false
    var unreadableTextRange = false
    var value = "cat"
    var replacement: String?
    var pasteDelay: Duration?
    var dropPaste = false
    var posts = 0
    var pasted: [String] = []
    var onFocusRead: (() -> Void)?

    init() {
        currentField = field
        focusedWindow = mainWindow
        clipboard.setString(Self.previousClipboard, forType: .string)
    }

    func close() { clipboard.releaseGlobally() }

    func inserter() -> TextInserter {
        let app = TextInserter.Environment.Application(processID: 101, bundleID: bundleID)
        let environment = TextInserter.Environment(frontmostApplication: {
            .init(processID: self.frontmostPID, bundleID: self.frontmostPID == 101 ? app.bundleID : "test.other")
        }, application: { $0 == 101 ? app : nil }, activate: { _ in
            self.activations += 1
            if let delay = self.activationDelay {
                Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    self.frontmostPID = 101
                }
            } else { self.frontmostPID = 101 }
            return true
        }, isTrusted: { self.trusted }, applicationFocus: { _ in
            self.focusReads += 1
            self.onFocusRead?()
            guard self.focusAvailable else { return nil }
            return self.applicationReportsWindow ? self.window : self.currentField
        }, systemFocus: { self.focusAvailable ? (self.systemField ?? self.currentField) : nil },
        focusedWindow: { _ in self.focusedWindow }, processID: { element in
            if CFEqual(element, self.foreignField) { return 999 }
            return CFEqual(element, self.window) ? 101 : self.systemOwnerPID
        }, readAttribute: { element, attribute in
            guard !CFEqual(element, self.window) else { return (.attributeUnsupported, nil) }
            switch attribute as String {
            case kAXRoleAttribute as String: return (.success, kAXTextAreaRole as CFString)
            case kAXSelectedTextRangeAttribute as String:
                guard !self.alternateRangeOnly, var range = self.range else { return (.attributeUnsupported, nil) }
                return (.success, AXValueCreate(.cfRange, &range))
            case kAXSelectedTextRangesAttribute as String:
                guard self.alternateRangeOnly, var range = self.range,
                      let value = AXValueCreate(.cfRange, &range) else { return (.attributeUnsupported, nil) }
                return (.success, [value] as CFArray)
            case kAXValueAttribute as String:
                if self.unreadableValue { return (.attributeUnsupported, nil) }
                return (.success, self.value as CFString)
            default: return (.attributeUnsupported, nil)
            }
        }, enableWebAccessibility: { _ in
            self.webEnabled = self.canEnableWebAccessibility
            return self.webEnabled
        }, postPaste: {
            self.posts += 1
            if self.dropPaste { return true }
            if let delay = self.pasteDelay {
                Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    self.receivePaste()
                }
            } else { self.receivePaste() }
            return true
        }, pasteboard: clipboard, readText: { _, range in
            let source = self.value as NSString
            guard !self.unreadableTextRange, range.location <= source.length,
                  range.length <= source.length - range.location else { return nil }
            return source.substring(with: NSRange(location: range.location, length: range.length))
        })
        let inserter = TextInserter(environment: environment)
        inserter.restoreDelay = 0
        inserter.confirmationTimeout = .milliseconds(50)
        return inserter
    }

    private func receivePaste() {
        guard let text = clipboard.string(forType: .string) else { return }
        pasted.append(text)
        if let range {
            value = (value as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length),
                                                           with: replacement ?? text)
            self.range = CFRange(location: range.location + (text as NSString).length, length: 0)
        }
    }
}
