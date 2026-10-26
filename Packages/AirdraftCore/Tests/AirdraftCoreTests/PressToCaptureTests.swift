import AppKit
import ApplicationServices
import XCTest
@testable import AirdraftCore

/// AD-072: shortcut acceptance to the first captured audio buffer. Uses the
/// production startup path with an injected recorder and OS boundary: no
/// microphone, Accessibility or real apps are touched.
@MainActor
final class PressToCaptureTests: XCTestCase {
    /// A native field publishes its caret; capture waits for it to be stable.
    /// An editor that draws its own text never does, so capture waits for the
    /// caretless settle time before accepting the app-level target.
    enum Destination: String, CaseIterable { case nativeField, caretlessEditor, script }

    func testCaptureLatencyByDestination() async throws {
        var report: [String: Any] = [:]
        for destination in Destination.allCases {
            var pressToCapture: [Int] = []
            var pressToRecording: [Int] = []
            for _ in 0..<7 {
                let fixture = try LatencyFixture(destination: destination)
                defer { fixture.close() }
                let measured = try await fixture.measureStart()
                pressToCapture.append(measured.pressToCaptureMs)
                pressToRecording.append(measured.pressToRecordingMs)
                XCTAssertEqual(fixture.recorder.starts, 1)
                if destination != .script { XCTAssertNotNil(fixture.pipeline.insertionTargetAtStart, "Target capture still runs") }
            }
            report[destination.rawValue] = ["pressToCaptureMedianMs": Self.median(pressToCapture),
                                            "pressToRecordingStateMedianMs": Self.median(pressToRecording)]
        }
        report["simulatedDeviceOpenMs"] = Int(LatencyRecorder.startLatency * 1000)
        report["simulatedFirstBufferMs"] = Int(LatencyRecorder.bufferLatency * 1000)
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print("PRESS_TO_CAPTURE " + String(decoding: json, as: UTF8.self))
        if let output = ProcessInfo.processInfo.environment["AIRDRAFT_PRESS_TO_CAPTURE_OUTPUT"] {
            try json.write(to: URL(fileURLWithPath: output))
        }
        // Capture no longer waits for destination capture: a caretless editor's
        // 250 ms settle happens while audio is already being recorded.
        let caretless = try XCTUnwrap(report[Destination.caretlessEditor.rawValue] as? [String: Int])
        XCTAssertLessThan(caretless["pressToCaptureMedianMs"] ?? .max,
                          Int(TextInserter.caretlessSettleTime.components.seconds * 1000)
                            + Int(TextInserter.caretlessSettleTime.components.attoseconds / 1_000_000_000_000_000))
    }

    private static func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }

    /// Waits until capture runs while the caretless destination is still settling.
    private func startCapturing(_ fixture: LatencyFixture) async throws {
        fixture.pipeline.startRecording()
        for _ in 0..<200 where !fixture.recorder.isRecording { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(fixture.recorder.isRecording, "Capture starts before the destination is captured")
        XCTAssertFalse(fixture.pipeline.isRecording)
        XCTAssertTrue(fixture.pipeline.isBusy)
    }

    /// An early tap, cancel after a release, a setup change and an interruption during destination
    /// capture all stop the microphone and keep no audio; the next press starts cleanly.
    func testCancelSetupChangeOrInterruptionDuringDestinationCaptureDiscardsAudio() async throws {
        do {
            let fixture = try LatencyFixture(destination: .caretlessEditor)
            defer { fixture.close() }
            try await startCapturing(fixture)
            fixture.pipeline.stopAndProcess()   // A tap released this early cancels.
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertEqual(fixture.pipeline.state, .idle)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertFalse(fixture.recorder.isRecording, "The old startup cannot reopen or keep capture")
            XCTAssertFalse(fixture.pipeline.isRecording)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
            // The next press starts cleanly on the same recorder.
            _ = try await fixture.measureStart()
            XCTAssertEqual(fixture.recorder.starts, 2)
        }
        do {
            let fixture = try LatencyFixture(destination: .caretlessEditor)
            defer { fixture.close() }
            fixture.desktop.frontmost = false
            try await startCapturing(fixture)
            try await Task.sleep(for: .milliseconds(400))
            fixture.pipeline.stopAndProcess()
            fixture.pipeline.cancel()
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertEqual(fixture.pipeline.state, .idle)
            fixture.desktop.frontmost = true
            try await Task.sleep(for: .milliseconds(600))
            XCTAssertFalse(fixture.pipeline.isRecording, "The cancelled startup never reaches recording")
            XCTAssertNil(fixture.pipeline.lastOutcome)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        }
        do {
            let fixture = try LatencyFixture(destination: .caretlessEditor)
            defer { fixture.close() }
            try await startCapturing(fixture)
            fixture.settings.outputDestination = .script
            for _ in 0..<500 where fixture.pipeline.isBusy { try await Task.sleep(for: .milliseconds(2)) }
            if case .failed = fixture.pipeline.state {} else { XCTFail("The refusal must be visible") }
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertGreaterThanOrEqual(fixture.recorder.cancels, 1)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
        }
        do {
            let fixture = try LatencyFixture(destination: .caretlessEditor)
            defer { fixture.close() }
            try await startCapturing(fixture)
            fixture.recorder.interruptionHandler?(.inputChanged)
            for _ in 0..<200 where fixture.pipeline.isBusy { try await Task.sleep(for: .milliseconds(2)) }
            guard case .failed(let message) = fixture.pipeline.state else { return XCTFail("The interruption must be visible") }
            XCTAssertTrue(message.contains(AudioRecorderError.inputChanged.localizedDescription))
            XCTAssertFalse(fixture.recorder.isRecording)
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(fixture.pipeline.isRecording, "The cancelled startup never reaches recording")
        }
    }

    /// AD-077: a hold released after speaking, while an app switch is still settling, keeps the
    /// speech: it is processed once the destination is captured, without the audio recorded after
    /// the release grace. Audio captured before the recording state belongs to the dictation.
    func testStartupSpeechReachesProcessingIncludingHoldReleasedDuringDestinationCapture() async throws {
        do {
            let fixture = try LatencyFixture(destination: .caretlessEditor)
            defer { fixture.close() }
            fixture.desktop.frontmost = false
            try await startCapturing(fixture)
            try await Task.sleep(for: .milliseconds(400))
            fixture.pipeline.stopAndProcess()
            XCTAssertTrue(fixture.recorder.isRecording, "Captured speech is kept, not discarded")
            XCTAssertTrue(fixture.pipeline.isBusy)
            try await Task.sleep(for: .milliseconds(300))
            fixture.desktop.frontmost = true
            for _ in 0..<1500 where fixture.pipeline.lastOutcome == nil { try await Task.sleep(for: .milliseconds(2)) }
            XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Latency words")
            XCTAssertEqual(fixture.recorder.cancels, 0)
            XCTAssertFalse(fixture.recorder.isRecording)
            // The recorder returns one second; the session keeps capture start to release plus grace.
            XCTAssertGreaterThan(fixture.pipeline.lastRecordingDuration, 0.7)
            XCTAssertLessThan(fixture.pipeline.lastRecordingDuration, 0.99, "Audio after the release grace is dropped")
        }
        do {
            let fixture = try LatencyFixture(destination: .script)
            defer { fixture.close() }
            _ = try await fixture.measureStart()
            fixture.pipeline.stopAndProcess()
            for _ in 0..<500 where fixture.pipeline.isBusy || fixture.pipeline.isFinishingDelivery {
                try await Task.sleep(for: .milliseconds(2))
            }
            XCTAssertEqual(fixture.pipeline.lastOutcome?.final, "Latency words")
            XCTAssertNotNil(fixture.pipeline.lastOutcome?.timings.pressToCaptureMs)
        }
    }
}

@MainActor
final class LatencyFixture {
    let desktop = FakeDesktop()
    let recorder = LatencyRecorder()
    let settings: AppSettings
    let pipeline: DictationPipeline
    private let suite = "airdraft.latency.\(UUID().uuidString)"
    private let directory: URL
    private let script: URL

    init(destination: PressToCaptureTests.Destination) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        script = directory.appendingPathComponent("deliver.sh")
        try "#!/bin/sh\ncat >/dev/null\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .parakeet)
        settings.llm = LLMConfig(kind: .none)
        settings.useAppContext = false
        settings.livePreviewEnabled = false
        settings.outputDestination = destination == .script ? .script : .cursor
        settings.outputScriptPath = script.path
        desktop.caret = destination == .nativeField ? CFRange(location: 0, length: 0) : nil
        desktop.bundleID = destination == .caretlessEditor ? "dev.zed.Zed" : "test.latency.editor"
        pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
            profiles: ProfileStore(directory: directory), history: nil,
            factory: EngineFactory(status: EngineStatus(), credentialReader: { _ in
                XCTFail("Latency tests must not read credentials"); return nil
            }, transcriberBuilder: { _ in LatencySpeech() }),
            recorder: recorder, inserter: desktop.inserter(), sendScript: { _, _ in },
            recordingPreflight: { _, _, _, _, _ in }, requestMicrophoneAccess: { true })
    }

    struct Measurement { let pressToCaptureMs: Int; let pressToRecordingMs: Int }

    func measureStart() async throws -> Measurement {
        let pressed = ContinuousClock.now
        pipeline.startRecording()
        let token = pipeline.generation
        var recordingAt: ContinuousClock.Instant?
        for _ in 0..<600 {
            if recordingAt == nil, pipeline.isRecording { recordingAt = .now }
            if recordingAt != nil, pipeline.pressToCaptureMs(for: token) != nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let capture = try XCTUnwrap(pipeline.pressToCaptureMs(for: token), "First buffer must be timed")
        let recording = try XCTUnwrap(recordingAt, "Recording must start")
        let toRecording = pressed.duration(to: recording)
        return Measurement(pressToCaptureMs: capture,
                           pressToRecordingMs: Int(toRecording.components.seconds * 1000
                                                   + toRecording.components.attoseconds / 1_000_000_000_000_000))
    }

    func close() {
        pipeline.cancel()
        desktop.close()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
}

/// One frontmost app with a focused element. `caret` nil makes it caretless.
@MainActor
final class FakeDesktop {
    let field = AXUIElementCreateApplication(301)
    let pasteboard = NSPasteboard.withUniqueName()
    var caret: CFRange? = CFRange(location: 0, length: 0)
    var bundleID = "test.latency.editor"
    var frontmost = true

    func close() { pasteboard.releaseGlobally() }

    func inserter() -> TextInserter {
        let environment = TextInserter.Environment(frontmostApplication: {
            self.frontmost ? .init(processID: 301, bundleID: self.bundleID) : nil
        }, application: { $0 == 301 ? .init(processID: 301, bundleID: self.bundleID) : nil },
        activate: { _ in true }, isTrusted: { true }, applicationFocus: { _ in self.field },
        systemFocus: { self.field }, focusedWindow: { _ in nil }, processID: { _ in 301 },
        readAttribute: { _, attribute in
            guard attribute as String == kAXSelectedTextRangeAttribute as String, var caret = self.caret else {
                return (.attributeUnsupported, nil)
            }
            return (.success, AXValueCreate(.cfRange, &caret))
        }, enableWebAccessibility: { _ in false }, postPaste: { true }, pasteboard: pasteboard)
        let inserter = TextInserter(environment: environment)
        inserter.restoreDelay = 0
        inserter.unverifiedRestoreDelay = 0
        inserter.confirmationTimeout = .milliseconds(20)
        return inserter
    }
}

/// Opening the device blocks briefly, like AVAudioEngine.start, and the first
/// buffer arrives on another thread after its own delay.
/// Unchecked: recording state is locked; handlers are set by the MainActor
/// pipeline before start, and the delayed level callback uses a captured copy.
final class LatencyRecorder: AudioRecording, @unchecked Sendable {
    static let startLatency: TimeInterval = 0.03
    static let bufferLatency: TimeInterval = 0.04
    private let lock = NSLock()
    private var recording = false
    private(set) var starts = 0
    private(set) var cancels = 0
    private(set) var startedAt: TimeInterval?
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    var samplesHandler: (@Sendable ([Float]) -> Void)?
    var isRecording: Bool { lock.withLock { recording } }

    func start(microphone: MicrophonePreference) throws {
        if isRecording { throw AudioRecorderError.alreadyRecording }
        Thread.sleep(forTimeInterval: Self.startLatency)
        lock.withLock { recording = true; starts += 1; startedAt = ProcessInfo.processInfo.systemUptime }
        let handler = levelHandler
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.bufferLatency) { [weak self] in
            guard self?.isRecording == true else { return }
            handler?(0.2)
        }
    }

    func stop() -> [Float] {
        lock.withLock { recording = false }
        return [Float](repeating: 0.1, count: 16_000)
    }

    func cancel() {
        lock.withLock { recording = false; cancels += 1 }
    }
}

struct LatencySpeech: Transcriber {
    let id = "latency-speech"
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        Transcript(text: "Latency words", engine: id, latencyMs: 0)
    }
}
