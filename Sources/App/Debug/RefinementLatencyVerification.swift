#if DEBUG
import AirdraftCore
import Foundation

/// Replay an existing PCM file through recording startup and stop without
/// opening audio hardware. Engines, preparation, snapshots and history are real.
@MainActor
enum RefinementLatencyVerification {
    @MainActor
    final class Session {
        let pipeline: DictationPipeline
        private var stopRequested: TimeInterval?
        private(set) var stopToOutcomeMs: Int?
        private(set) var recordingLeadMs = 0

        init(pipeline: DictationPipeline) {
            self.pipeline = pipeline
            pipeline.onOutcome = { [weak self] _ in
                guard let self, let stopRequested = self.stopRequested else { return }
                self.stopToOutcomeMs = Int((ProcessInfo.processInfo.systemUptime - stopRequested) * 1_000)
            }
        }

        func startAndStop(recordingMilliseconds: Int) async throws {
            try await pipeline.startFromAutomation()
            guard pipeline.isRecording else { throw Failure.invalidSetup }
            let recordingStarted = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .milliseconds(recordingMilliseconds))
            guard pipeline.isRecording else { throw Failure.captureStopped }
            recordingLeadMs = Int((ProcessInfo.processInfo.systemUptime - recordingStarted) * 1_000)
            stopRequested = ProcessInfo.processInfo.systemUptime
            try pipeline.stopFromAutomation()
        }

        var report: [String: Any] {
            ["capture": "silent-file-replay", "recordingLeadMs": recordingLeadMs,
             "stopToOutcomeMs": stopToOutcomeMs.map { $0 as Any } ?? NSNull(),
             "measurementEnd": "outcome-after-history", "externalDelivery": false]
        }
    }

    static func makeSession(app: AppContainer, samples: [Float]) throws -> Session {
        guard LocalE2E.isActive, app.isolatedData, app.dataLease?.holdsLease == true,
              app.history != nil, !app.pipeline.isBusy, !samples.isEmpty,
              !app.settings.livePreviewEnabled || app.settings.livePreviewSource == .speechModel,
              !app.settings.useAppContext else {
            throw Failure.invalidSetup
        }
        let pipeline = DictationPipeline(settings: app.settings, dictionary: app.dictionary,
            profiles: app.profiles, history: app.history, factory: app.factory,
            recorder: FileRecorder(samples: samples),
            recordingPreflight: { asr, _, _, _, _ in
                guard asr.kind.isLocal, LocalModels.isInstalled(asr) else { throw Failure.invalidSetup }
                // Apple startup must not install assets during a replay fixture.
                if asr.kind == .apple {
                    let engine = await app.factory.transcriber(for: asr)
                    guard await engine.isReady() else { throw Failure.invalidSetup }
                }
            }, accessCheck: { try await app.license.requireAccess() }, requestMicrophoneAccess: { true })
        pipeline.insertionEnabled = false
        pipeline.prepareRefinement = { [weak models = app.models] config in
            guard let models else { throw CancellationError() }
            return try await models.prepareLLMBackend(config: config)
        }
        pipeline.onLLMUsed = { [weak models = app.models] instance, config in
            models?.noteLLMUsed(instance, config: config)
        }
        pipeline.onStateChange = { [weak pipeline, weak models = app.models] _ in
            models?.setDictationBusy(pipeline?.isBusy == true)
        }
        return Session(pipeline: pipeline)
    }

    static func timingReport(_ timings: DictationTimings) -> [String: Any] {
        var result: [String: Any] = [
            "refinerSetupMs": timings.refinerSetupMs,
            "modelPreparationMs": timings.modelPreparationMs,
            "cliWarmupMs": timings.cliWarmupMs,
            "promptPrefixMs": timings.promptPrefixMs,
            "preparationWaitMs": timings.preparationWaitMs,
            "refinementRequestMs": timings.refinementRequestMs,
            "postProcessingMs": timings.postProcessingMs,
            "deliveryMs": timings.deliveryMs,
            "historyMs": timings.historyMs,
            "processingMs": timings.processingMs,
        ]
        result["stopToDeliveryMs"] = timings.stopToDeliveryMs.map { $0 as Any } ?? NSNull()
        result["pressToCaptureMs"] = timings.pressToCaptureMs.map { $0 as Any } ?? NSNull()
        return result
    }

    private enum Failure: LocalizedError {
        case invalidSetup, captureStopped
        var errorDescription: String? {
            switch self {
            case .invalidSetup: return "Silent recording replay requires isolated local models and history, with app context disabled and live preview off or set to the selected speech model."
            case .captureStopped: return "The recording replay stopped before its requested lead time. Keep --e2e-recording-ms below the recording limit."
            }
        }
    }

    /// Contains only the supplied file; no device, monitoring or playback APIs.
    private final class FileRecorder: AudioRecording, @unchecked Sendable {
        private let lock = NSLock()
        private let samples: [Float]
        private var recording = false
        var isRecording: Bool { lock.withLock { recording } }
        var levelHandler: (@Sendable (Float) -> Void)?
        /// Model live preview (AD-084) receives the file in real-time 100 ms chunks.
        var samplesHandler: (@Sendable ([Float]) -> Void)?
        var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
        init(samples: [Float]) { self.samples = samples }
        func start(microphone: MicrophonePreference) throws {
            lock.withLock { recording = true }
            if let preview = samplesHandler {
                let samples = samples
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let chunk = Int(AudioRecorder.sampleRate / 10)
                    let started = DispatchTime.now().uptimeNanoseconds
                    var offset = 0
                    while offset < samples.count, self?.isRecording == true {
                        preview(Array(samples[offset..<min(offset + chunk, samples.count)]))
                        offset += chunk
                        let due = started + UInt64(offset) * 1_000_000_000 / UInt64(AudioRecorder.sampleRate)
                        let now = DispatchTime.now().uptimeNanoseconds
                        if due > now { usleep(useconds_t((due - now) / 1_000)) }
                    }
                }
            }
            // The file's first chunk stands in for the first device buffer, so
            // the replay reports press-to-capture through production startup.
            let handler = levelHandler
            let first = Array(samples.prefix(Int(AudioRecorder.sampleRate / 10)))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard self?.isRecording == true else { return }
                handler?(AudioLevel.meter(first))
            }
        }
        func stop() -> [Float] { lock.withLock { recording = false }; return samples }
        func cancel() { lock.withLock { recording = false } }
    }
}
#endif
