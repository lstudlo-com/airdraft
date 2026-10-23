#if DEBUG
import AVFoundation
import AirdraftCore
import CoreAudio
import Foundation

/// Measures press-to-capture and first-buffer latency on the real default input.
/// It runs only when this Debug identity already holds microphone access: it
/// never requests access, never switches devices and keeps no audio. Speech
/// recognition is a fixture that ignores the samples, history is absent and
/// insertion is off, so captured audio is discarded after each trial.
@MainActor
enum CaptureLatencyVerification {
    static func run(app: AppContainer, trials: Int, holdMilliseconds: Int) async throws -> [String: Any] {
        var report: [String: Any] = ["action": "capture-latency", "status": "unverified"]
        // Read the status only. Any audio API used before this check could
        // present the system prompt for an undetermined identity.
        let authorization = AVCaptureDevice.authorizationStatus(for: .audio)
        report["microphoneAuthorization"] = label(authorization)
        guard authorization == .authorized else {
            report["reason"] = "Microphone access is \(label(authorization)) for this Debug identity. The harness never requests access, so the measurement was not run."
            return report
        }
        guard LocalE2E.isActive, app.isolatedData, !app.pipeline.isBusy else { throw Failure.invalidSetup }
        app.settings.livePreviewEnabled = false
        app.settings.useAppContext = false

        let defaultID = MicrophoneDevices.systemDefaultID
        let device = MicrophoneDevices.available().first { $0.id == defaultID }
        report["device"] = [
            "name": device?.name ?? "unknown",
            "transport": transportLabel(device?.transportType),
            "bluetooth": device.map { isBluetooth($0.transportType) } ?? false,
            "selection": "system default (unchanged)",
        ] as [String: Any]

        var firstBuffer: [Int] = []
        for _ in 0..<trials {
            firstBuffer.append(try await recorderFirstBufferMs())
            try await Task.sleep(for: .milliseconds(300))
        }
        report["recorderFirstBufferMs"] = summary(firstBuffer)

        var pressToCapture: [Int] = []
        for _ in 0..<trials {
            pressToCapture.append(try await pipelinePressToCaptureMs(app: app, holdMilliseconds: holdMilliseconds))
            try await Task.sleep(for: .milliseconds(300))
        }
        report["pressToCaptureMs"] = summary(pressToCapture)
        report["trials"] = trials
        report["method"] = "recorderFirstBufferMs: AudioRecorder.start to its first level callback. pressToCaptureMs: production DictationPipeline startup (prerequisites passed by fixture, model ready) to its first captured buffer, read from the outcome timings."
        report["audioStored"] = false
        report["status"] = "passed"
        return report
    }

    /// Recorder-only latency: device open to the first converted buffer.
    private static func recorderFirstBufferMs() async throws -> Int {
        let recorder = AudioRecorder()
        let stamp = FirstStamp()
        recorder.levelHandler = { _ in stamp.mark() }
        let started = ProcessInfo.processInfo.systemUptime
        try recorder.start(microphone: .systemDefault)
        defer { recorder.cancel() }
        let deadline = started + 5
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let first = stamp.value { return Int((first - started) * 1000) }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw Failure.noBuffer
    }

    /// One production startup on the real recorder with fixture speech.
    private static func pipelinePressToCaptureMs(app: AppContainer, holdMilliseconds: Int) async throws -> Int {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil },
                                    transcriberBuilder: { MeasurementSpeech(id: $0.engineID) },
                                    refinerBuilder: { _ in nil })
        let pipeline = DictationPipeline(
            settings: app.settings, dictionary: app.dictionary, profiles: app.profiles,
            history: nil, factory: factory, recorder: AudioRecorder(),
            recordingPreflight: { asr, _, _, _, _ in guard asr.kind.isLocal else { throw Failure.invalidSetup } },
            accessCheck: {},
            requestMicrophoneAccess: { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized })
        pipeline.insertionEnabled = false
        defer { pipeline.cancel() }
        try await pipeline.startFromAutomation()
        guard pipeline.isRecording else { throw Failure.invalidSetup }
        try await Task.sleep(for: .milliseconds(holdMilliseconds))
        try pipeline.stopFromAutomation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while pipeline.isBusy || pipeline.isFinishingDelivery, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        await factory.unloadAll()
        guard let value = pipeline.lastOutcome?.timings.pressToCaptureMs else { throw Failure.noBuffer }
        return value
    }

    private static func summary(_ values: [Int]) -> [String: Any] {
        let sorted = values.sorted()
        return ["samples": values, "first": values.first ?? -1, "min": sorted.first ?? -1,
                "median": sorted.isEmpty ? -1 : sorted[sorted.count / 2], "max": sorted.last ?? -1]
    }

    private static func label(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }

    private static func isBluetooth(_ transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func transportLabel(_ transport: UInt32?) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "built-in"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "bluetooth"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: return "continuity"
        case nil: return "unknown"
        default: return "other"
        }
    }

    private enum Failure: LocalizedError {
        case invalidSetup, noBuffer
        var errorDescription: String? {
            switch self {
            case .invalidSetup: return "Capture latency requires --e2e-local isolated data, an idle pipeline and on-device speech settings."
            case .noBuffer: return "The default input delivered no audio buffer within the deadline."
            }
        }
    }

    /// `@unchecked Sendable`: `first` is guarded by `lock`.
    private final class FirstStamp: @unchecked Sendable {
        private let lock = NSLock()
        private var first: TimeInterval?
        var value: TimeInterval? { lock.withLock { first } }
        func mark() {
            let now = ProcessInfo.processInfo.systemUptime
            lock.withLock { if first == nil { first = now } }
        }
    }

    /// Always ready; ignores the samples so no speech content exists anywhere.
    private struct MeasurementSpeech: Transcriber {
        let id: String
        func isReady() async -> Bool { true }
        func prepare() async throws {}
        func unload() async {}
        func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
            Transcript(text: "capture latency fixture", engine: id, latencyMs: 0)
        }
    }
}
#endif
