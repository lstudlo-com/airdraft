import AppKit
import ApplicationServices
import XCTest
@testable import AirdraftCore

/// These tests call the production capture and insert entry points. Only OS
/// reads, AX writes and the posted key event are replaced by a disposable editor.
@MainActor
final class TextDeliveryRegressionTests: XCTestCase {
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
        XCTAssertEqual(editor.writes, 0)
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
    }

    func testAutoPastesOnceAfterExplicitAXRejection() async throws {
        for error: AXError in [.attributeUnsupported, .notImplemented] {
            let editor = Editor()
            defer { editor.close() }
            editor.writeResult = error
            let inserter = editor.inserter()
            let captured = await inserter.captureTarget()
            let target = try XCTUnwrap(captured)
            let result = await inserter.insert(Editor.dictation, target: target)
            XCTAssertEqual(result.method, .paste)
            XCTAssertNil(result.notice)
            XCTAssertEqual(editor.writes, 1)
            XCTAssertEqual(editor.pasted, [Editor.dictation])
        }
    }

    func testAmbiguousAXWriteNeverPastesOrRepeatsTheWrite() async throws {
        for error: AXError in [.cannotComplete, .failure, .invalidUIElement, .apiDisabled] {
            let editor = Editor()
            defer { editor.close() }
            editor.writeResult = error
            let inserter = editor.inserter()
            let captured = await inserter.captureTarget()
            let target = try XCTUnwrap(captured)
            let result = await inserter.insert(Editor.dictation, target: target)
            XCTAssertFalse(result.didInsert)
            XCTAssertEqual(editor.writes, 1)
            XCTAssertTrue(editor.pasted.isEmpty)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        }
    }

    func testRejectedWriteWithChangedDestinationNeverPastes() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.writeResult = .attributeUnsupported
        editor.afterWrite = { editor.range = CFRange(location: 1, length: 0) }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let result = await inserter.insert(Editor.dictation, target: target)
        XCTAssertFalse(result.didInsert)
        XCTAssertEqual(editor.writes, 1)
        XCTAssertTrue(editor.pasted.isEmpty)
    }

    func testAcceptedAXWriteWaitsForTheValueAndReportsDeliveryOnce() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.writeResult = .success
        editor.afterWrite = { editor.range = CFRange(location: Editor.dictation.utf16.count, length: 0) }
        editor.valueAfterWrite = { reads in reads >= 3 ? Editor.dictation : "cat" }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        var delivered = 0
        let result = await inserter.insert(Editor.dictation, target: target) { delivered += 1 }
        XCTAssertEqual(result.method, .accessibility)
        XCTAssertEqual(editor.writes, 1)
        XCTAssertEqual(editor.verificationReads, 3)
        XCTAssertEqual(delivered, 1)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
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
            XCTAssertEqual(editor.writes, 0)
            XCTAssertTrue(editor.pasted.isEmpty)
            XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
        }
    }

    func testUnknownSelectionAndForeignSystemFocusCannotAuthorizePaste() async throws {
        for foreignProcess in [false, true] {
            let editor = Editor()
            defer { editor.close() }
            if !foreignProcess { editor.range = nil }
            if foreignProcess { editor.applicationReportsWindow = true; editor.systemOwnerPID = 999 }
            let inserter = editor.inserter()
            let target = await inserter.captureTarget()
            let result = await inserter.insert(Editor.dictation, method: .paste, target: target)
            XCTAssertFalse(result.didInsert)
            XCTAssertEqual(editor.writes, 0)
            XCTAssertTrue(editor.pasted.isEmpty)
        }
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
        XCTAssertEqual(editor.writes, 0)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.previousClipboard)
    }

    func testCancellationDuringAXVerificationNeverCopiesOrPastes() async throws {
        let editor = Editor()
        defer { editor.close() }
        editor.writeResult = .success
        let read = expectation(description: "AX verification pending")
        editor.valueAfterWrite = { count in
            if count == 1 { read.fulfill() }
            return "cat"
        }
        let inserter = editor.inserter()
        let captured = await inserter.captureTarget()
        let target = try XCTUnwrap(captured)
        let task = Task { @MainActor in await inserter.insert(Editor.dictation, target: target) }
        await fulfillment(of: [read], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.didInsert)
        XCTAssertEqual(editor.writes, 1)
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
        XCTAssertEqual(editor.writes, 0)
        XCTAssertTrue(editor.pasted.isEmpty)
        XCTAssertEqual(editor.clipboard.string(forType: .string), Editor.dictation)
    }

    func testPipelineWithContextOffCapturesPastesAndSavesDeliveredHistory() async throws {
        let editor = Editor()
        defer { editor.close() }
        let suite = "airdraft.delivery-regression.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .parakeet)
        settings.llm.select(.none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        let history = try HistoryStore(directory: directory)
        let recorder = DeliveryRecorder()
        let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: ProfileStore(directory: directory), history: history,
            factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Delivery regression tests must not read credentials"); return nil
            }, transcriberBuilder: { _ in DeliverySpeech() }), recorder: recorder,
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
        pipeline.stopAndProcess()
        for _ in 0..<200 where pipeline.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(editor.pasted, [Editor.dictation])
        XCTAssertEqual(delivered, 1)
        XCTAssertNil(pipeline.lastIssue)
        let record = try XCTUnwrap(history.recent(limit: 1).first)
        XCTAssertTrue(record.inserted)
        XCTAssertEqual(record.outputSucceeded, true)
        XCTAssertEqual(record.rawTranscript, Editor.dictation)
        XCTAssertEqual(record.finalText, Editor.dictation)
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

@MainActor
private final class Editor {
    static let dictation = "Dictated text 中文🙂"
    static let previousClipboard = "Disposable previous clipboard"
    let clipboard = NSPasteboard.withUniqueName()
    let field = AXUIElementCreateApplication(101)
    let otherField = AXUIElementCreateApplication(102)
    let window = AXUIElementCreateApplication(103)
    var currentField: AXUIElement
    var frontmostPID: Int32 = 101
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
    var writes = 0
    var verificationReads = 0
    var pasted: [String] = []
    var writeResult: AXError = .attributeUnsupported
    var afterWrite: (() -> Void)?
    var onFocusRead: (() -> Void)?
    var valueAfterWrite: ((Int) -> String)?

    init() {
        currentField = field
        clipboard.setString(Self.previousClipboard, forType: .string)
    }

    func close() { clipboard.releaseGlobally() }

    func inserter() -> TextInserter {
        let app = TextInserter.Environment.Application(processID: 101, bundleID: "test.editor")
        let environment = TextInserter.Environment(frontmostApplication: {
            .init(processID: self.frontmostPID, bundleID: self.frontmostPID == 101 ? app.bundleID : "test.other")
        }, application: { $0 == 101 ? app : nil }, activate: { _ in
            self.activations += 1
            self.frontmostPID = 101
            return true
        }, isTrusted: { self.trusted }, applicationFocus: { _ in
            self.focusReads += 1
            self.onFocusRead?()
            guard self.focusAvailable else { return nil }
            return self.applicationReportsWindow ? self.window : self.currentField
        }, systemFocus: { self.focusAvailable ? self.currentField : nil }, processID: { element in
            CFEqual(element, self.window) ? 101 : self.systemOwnerPID
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
                if self.writes > 0 {
                    self.verificationReads += 1
                    return (.success, (self.valueAfterWrite?(self.verificationReads) ?? "cat") as CFString)
                }
                return (.success, "cat" as CFString)
            default: return (.attributeUnsupported, nil)
            }
        }, isSettable: { _, _ in true }, writeAttribute: { _, _, _ in
            self.writes += 1
            self.afterWrite?()
            return self.writeResult
        }, enableWebAccessibility: { _ in
            self.webEnabled = self.canEnableWebAccessibility
            return self.webEnabled
        }, postPaste: {
            guard let text = self.clipboard.string(forType: .string) else { return false }
            self.pasted.append(text)
            return true
        }, pasteboard: clipboard)
        let inserter = TextInserter(environment: environment)
        inserter.restoreDelay = 0
        return inserter
    }
}
