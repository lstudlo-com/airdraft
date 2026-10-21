import Foundation
import Observation
import os

public enum PipelineState: Equatable, Sendable {
    case idle
    case recording
    /// First use of a local model: compiling / loading, can take a minute.
    case preparingModel
    case transcribing
    case refining
    case inserting
    case failed(String)
    /// Finished, but something the user should know (LLM offline, text only copied).
    case notice(String, requiresAttention: Bool = true)

    public var isBusy: Bool {
        switch self {
        case .idle, .failed, .notice: return false
        default: return true
        }
    }
}

public struct DictationOutcome: Sendable, Equatable {
    public var raw: String
    public var refined: String
    public var final: String
    public var asrMs: Int
    public var llmMs: Int
    public var llmSkippedReason: String?
    public var timings: DictationTimings = .init()
}

/// Wall-clock stages, in milliseconds. Preparation can overlap recording/ASR;
/// only preparationWaitMs belongs to the final refinement wait.
public struct DictationTimings: Sendable, Equatable {
    public var refinerSetupMs = 0
    public var modelPreparationMs = 0
    public var cliWarmupMs = 0
    public var promptPrefixMs = 0
    public var preparationWaitMs = 0
    public var refinementRequestMs = 0
    public var postProcessingMs = 0
    public var deliveryMs = 0
    public var historyMs = 0
    public var processingMs = 0
    public var stopToDeliveryMs: Int?
    public init() {}
}

/// A failed recording kept in memory until the user retries or discards it.
public struct PendingRecording: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let seconds: Double
    /// The failure shown with this recording's recovery actions.
    public internal(set) var issue: String
    /// Kept by History's retranscription sheet, not by a dictation.
    public let isReview: Bool
}

/// Airdraft never pastes into its own windows. Onboarding practice is the one
/// exception: its editor receives a dictation's final text through this channel,
/// so Try It completes only through the real pipeline.
@MainActor
public protocol PracticeDeliveryTarget: AnyObject {
    /// True when a dictation starting now is meant for the practice editor:
    /// Airdraft is active and that editor has keyboard focus.
    var acceptsDictation: Bool { get }
    /// Inserts the final text into the practice editor; false if it is gone.
    func insertDictation(_ text: String) -> Bool
}

/// Record -> transcribe -> (refine) -> dictionary -> insert -> history.
/// The LLM is best-effort: any failure or timeout falls back to the raw
/// transcript so dictation never blocks on a slow model.
@MainActor
@Observable
public final class DictationPipeline {
    public private(set) var state: PipelineState = .idle
    public private(set) var lastIssue: String?
    /// Failed recordings waiting for explicit retry or discard, oldest first.
    public var pendingRecordings: [PendingRecording] { recoveries.map(\.info) }
    public var hasRecoverableRecording: Bool { !recoveries.isEmpty }
    /// The newest dictation recovery: Home and the menu act on this one.
    public var latestPendingDictation: PendingRecording? { recoveries.last { !$0.info.isReview }?.info }
    /// New dictation stays available while failed recordings wait. Bound their
    /// memory: at most three recordings or 15 minutes of 16 kHz audio (~58 MB),
    /// then ask for a retry or discard instead of dropping audio. The bound is
    /// hard: a new recording starts only while the kept audio plus its own
    /// effective recording limit still fits, so a failure can always be kept.
    public static let maximumPendingRecordings = 3
    public static let maximumPendingRecordingSeconds: Double = 900
    public var canKeepAnotherRecording: Bool {
        let dictations = recoveries.filter { !$0.info.isReview }
        let limit = SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: speechConfig.kind)
        return dictations.count < Self.maximumPendingRecordings
            && dictations.reduce(0) { $0 + $1.info.seconds } + Double(limit) <= Self.maximumPendingRecordingSeconds
    }
    public private(set) var historyStorageError: String?
    public private(set) var isSavingHistory = false
    /// A delivered dictation is still saving history and publishing its outcome.
    /// The next recording may already run; quit and data maintenance wait.
    public private(set) var isFinishingDelivery = false
    private var deliveryTail: Task<Void, Never>?
    private var deliveryTailID: UUID?
    private var historySaveTask: Task<Void, Never>?
    public private(set) var isMaintainingData = false
    private var maintenanceReason: String?
    public var isProcessingMedia = false
    public var isCapturingMeeting = false
    public private(set) var previewText = ""
    public private(set) var previewIssue: String?
    public private(set) var previewEnabledForRecording = false
    private var previewSession: (any SpeechPreviewSession)?
    public typealias PreviewBuilder = @Sendable (String, @escaping @Sendable (String) -> Void, @escaping @Sendable (String) -> Void) -> any SpeechPreviewSession
    private let previewBuilder: PreviewBuilder
    public private(set) var reviewOutcome: DictationOutcome?
    public private(set) var audioStorageError: String?
    public private(set) var audioRevision = 0
    private var reviewGeneration: UUID?
    private struct OutputSnapshot: Sendable, Equatable {
        var destination: TextOutputDestination
        var scriptPath: String
        var insertionMethod: InsertionMethod
    }
    private struct RecordingSnapshot: Sendable, Equatable {
        let asr: ASRConfig
        let profile: RefinementProfile
        let llm: LLMConfig
        let microphone: MicrophonePreference
        let output: OutputSnapshot
        let baseRules: String
        let dictionary: [DictionaryEntry]
        let useAppContext: Bool
    }
    private var recordingAtStart: RecordingSnapshot?
    private let sendScript: @Sendable (String, String) async throws -> Void
    private struct Recovery {
        var info: PendingRecording
        let samples: [Float]
        var context: AppContext
        var target: InsertionTarget?
        var reviewOnly: Bool
        let output: OutputSnapshot
    }
    private var recoveries: [Recovery] = []
    /// The recovery an explicit retry is processing, keyed by its generation.
    private var retryingRecovery: (token: UUID, id: UUID)?
    private var unsavedHistory: [(record: DictationRecord, samples: [Float]?)] = []
    private let historyDirectory: URL?
    public private(set) var historyStore: HistoryStore?
    public private(set) var lastOutcome: DictationOutcome?
    /// Most recent input levels (0...1), oldest first. Drives the HUD waveform.
    public private(set) var levelHistory: [Float] = []
    public static let levelHistoryLength = 22
    public private(set) var recordingStartedAt: Date?
    public private(set) var lastRecordingDuration: TimeInterval = 0

    public var onStateChange: ((PipelineState) -> Void)?
    public var onRecordingBlocked: (() -> Void)?
    public var onOutcome: ((DictationOutcome) -> Void)?
    /// Delivery feedback precedes clipboard restoration and history persistence.
    /// Paste delivery requires read-back of the expected text in the original field.
    public var onOutputDelivered: (() -> Void)?
    /// Called with the LLM instance id that served a refinement.
    public var onLLMUsed: ((String, LLMConfig) -> Void)?
    /// Ensures the captured refinement model is ready. Starts during recording;
    /// final refinement joins the same preparation instead of repeating discovery.
    public var prepareRefinement: ((LLMConfig) async throws -> RefinementPreparationBackend)?
    /// When false the final text is not inserted anywhere (self-tests).
    public var insertionEnabled = true
    /// Onboarding practice's editor. Consulted only while practice runs.
    public weak var practiceTarget: (any PracticeDeliveryTarget)?

    private let settings: AppSettings
    private let dictionary: DictionaryStore
    private let profiles: ProfileStore
    private var history: HistoryStore? { historyStore }
    private let factory: EngineFactory
    private let recorder: any AudioRecording
    private let contextReader: AppContextReader
    private let insertText: ((String, InsertionMethod, InsertionTarget?) async -> InsertionResult)?
    private let inserter: TextInserter

    private var generation = UUID()
    private var releaseTask: Task<Void, Never>?
    @MainActor private final class RefinementPreparation {
        let token: UUID
        var task: Task<any Refiner, Error>?
        var prefixTask: Task<Void, Never>?
        var setupMs = 0
        var modelMs = 0
        var cliMs = 0
        var prefixMs = 0
        var setupStarted: TimeInterval?
        var modelStarted: TimeInterval?
        var cliStarted: TimeInterval?
        var prefixStarted: TimeInterval?
        var setupDuration: Int { setupStarted.map { DictationPipeline.elapsed(since: $0) } ?? setupMs }
        var modelDuration: Int { modelStarted.map { DictationPipeline.elapsed(since: $0) } ?? modelMs }
        var cliDuration: Int { cliStarted.map { DictationPipeline.elapsed(since: $0) } ?? cliMs }
        var prefixDuration: Int { prefixStarted.map { DictationPipeline.elapsed(since: $0) } ?? prefixMs }
        init(token: UUID) { self.token = token }
    }
    @MainActor private final class RefinementAttempt {
        var preparationWaitMs = 0
        var requestStarted: TimeInterval?
        var requestMs = 0
        var requestFinished = false
    }
    private var refinementPreparation: RefinementPreparation?
    /// Keeps the session's local speech engine out of idle unloading.
    private var speechSessionPin: (token: UUID, pin: UUID)?
    private var stopRequestedAt: TimeInterval?
    private var insertionTargetAtStart: InsertionTarget?
    /// The recording was started for onboarding practice's own editor.
    private var practiceDeliveryAtStart = false
    /// How cursor delivery treats one processing run.
    private enum DeliveryPolicy {
        /// Paste into the captured target; a caretless editor may be sent unverified.
        case normal
        /// An explicit retry: verified targets only, otherwise copy.
        case retry
        /// Onboarding practice's own editor.
        case practice
        /// Retries during practice never paste or run a script.
        case copyOnly
    }
    private var contextAtStart: AppContext = .empty
    private var processingTask: Task<Void, Never>?
    /// Returns a failure or notice to idle; replaced whenever the state changes.
    private var resetTask: Task<Void, Never>?
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "pipeline")
    private var autoStopTask: Task<Void, Never>?
    private var stopping = false
    private var recordingRequest: Task<Void, Never>?
    private var recordingRequestID = UUID()
    private let recordingPreflight: (@MainActor (ASRConfig, LLMConfig, Bool, MicrophonePreference, Bool) async throws -> Void)?
    private let accessCheck: @MainActor () async throws -> Void
    public var speechConfig: ASRConfig { settings.speechConfig(for: profiles.activeProfile) }
    private let requestMicrophoneAccess: @Sendable () async -> Bool

    public init(
        settings: AppSettings,
        dictionary: DictionaryStore,
        profiles: ProfileStore,
        history: HistoryStore?,
        historyDirectory: URL? = nil,
        factory: EngineFactory,
        recorder: any AudioRecording = AudioRecorder(),
        previewBuilder: @escaping PreviewBuilder = { SpeechPreview.start(locale: $0, onText: $1, onIssue: $2) },
        contextReader: AppContextReader? = nil,
        inserter: TextInserter? = nil,
        insertText: ((String, InsertionMethod, InsertionTarget?) async -> InsertionResult)? = nil,
        sendScript: @escaping @Sendable (String, String) async throws -> Void = { try await ScriptDelivery.send(text: $0, to: $1) },
        recordingPreflight: (@MainActor (ASRConfig, LLMConfig, Bool, MicrophonePreference, Bool) async throws -> Void)? = nil,
        accessCheck: @escaping @MainActor () async throws -> Void = {},
        requestMicrophoneAccess: @escaping @Sendable () async -> Bool = { await AudioRecorder.requestMicrophoneAccess() }
    ) {
        self.settings = settings
        self.dictionary = dictionary
        self.profiles = profiles
        self.historyStore = history
        self.historyDirectory = historyDirectory
        if history == nil && historyDirectory != nil { historyStorageError = String(localized: "History is unavailable. Dictations stay in memory until saved. Retry saving or check the data folder.", bundle: .module) }
        self.factory = factory
        self.recorder = recorder
        self.previewBuilder = previewBuilder
        self.contextReader = contextReader ?? AppContextReader()
        self.inserter = inserter ?? TextInserter()
        self.insertText = insertText
        self.sendScript = sendScript
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.recordingPreflight = recordingPreflight
        self.accessCheck = accessCheck

    }

    private func wireRecorder(for token: UUID) {
        recorder.levelHandler = { [weak self] level in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording else { return }
                self.levelHistory.append(level)
                if self.levelHistory.count > Self.levelHistoryLength {
                    self.levelHistory.removeFirst(self.levelHistory.count - Self.levelHistoryLength)
                }
            }
        }
        recorder.interruptionHandler = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording else { return }
                let samples = self.recorder.stop()
                let context = self.contextAtStart
                let target = self.insertionTargetAtStart
                let output = self.recordingAtStart?.output
                self.cancel()
                let message = reason.localizedDescription + (samples.isEmpty ? "" : " " + String(localized: "Captured audio is kept for retry.", bundle: .module))
                if !samples.isEmpty { self.retain(samples, context: context, target: target, output: output, issue: message) }
                self.fail(message, openRecovery: !samples.isEmpty)
            }
        }
    }

    private func startPreview(for token: UUID) {
        stopPreview()
        guard settings.livePreviewEnabled, settings.hudStyle != .none else { return }
        previewEnabledForRecording = true
        let session = previewBuilder(settings.livePreviewLocale, { [weak self] text in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording, self.previewEnabledForRecording else { return }
                self.previewText = String(text.suffix(500))
            }
        }, { [weak self] issue in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording, self.previewEnabledForRecording else { return }
                self.previewText = ""
                self.previewIssue = issue
            }
        })
        previewSession = session
        recorder.samplesHandler = { samples in session.append(samples) }
    }

    /// Apply an explicit Off choice immediately without interrupting final capture.
    public func disableLivePreview() { stopPreview() }

    private func stopPreview() {
        recorder.samplesHandler = nil
        previewSession?.cancel()
        previewSession = nil
        previewText = ""
        previewIssue = nil
        previewEnabledForRecording = false
    }

    public var isRecording: Bool { state == .recording }
    /// Work outside dictation that excludes a new recording.
    private var exclusiveWorkReason: String? {
        if isMaintainingData {
            return maintenanceReason ?? String(localized: "Recording is unavailable while Airdraft manages its data.", bundle: .module)
        }
        if isCapturingMeeting { return String(localized: "Stop the meeting recording before dictating.", bundle: .module) }
        if isProcessingMedia { return String(localized: "Wait for the media transcription to finish before dictating.", bundle: .module) }
        return nil
    }
    public var isBusy: Bool { isMaintainingData || isProcessingMedia || isCapturingMeeting || state.isBusy || recordingRequest != nil }

    // MARK: - Control

    public func toggle() {
        if recordingRequest != nil && !isRecording { cancel() }
        else if isRecording { stopAndProcess() } else { startRecording() }
    }

    public func startRecording() {
        // Recording, startup and processing are already visible in the HUD.
        guard !state.isBusy, recordingRequest == nil else { return }
        if let reason = exclusiveWorkReason {
            // Never drop a shortcut press silently while nothing else is shown.
            fail(reason)
            return
        }
        guard canKeepAnotherRecording else {
            // Never drop kept audio to make room; ask for a retry or discard instead.
            fail(String(localized: "Several recordings are waiting for retry. Open Airdraft to retry or discard one before recording again.", bundle: .module), openRecovery: true)
            return
        }
        let token = UUID()
        recordingRequestID = token
        generation = token
        recordingRequest = Task {
            await beginRecording(token: token)
            // Every early return or cancellation before capture ends the pin.
            if !(isCurrent(token) && isRecording) { releaseSpeechSessionPin(for: token) }
            if recordingRequestID == token { recordingRequest = nil }
        }
    }

    /// App Intents use the same startup task and only report success once capture begins.
    public func startFromAutomation() async throws {
        if isRecording { return }
        guard !isBusy else { throw RecordingPrerequisiteError(String(localized: "Airdraft is already starting or processing a recording.", bundle: .module)) }
        guard canKeepAnotherRecording else { throw RecordingPrerequisiteError(String(localized: "Retry or discard the saved recording in Airdraft first.", bundle: .module)) }
        try Task.checkCancellation()
        startRecording()
        let token = recordingRequestID
        guard let request = recordingRequest else {
            throw RecordingPrerequisiteError(lastIssue ?? String(localized: "Recording could not start.", bundle: .module))
        }
        do {
            try await OperationDeadline.run(seconds: 15) { await request.value }
            try Task.checkCancellation()
        } catch {
            if recordingRequestID == token, generation == token { cancel() }
            if case RefinerError.timeout = error {
                throw RecordingPrerequisiteError(String(localized: "Recording startup timed out. Open Airdraft to check the selected model and permissions.", bundle: .module))
            }
            throw error
        }
        guard generation == token else { throw CancellationError() }
        guard isRecording else { throw RecordingPrerequisiteError(lastIssue ?? String(localized: "Recording did not start.", bundle: .module)) }
    }

    public func stopFromAutomation() throws {
        guard isRecording || recordingRequest != nil || !isBusy else {
            throw RecordingPrerequisiteError(String(localized: "Airdraft is already processing a recording.", bundle: .module))
        }
        stopAndProcess()
    }

    public func cancelFromAutomation() throws {
        guard state != .inserting else {
            throw RecordingPrerequisiteError(String(localized: "Text delivery has started and cannot be cancelled safely.", bundle: .module))
        }
        cancel()
    }

    private func selectedOutput() -> OutputSnapshot {
        OutputSnapshot(destination: settings.outputDestination, scriptPath: settings.outputScriptPath,
                       insertionMethod: settings.insertionMethod)
    }

    private func recordingSnapshot(output: OutputSnapshot? = nil) -> RecordingSnapshot {
        let profile = settings.effectiveProfile(profiles.activeProfile)
        return RecordingSnapshot(asr: profile.speechConfig(default: settings.asr), profile: profile,
                                 llm: settings.llm, microphone: settings.microphone,
                                 output: output ?? selectedOutput(), baseRules: profiles.baseRules,
                                 dictionary: dictionary.entries, useAppContext: settings.useAppContext)
    }

    private func beginRecording(token: UUID) async {
        guard isCurrent(token) else { return }
        let snapshot = recordingSnapshot()
        let asr = snapshot.asr
        let llm = snapshot.llm
        let profile = snapshot.profile
        let microphone = snapshot.microphone
        let output = snapshot.output
        let needsInsertion = insertionEnabled && output.destination == .cursor
        // Read earlier dictations while startup checks run, before the destination is known.
        let recentFinals = snapshot.useAppContext ? prefetchRecentFinals(appBundleId: nil) : nil
        do {
            try await accessCheck()
            guard isCurrent(token) else { return }
            if let reason = profile.speechModel?.unavailableReason {
                throw RecordingPrerequisiteError(reason)
            }
            if insertionEnabled, output.destination == .script, let reason = ScriptDelivery.unavailableReason(path: output.scriptPath) {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start.", bundle: .module) + " " + reason)
            }
            _ = try SpeechLanguagePolicy.resolve(asr)
            if let recordingPreflight {
                try await recordingPreflight(asr, llm, profile.usesLLM, microphone, needsInsertion)
            } else {
                try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: profile.usesLLM,
                                                 microphone: microphone, insertionEnabled: needsInsertion)
            }
            guard isCurrent(token) else { return }
            guard recordingSnapshot() == snapshot else {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            }
            if asr.kind.isLocal {
                // Pin before checking readiness so the idle watch cannot unload
                // the model between this check and the end of processing.
                let limit = SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: asr.kind)
                let pin = await factory.pinForSession(asr.engineID, recordingSeconds: TimeInterval(limit))
                guard isCurrent(token) else { await factory.releaseSessionPin(pin); return }
                releaseSpeechSessionPin()
                speechSessionPin = (token, pin)
                let engine = await factory.transcriber(for: asr)
                let ready = await engine.isReady()
                guard isCurrent(token) else { return }
                if !ready {
                    set(.preparingModel)
                    // Join any startup/UI load through the factory's load lease.
                    try await factory.prepare(asr)
                } else {
                    // Capture can begin while cancelled inference winds down.
                    // A ready model needs only its idle timestamp refreshed.
                    await factory.markUsed(engine.id)
                }
            }
            guard isCurrent(token) else { return }
            guard recordingSnapshot() == snapshot else {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            }
        } catch {
            guard isCurrent(token) else { return }
            fail(error.localizedDescription)
            onRecordingBlocked?()
            return
        }
        let granted = await requestMicrophoneAccess()
        guard isCurrent(token) else { return }
        guard granted else {
            fail(String(localized: "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        guard recordingSnapshot() == snapshot else {
            fail(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        // Practice's own editor is inside Airdraft, which is never a paste target.
        let practice = needsInsertion && settings.isOnboardingPractice && practiceTarget?.acceptsDictation == true
        let insertionTarget = needsInsertion && !practice ? await inserter.captureTarget() : nil
        guard isCurrent(token) else { return }
        var context = snapshot.useAppContext ? contextReader.read() : .empty
        if let recentFinals, context.recentDictations.isEmpty {
            context.recentDictations = await recentFinals.finals(for: context.bundleId)
            guard isCurrent(token) else { return }
        }
        guard recordingSnapshot() == snapshot else {
            fail(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        recordingAtStart = snapshot
        insertionTargetAtStart = insertionTarget
        practiceDeliveryAtStart = practice
        contextAtStart = context
        wireRecorder(for: token)
        startPreview(for: token)
        do {
            try recorder.start(microphone: microphone)
        } catch {
            stopPreview()
            fail(String(localized: "Could not start recording: \(error.localizedDescription)", bundle: .module))
            onRecordingBlocked?()
            return
        }
        recordingStartedAt = Date()
        stopRequestedAt = nil
        levelHistory = []
        set(.recording)
        startRefinementPreparation(context: contextAtStart, snapshot: snapshot, token: token)

        let limit = SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: asr.kind)
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard let self, self.isCurrent(token) else { return }
            self.finishRecording()
        }
    }

    /// Keep capturing briefly after the key is released: people let go while
    /// the last syllable is still sounding.
    public static let releaseGraceSeconds: Double = 0.35

    public func stopAndProcess() {
        if recordingRequest != nil && !isRecording {
            cancel()
            return
        }
        guard state == .recording, !stopping else { return }
        stopRequestedAt = ProcessInfo.processInfo.systemUptime
        stopping = true
        let token = generation
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.releaseGraceSeconds))
            guard self.isCurrent(token) else { return }
            self.stopping = false
            self.finishRecording()
        }
    }

    private func finishRecording() {
        guard state == .recording, let snapshot = recordingAtStart else { return }
        if stopRequestedAt == nil { stopRequestedAt = ProcessInfo.processInfo.systemUptime }
        autoStopTask?.cancel()
        releaseTask?.cancel()
        stopping = false
        stopPreview()
        let samples = recorder.stop()
        recordingAtStart = nil
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        recordingStartedAt = nil

        guard seconds >= 0.3 else {
            discardRefinementPreparation()
            releaseSpeechSessionPin()
            set(.idle)
            return
        }
        set(.transcribing)
        let ctx = contextAtStart
        let token = generation
        let target = insertionTargetAtStart
        let delivery: DeliveryPolicy = practiceDeliveryAtStart ? .practice : .normal
        processingTask = Task { await process(samples: samples, seconds: seconds, context: ctx, target: target, token: token, snapshot: snapshot, delivery: delivery) }
    }

    /// Runs 16 kHz mono samples through transcription, refinement, dictionary and
    /// history exactly like a recording would. Used by self-tests and the CLI.
    public func processSamples(_ samples: [Float], context: AppContext = .empty) {
        guard !isBusy else { return }
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        let snapshot = recordingSnapshot()
        let token = generation
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        levelHistory = []
        set(.transcribing)
        processingTask = Task {
            do {
                try await accessCheck()
                guard isCurrent(token) else { return }
                await process(samples: samples, seconds: seconds, context: context, target: nil, token: token, snapshot: snapshot)
            } catch {
                guard isCurrent(token) else { return }
                fail(error.localizedDescription)
                onRecordingBlocked?()
            }
        }
    }

    /// Review old audio without insertion, clipboard changes, or duplicate history.
    /// This delivery policy survives speech failures and explicit retries.
    public func retranscribe(_ record: DictationRecord) {
        guard let history else { return }
        retranscribe { try history.audioSamples(for: record) }
    }

    public func retranscribe(_ asset: RecordingAsset) {
        guard let history else { return }
        retranscribe { try history.audioSamples(for: asset) }
    }

    private func retranscribe(loadSamples: @escaping @Sendable () throws -> [Float]) {
        guard !isBusy else { return }
        // One review at a time: its recovery belongs to the sheet that started it.
        recoveries.removeAll { $0.info.isReview }
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        let token = generation
        reviewGeneration = token
        reviewOutcome = nil
        lastIssue = nil
        let snapshot = recordingSnapshot()
        set(.transcribing)
        processingTask = Task {
            do {
                try await accessCheck()
                guard isCurrent(token) else { return }
                let samples = try await Task.detached(operation: loadSamples).value
                guard isCurrent(token) else { return }
                await process(samples: samples, seconds: Double(samples.count) / AudioRecorder.sampleRate,
                              context: .empty, target: nil, token: token, snapshot: snapshot, reviewOnly: true)
            } catch {
                guard isCurrent(token) else { return }
                fail(String(localized: "Recording could not be opened.", bundle: .module) + " " + error.localizedDescription)
                if error is LicenseError { onRecordingBlocked?() }
            }
        }
    }

    public func dismissReview() {
        // The reviewed audio stays in History; closing the sheet ends its recovery.
        recoveries.removeAll { $0.info.isReview }
        if reviewGeneration == generation {
            cancel()
            reviewOutcome = nil
            reviewGeneration = nil
            lastIssue = nil
        }
    }

    public func pruneSavedAudio() async {
        guard !isMaintainingData, let history else { return }
        let cutoff = settings.audioRetention.cutoff()
        do {
            try await Task.detached { try history.pruneAudio(olderThan: cutoff) }.value
            audioStorageError = nil
            audioRevision += 1
        } catch { audioStorageError = String(localized: "Saved audio could not be removed.", bundle: .module) + " " + error.localizedDescription }
    }

    /// Build once, discover/load a managed model and start a supported CLI while
    /// recording/ASR is running. No transcript is sent until final recognition.
    private func startRefinementPreparation(context: AppContext, snapshot: RecordingSnapshot, token: UUID) {
        guard refinementPreparation?.token != token else { return }
        discardRefinementPreparation()
        let config = snapshot.llm
        let profile = snapshot.profile
        guard profile.usesLLM, config.kind != .none else { return }
        let request = RefineRequest(
            transcript: "",
            profile: profile,
            baseRules: snapshot.baseRules,
            context: context,
            family: AppFamily.classify(context),
            dictionary: snapshot.dictionary,
            chineseScript: snapshot.asr.chineseScript
        )
        let preparation = RefinementPreparation(token: token)
        refinementPreparation = preparation
        let prepare = prepareRefinement
        preparation.task = Task { [factory] in
            // A cold native load may finish while a long recording continues.
            // Its speculative lifetime is independent of the final refinement
            // deadline, which still bounds the remaining wait plus the request.
            return try await OperationDeadline.run(seconds: 300) { @MainActor in
                try Task.checkCancellation()
                let setupStarted = ProcessInfo.processInfo.systemUptime
                preparation.setupStarted = setupStarted
                guard var refiner = await factory.refiner(for: config) else { throw RefinerError.invalidResponse }
                preparation.setupMs = Self.elapsed(since: setupStarted)
                preparation.setupStarted = nil
                try Task.checkCancellation()
                let modelStarted = ProcessInfo.processInfo.systemUptime
                preparation.modelStarted = modelStarted
                let backend: RefinementPreparationBackend
                do { backend = try await prepare?(config) ?? .unmanaged }
                catch {
                    preparation.modelMs = Self.elapsed(since: modelStarted)
                    preparation.modelStarted = nil
                    throw error
                }
                preparation.modelMs = Self.elapsed(since: modelStarted)
                preparation.modelStarted = nil
                try Task.checkCancellation()
                let warmStarted = ProcessInfo.processInfo.systemUptime
                if config.kind.isCLI { preparation.cliStarted = warmStarted }
                refiner = try await refiner.prepare(request, backend: backend, owner: token)
                if config.kind.isCLI {
                    preparation.cliMs = Self.elapsed(since: warmStarted)
                    preparation.cliStarted = nil
                }
                if backend == .lmStudio {
                    let preparedRefiner = refiner
                    preparation.prefixTask = Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        let prefixStarted = ProcessInfo.processInfo.systemUptime
                        preparation.prefixStarted = prefixStarted
                        defer {
                            preparation.prefixMs = Self.elapsed(since: prefixStarted)
                            preparation.prefixStarted = nil
                        }
                        // Speculative work must never consume the final request's
                        // deadline. It is cancelled as soon as ASR is complete.
                        do {
                            try await OperationDeadline.run(seconds: config.timeoutSeconds) {
                                try await preparedRefiner.prewarmPrompt(request, backend: backend)
                            }
                        } catch {}
                    }
                }
                try Task.checkCancellation()
                return refiner
            }
        }
    }

    private func discardRefinementPreparation(for token: UUID? = nil) {
        guard let preparation = refinementPreparation, token == nil || preparation.token == token else { return }
        preparation.task?.cancel()
        preparation.prefixTask?.cancel()
        refinementPreparation = nil
        Task { await CLIRefiner.discardPrewarm(owner: preparation.token) }
    }

    private func releaseSpeechSessionPin(for token: UUID? = nil) {
        guard let current = speechSessionPin, token == nil || current.token == token else { return }
        speechSessionPin = nil
        Task { [factory] in await factory.releaseSessionPin(current.pin) }
    }

    private static func elapsed(since start: TimeInterval) -> Int {
        Int(max(0, ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    public func cancel() {
        // Once a write begins, finish recording its outcome before accepting a new session.
        guard state != .inserting else { return }
        stopPreview()
        generation = UUID()
        // Kept recordings survive cancellation; only an explicit discard removes them.
        retryingRecovery = nil
        releaseTask?.cancel()
        discardRefinementPreparation()
        releaseSpeechSessionPin()
        stopRequestedAt = nil
        recordingRequestID = UUID()
        recordingRequest?.cancel()
        recordingRequest = nil
        stopping = false
        autoStopTask?.cancel()
        processingTask?.cancel()
        if recorder.isRecording { recorder.cancel() }
        recordingStartedAt = nil
        recordingAtStart = nil
        set(.idle)
    }

    public func dismissIssue() { lastIssue = nil }

    /// Discards `id`, or the newest kept recording when `id` is nil.
    public func discardRecording(_ id: UUID? = nil) {
        guard !isBusy, let index = recoveryIndex(id) else { return }
        let removed = recoveries.remove(at: index)
        if lastIssue == removed.info.issue || recoveries.isEmpty { lastIssue = nil }
        set(.idle)
    }

    /// Retries `id`, or the newest kept recording when `id` is nil. Current
    /// processing settings apply; the original delivery target and policy stay.
    /// A caretless target is copied instead of pasted, and a retry during
    /// onboarding practice only copies: practice never runs a saved script.
    public func retryRecording(_ id: UUID? = nil) {
        guard !isBusy, let index = recoveryIndex(id) else { return }
        let recovery = recoveries[index]
        let snapshot = recordingSnapshot(output: recovery.output)
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        let token = generation
        retryingRecovery = (token, recovery.info.id)
        if recovery.reviewOnly { reviewGeneration = token }
        set(.transcribing)
        let delivery: DeliveryPolicy = settings.isOnboardingPractice ? .copyOnly : .retry
        processingTask = Task {
            await process(samples: recovery.samples, seconds: recovery.info.seconds,
                          context: recovery.context, target: recovery.target, token: token, snapshot: snapshot,
                          reviewOnly: recovery.reviewOnly, delivery: delivery)
        }
    }

    private func recoveryIndex(_ id: UUID?) -> Int? {
        guard let id else { return recoveries.indices.last }
        return recoveries.firstIndex { $0.info.id == id }
    }

    /// Keeps failed audio. A failed retry replaces its own entry and becomes the newest.
    private func retain(_ samples: [Float], context: AppContext, target: InsertionTarget?, reviewOnly: Bool = false,
                        output: OutputSnapshot? = nil, issue: String, replacing id: UUID? = nil) {
        var isReview = reviewOnly && reviewGeneration == generation
        if let id, let index = recoveries.firstIndex(where: { $0.info.id == id }) {
            isReview = recoveries[index].info.isReview
            recoveries.remove(at: index)
        }
        if isReview { recoveries.removeAll { $0.info.isReview } }
        let info = PendingRecording(id: id ?? UUID(), createdAt: Date(), seconds: Double(samples.count) / AudioRecorder.sampleRate,
                                    issue: issue, isReview: isReview)
        recoveries.append(Recovery(info: info, samples: samples, context: context, target: target, reviewOnly: reviewOnly,
                                   output: output ?? recordingAtStart?.output ?? selectedOutput()))
    }

    /// Successful or silent processing resolves the recovery a retry was
    /// processing, once its result is held by History's pending saves or the
    /// review outcome. Cancellation before that point keeps the audio.
    private func resolveRecovery(for token: UUID) {
        guard let retrying = retryingRecovery, retrying.token == token else { return }
        retryingRecovery = nil
        recoveries.removeAll { $0.info.id == retrying.id }
    }

    /// Saves pending dictations. Calls are serialized: a caller that arrives
    /// during another save waits for it, then saves anything it left behind.
    public func retryHistorySave() async {
        while let running = historySaveTask {
            await running.value
            if unsavedHistory.isEmpty && historyStorageError == nil { return }
            // Another waiter may already have started the follow-up save.
            if historySaveTask == nil { break }
        }
        guard !isMaintainingData else { return }
        isSavingHistory = true
        let task = Task { @MainActor in await self.saveUnsavedHistory() }
        historySaveTask = task
        await task.value
    }

    private func saveUnsavedHistory() async {
        defer {
            isSavingHistory = false
            historySaveTask = nil
        }
        do {
            if historyStore == nil, let historyDirectory { historyStore = try HistoryStore(directory: historyDirectory) }
            guard let historyStore else { return }
            while let pending = unsavedHistory.first {
                let audio = settings.audioRetention == .off ? nil : pending.samples
                _ = try await Task.detached { try historyStore.save(pending.record, samples: audio) }.value
                unsavedHistory.removeFirst()
            }
            historyStorageError = nil
            await pruneSavedAudio()
        } catch {
            historyStorageError = String(localized: "History could not be saved. Your unsaved dictations remain in memory.", bundle: .module) + " " + error.localizedDescription
        }
    }

    /// Freeze every entry point before deletion. Existing writes must finish
    /// first; setting the flag is synchronous on the same actor as those starts.
    /// `reason` replaces the generic cleanup message shown for a rejected
    /// shortcut, e.g. when another running copy holds the data lease.
    public func beginDataMaintenance(reason: String? = nil) throws {
        guard !isCapturingMeeting, !isProcessingMedia, !state.isBusy, recordingRequest == nil, !isSavingHistory,
              !isFinishingDelivery else { throw CleanupError.busy }
        isMaintainingData = true
        maintenanceReason = reason
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        resetTask?.cancel()
        audioRevision += 1
    }

    public func endDataMaintenance() {
        isMaintainingData = false
        maintenanceReason = nil
    }

    /// Delivered dictations still saving history or restoring the clipboard.
    public var hasPendingDelivery: Bool { isFinishingDelivery || isSavingHistory || inserter.hasPendingClipboardRestoration }

    /// Waits for delivered dictations to reach history. Quit passes
    /// `flushClipboard` to restore the displaced clipboard without the delay;
    /// delivery is already confirmed, so the receiver has read the transcript.
    public func finishPendingDelivery(flushClipboard: Bool = false) async {
        await inserter.finishClipboardRestoration(immediately: flushClipboard)
        while let tail = deliveryTail { await tail.value }
        if let historySaveTask { await historySaveTask.value }
    }

    public func prepareDataRemoval(_ scope: DataCleanupScope) async throws {
        guard isMaintainingData else { throw CleanupError.busy }
        if scope == .history {
            // Pending text must not reappear on Save Retry. Retain its audio as
            // a detached asset before discarding the pending transcript.
            while let pending = unsavedHistory.first {
                if let samples = pending.samples, !samples.isEmpty {
                    guard let history else { throw CleanupError.storageUnavailable }
                    _ = try await Task.detached {
                        try history.saveRecording(samples: samples, createdAt: pending.record.createdAt)
                    }.value
                }
                unsavedHistory.removeFirst()
            }
            recoveries = recoveries.map { saved in
                var saved = saved
                saved.context = .empty; saved.target = nil; saved.reviewOnly = true
                return saved
            }
        } else if scope.removesHistory {
            unsavedHistory = []
        } else {
            unsavedHistory = unsavedHistory.map { ($0.record, nil) }
        }
        if scope.removesAudio { recoveries = []; retryingRecovery = nil }
        if scope.removesHistory {
            lastOutcome = nil; reviewOutcome = nil; lastIssue = nil; historyStorageError = nil
        }
        audioStorageError = nil
        stopPreview()
        levelHistory = []
    }

    public func closeHistoryForReset() async throws {
        guard isMaintainingData else { throw CleanupError.busy }
        if let history { try await Task.detached { try history.close() }.value }
        historyStore = nil
    }

    // MARK: - Processing

    private func process(samples: [Float], seconds: Double, context: AppContext, target: InsertionTarget?, token: UUID,
                         snapshot: RecordingSnapshot, reviewOnly: Bool = false, delivery: DeliveryPolicy = .normal) async {
        guard isCurrent(token) else { return }
        let processingStarted = ProcessInfo.processInfo.systemUptime
        let stopRequested = stopRequestedAt
        var timings = DictationTimings()
        defer {
            discardRefinementPreparation(for: token)
            releaseSpeechSessionPin(for: token)
            Self.log.notice("processing timing totalMs=\(Self.elapsed(since: processingStarted)) preparationWaitMs=\(timings.preparationWaitMs) refinementRequestMs=\(timings.refinementRequestMs) postProcessingMs=\(timings.postProcessingMs) deliveryMs=\(timings.deliveryMs) historyMs=\(timings.historyMs) stopToDeliveryMs=\(timings.stopToDeliveryMs ?? -1)")
        }
        // Muted/digital-silence recordings contain no speech. Some recognizers
        // hallucinate on them; never let that text reach delivery or history.
        // Use exact silence, not a volume threshold that could reject quiet speech.
        guard samples.contains(where: { $0 != 0 }) else {
            resolveRecovery(for: token)
            lastIssue = nil
            set(.idle)
            return
        }
        let output = snapshot.output
        let entries = snapshot.dictionary
        let asrConfig = snapshot.asr
        let llmConfig = snapshot.llm
        let profile = snapshot.profile
        let baseRules = snapshot.baseRules
        let family = AppFamily.classify(context)
        var context = context
        if snapshot.useAppContext && context.recentDictations.isEmpty && stopRequested == nil {
            context.recentDictations = await prefetchRecentFinals(appBundleId: context.bundleId).finals(for: context.bundleId)
            guard isCurrent(token) else { return }
        }

        // 1. ASR
        let transcript: Transcript
        do {
            if let reason = profile.speechModel?.unavailableReason {
                throw RecordingPrerequisiteError(reason)
            }
            let language = try SpeechLanguagePolicy.resolve(asrConfig)
            try SpeechInputLimits.validate(sampleCount: samples.count, for: asrConfig.kind)
            startRefinementPreparation(context: context, snapshot: snapshot, token: token)
            let hints = TranscriptionHints(
                language: language.language,
                vocabulary: DictionaryPostProcessor.vocabulary(entries),
                chineseScript: asrConfig.chineseScript
            )
            transcript = try await factory.transcribe(samples, hints: hints, config: asrConfig) { @MainActor [weak self] in
                guard let self, self.isCurrent(token) else { return }
                self.set(.preparingModel)
            }
        } catch {
            guard isCurrent(token) else { return }
            let message = String(localized: "Transcription failed: \(error.localizedDescription) Captured audio is kept for retry.", bundle: .module)
            let retried = retryingRecovery?.token == token ? retryingRecovery?.id : nil
            retryingRecovery = nil
            retain(samples, context: context, target: target, reviewOnly: reviewOnly, output: output, issue: message, replacing: retried)
            fail(message, openRecovery: !reviewOnly)
            return
        }
        guard isCurrent(token) else { return }
        refinementPreparation?.prefixTask?.cancel()
        lastIssue = nil
        guard !transcript.isEmpty else {
            resolveRecovery(for: token)
            set(.idle)
            return
        }

        // 2. LLM (best effort)
        var refined = transcript.text
        var llmMs = 0
        var llmEngine: String?
        var promptVersion: String?
        var skipReason: String?
        var llmError: String?
        var llmRejected = false

        let wordCount = Self.approximateWordCount(transcript.text)
        if !profile.usesLLM {
            skipReason = "\(profile.name): no LLM"
        } else if wordCount < llmConfig.minWordsForLLM && !context.hasSelection {
            skipReason = "short utterance (\(wordCount) words)"
        } else if llmConfig.kind != .none {
            set(.refining)
            let request = RefineRequest(
                transcript: transcript.text,
                profile: profile,
                baseRules: baseRules,
                context: context,
                family: family,
                dictionary: entries,
                chineseScript: asrConfig.chineseScript
            )
            let refinementStarted = ProcessInfo.processInfo.systemUptime
            let preparation = refinementPreparation
            let attempt = RefinementAttempt()
            do {
                let timeout = llmConfig.kind.isCLI ? max(60, llmConfig.timeoutSeconds) : llmConfig.timeoutSeconds
                let result = try await OperationDeadline.run(seconds: timeout) { @MainActor [self] in
                    guard isCurrent(token) else { throw CancellationError() }
                    guard let task = preparation?.task else { throw RefinerError.invalidResponse }
                    let refiner = try await task.value
                    preparation?.prefixTask?.cancel()
                    try Task.checkCancellation()
                    guard isCurrent(token) else { throw CancellationError() }
                    attempt.preparationWaitMs = Self.elapsed(since: refinementStarted)
                    let requestStarted = ProcessInfo.processInfo.systemUptime
                    attempt.requestStarted = requestStarted
                    defer {
                        attempt.requestMs = Self.elapsed(since: requestStarted)
                        attempt.requestFinished = true
                    }
                    return try await refiner.refine(request)
                }
                guard isCurrent(token) else { return }
                if let served = result.servedBy { onLLMUsed?(served, llmConfig) }
                let allowsLanguageChange = !profile.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || context.hasSelection
                if let violation = RefinementFidelity.violation(output: result.text, transcript: transcript.text,
                                                                recentDictations: context.recentDictations,
                                                                allowsLanguageChange: allowsLanguageChange) {
                    Self.log.notice("refinement rejected: \(String(describing: violation), privacy: .public) engine=\(result.engine, privacy: .public)")
                    llmError = violation.message
                    llmRejected = true
                    skipReason = "LLM output rejected, using raw transcript"
                } else {
                    refined = result.text
                    llmEngine = result.engine
                    promptVersion = result.promptVersion
                }
            } catch {
                llmError = error.localizedDescription
                skipReason = "LLM failed, using raw transcript"
            }
            llmMs = Int((ProcessInfo.processInfo.systemUptime - refinementStarted) * 1000)
            timings.preparationWaitMs = attempt.requestStarted == nil ? llmMs : attempt.preparationWaitMs
            timings.refinementRequestMs = attempt.requestFinished ? attempt.requestMs : attempt.requestStarted.map { Self.elapsed(since: $0) } ?? 0
            timings.refinerSetupMs = preparation?.setupDuration ?? 0
            timings.modelPreparationMs = preparation?.modelDuration ?? 0
            timings.cliWarmupMs = preparation?.cliDuration ?? 0
            timings.promptPrefixMs = preparation?.prefixDuration ?? 0
            Self.log.notice("refinement timing totalMs=\(llmMs) setupMs=\(timings.refinerSetupMs) modelPreparationMs=\(timings.modelPreparationMs) cliWarmupMs=\(timings.cliWarmupMs) promptPrefixMs=\(timings.promptPrefixMs) preparationWaitMs=\(timings.preparationWaitMs) requestMs=\(timings.refinementRequestMs) engine=\(llmConfig.engineLabel, privacy: .public)")
        } else {
            skipReason = "LLM off"
        }
        guard isCurrent(token) else { return }

        // 3. Script normalisation, then the dictionary always has the last word.
        let postStarted = ProcessInfo.processInfo.systemUptime
        let normalised = ChineseScriptConverter.convert(refined, to: asrConfig.chineseScript)
        let final = DictionaryPostProcessor.apply(normalised, entries: entries)
        timings.postProcessingMs = Self.elapsed(since: postStarted)

        if reviewOnly {
            timings.processingMs = Self.elapsed(since: processingStarted)
            reviewOutcome = DictationOutcome(raw: transcript.text, refined: refined, final: final,
                asrMs: transcript.latencyMs, llmMs: llmMs, llmSkippedReason: skipReason, timings: timings)
            resolveRecovery(for: token)
            lastIssue = llmError.map { String(localized: "Refinement failed; the original transcript is shown.", bundle: .module) + " " + $0 }
            set(.idle)
            return
        }

        // 4. Deliver once. A script can have external side effects, so never retry it
        // or fall back to pasting when its completion is uncertain.
        set(.inserting)
        let deliveryStarted = ProcessInfo.processInfo.systemUptime
        var notice: String?
        var noticeRequiresAttention = true
        var deliveryError: String?
        var inserted = false
        var outputSucceeded = false
        var sentUnverified = false
        var reportedDelivery = false
        let reportDelivery: () -> Void = { [weak self] in
            guard let self, self.isCurrent(token), !reportedDelivery else { return }
            reportedDelivery = true
            if let stopRequested { timings.stopToDeliveryMs = Self.elapsed(since: stopRequested) }
            self.onOutputDelivered?()
        }
        if insertionEnabled, delivery == .copyOnly {
            // Neither a paste nor the recording's saved script: copy for the user.
            let result = inserter.copyOnly(final, notice: String(localized: "Retried text copied. Paste it where you want it.", bundle: .module),
                                           requiresAttention: false)
            notice = result.notice
            noticeRequiresAttention = result.noticeRequiresAttention
            if result.noticeRequiresAttention { deliveryError = result.notice }
        } else if insertionEnabled {
            switch output.destination {
            case .cursor:
                let result: InsertionResult
                if delivery == .practice {
                    result = practiceTarget?.insertDictation(final) == true
                        ? InsertionResult(method: .practiceEditor, notice: nil)
                        : inserter.copyOnly(final, notice: String(localized: "Copied to clipboard", bundle: .module), requiresAttention: false)
                } else if let insertText { result = await insertText(final, output.insertionMethod, target) }
                else {
                    result = await inserter.insert(final, method: output.insertionMethod, target: target,
                                                   allowsUnconfirmedPaste: delivery != .retry,
                                                   onDelivered: reportDelivery)
                }
                sentUnverified = result.delivery == .sentUnverified
                // `inserted` records only confirmed text. A paste sent to a
                // validated caretless editor succeeded without confirmation.
                inserted = result.didInsert
                outputSucceeded = result.wasSent
                notice = result.notice
                noticeRequiresAttention = result.noticeRequiresAttention
                if !result.wasSent, result.noticeRequiresAttention { deliveryError = result.notice }
            case .script:
                do {
                    try await sendScript(final, output.scriptPath)
                    outputSucceeded = true
                } catch {
                    deliveryError = String(localized: "Script delivery failed or was interrupted. It may already have acted; it was not retried. Your text is kept in History.", bundle: .module) + " " + error.localizedDescription
                    notice = deliveryError
                }
            }
        }
        if outputSucceeded { reportDelivery() }
        timings.deliveryMs = Self.elapsed(since: deliveryStarted)
        if llmError != nil, notice == nil {
            let reason = llmRejected ? String(localized: "Refinement didn't match your speech", bundle: .module) : String(localized: "Refinement unavailable", bundle: .module)
            notice = outputSucceeded
                ? (output.destination == .script ? String(localized: "\(reason); raw text sent to script.", bundle: .module)
                    : sentUnverified ? String(localized: "\(reason); raw text pasted.", bundle: .module)
                    : String(localized: "\(reason); raw text inserted.", bundle: .module))
                : String(localized: "\(reason); raw text is available in History.", bundle: .module)
        }

        // 5. History. Delivery has finished, so this session releases the
        // pipeline before persistence: the next shortcut press can record at
        // once. Saving and the outcome continue in a tail that keeps their
        // order and that quit and data maintenance wait for.
        let record = DictationRecord(
            appBundleId: context.bundleId,
            appName: context.appName,
            windowTitle: context.windowTitle,
            url: context.url,
            mode: profile.name,
            family: family.rawValue,
            rawTranscript: transcript.text,
            refinedText: refined,
            finalText: final,
            language: transcript.language,
            asrEngine: transcript.engine,
            llmEngine: llmEngine,
            promptVersion: promptVersion,
            audioSeconds: seconds,
            asrMs: transcript.latencyMs,
            llmMs: llmMs,
            inserted: inserted,
            error: (llmError != nil || deliveryError != nil) ? [llmError, deliveryError].compactMap { $0 }.joined(separator: "\n") : nil,
            outputDestination: insertionEnabled ? output.destination.rawValue : nil,
            outputSucceeded: insertionEnabled ? outputSucceeded : nil
        )
        // Delivered text always reaches history, whatever happens next.
        let savesHistory = history != nil || historyDirectory != nil
        if savesHistory {
            // Held in memory first: a failed save stays visible and retryable.
            unsavedHistory.append((record, settings.audioRetention == .off ? nil : samples))
        }
        // The result is delivered and held for History: only now may a retry
        // release the kept audio it was processing.
        resolveRecovery(for: token)
        discardRefinementPreparation(for: token)
        let historyStarted = ProcessInfo.processInfo.systemUptime
        let previousTail = deliveryTail
        let tailID = UUID()
        deliveryTailID = tailID
        isFinishingDelivery = true
        deliveryTail = Task { @MainActor [timings, refined, llmMs, skipReason] in
            var timings = timings
            await previousTail?.value
            if savesHistory { await self.retryHistorySave() }
            timings.historyMs = Self.elapsed(since: historyStarted)
            timings.processingMs = Self.elapsed(since: processingStarted)
            let outcome = DictationOutcome(
                raw: transcript.text, refined: refined, final: final,
                asrMs: transcript.latencyMs, llmMs: llmMs, llmSkippedReason: skipReason, timings: timings
            )
            Self.log.notice("delivery tail historyMs=\(timings.historyMs) processingMs=\(timings.processingMs)")
            self.lastOutcome = outcome
            self.onOutcome?(outcome)
            if self.deliveryTailID == tailID {
                self.deliveryTail = nil
                self.isFinishingDelivery = false
            }
        }
        if let notice {
            lastIssue = notice
            set(.notice(notice, requiresAttention: noticeRequiresAttention))
            resetLater(after: 3)
        } else {
            lastIssue = nil
            set(.idle)
        }
    }

    // MARK: - Helpers

    /// Earlier dictations for `<recent_terms>` and the fidelity repeat check.
    /// Delivered dictations the delivery tail has not saved yet are snapshotted
    /// before saved rows are read off the main actor: a record saved in between
    /// is found in the database, and one saved earlier appears only once.
    private func prefetchRecentFinals(appBundleId: String?) -> RecentFinalsPrefetch {
        let pending = unsavedHistory.map(\.record)
        let store = history
        let saved = Task.detached(priority: .userInitiated) { () -> [DictationRecord] in
            // Without a known destination, read every app's recent rows and filter later.
            (try? store?.recentRecords(appBundleId: appBundleId, limit: appBundleId == nil ? 200 : HistoryStore.recentFinalsLimit)) ?? []
        }
        return RecentFinalsPrefetch(pending: pending, saved: saved)
    }

    private struct RecentFinalsPrefetch {
        let pending: [DictationRecord]
        let saved: Task<[DictationRecord], Never>

        func finals(for appBundleId: String?) async -> [String] {
            HistoryStore.recentFinals(saved: await saved.value, pending: pending, appBundleId: appBundleId)
        }
    }

    private func isCurrent(_ token: UUID) -> Bool { generation == token && !Task.isCancelled }

    private func set(_ new: PipelineState) {
        resetTask?.cancel()
        resetTask = nil
        state = new
        onStateChange?(new)
    }

    /// `openRecovery` shows Home when this failure kept audio for retry.
    private func fail(_ message: String, openRecovery: Bool = false) {
        lastIssue = message
        set(.failed(message))
        if openRecovery { onRecordingBlocked?() }
        resetLater(after: 4)
    }

    /// An earlier timer must not clear a newer failure or notice.
    private func resetLater(after seconds: Double) {
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.set(.idle)
        }
    }

    /// Words for Latin scripts, characters for CJK. Good enough for a threshold.
    nonisolated static func approximateWordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isCJK = (0x4E00...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
            if isCJK {
                count += 1
                inWord = false
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if !inWord { count += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return count
    }
}
