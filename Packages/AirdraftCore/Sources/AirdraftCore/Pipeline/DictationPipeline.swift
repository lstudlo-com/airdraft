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
    /// Shortcut acceptance to the first captured audio buffer; nil for
    /// file, review and retry processing.
    public var pressToCaptureMs: Int?
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
///
/// This file declares the pipeline's state and shared helpers. Each stage lives
/// in an extension: `+Recording` (startup, capture and cancellation),
/// `+Processing` (ASR, refinement and post-processing), `+Delivery` (output and
/// the history tail), `+Recovery` (kept recordings, retries and review) and
/// `+History` (persistence and data maintenance). Members those files share are
/// internal to the module; the public API is unchanged.
@MainActor
@Observable
public final class DictationPipeline {
    public internal(set) var state: PipelineState = .idle
    public internal(set) var lastIssue: String?
    /// Failed recordings waiting for explicit retry or discard, oldest first.
    public var pendingRecordings: [PendingRecording] { recoveries.map(\.info) }
    public var hasRecoverableRecording: Bool { !recoveries.isEmpty }
    /// The newest dictation recovery: Home and the menu act on this one.
    public var latestPendingDictation: PendingRecording? { recoveries.last { !$0.info.isReview }?.info }
    public internal(set) var historyStorageError: String?
    public internal(set) var isSavingHistory = false
    /// A delivered dictation is still saving history and publishing its outcome.
    /// The next recording may already run; quit and data maintenance wait.
    public internal(set) var isFinishingDelivery = false
    var deliveryTail: Task<Void, Never>?
    var deliveryTailID: UUID?
    var historySaveTask: Task<Void, Never>?
    public internal(set) var isMaintainingData = false
    var maintenanceReason: String?
    public var isProcessingMedia = false
    public var isCapturingMeeting = false
    public internal(set) var previewText = ""
    public internal(set) var previewIssue: String?
    public internal(set) var previewEnabledForRecording = false
    var previewSession: (any SpeechPreviewSession)?
    public typealias PreviewBuilder = @Sendable (String, @escaping @Sendable (String) -> Void, @escaping @Sendable (String) -> Void) -> any SpeechPreviewSession
    let previewBuilder: PreviewBuilder
    public internal(set) var reviewOutcome: DictationOutcome?
    public internal(set) var audioStorageError: String?
    public internal(set) var audioRevision = 0
    var reviewGeneration: UUID?
    struct OutputSnapshot: Sendable, Equatable {
        var destination: TextOutputDestination
        var scriptPath: String
        var insertionMethod: InsertionMethod
    }
    struct RecordingSnapshot: Sendable, Equatable {
        let asr: ASRConfig
        let profile: RefinementProfile
        let llm: LLMConfig
        let microphone: MicrophonePreference
        let output: OutputSnapshot
        let baseRules: String
        let dictionary: [DictionaryEntry]
        let useAppContext: Bool
    }
    var recordingAtStart: RecordingSnapshot?
    let sendScript: @Sendable (String, String) async throws -> Void
    struct Recovery {
        var info: PendingRecording
        let samples: [Float]
        var context: AppContext
        var target: InsertionTarget?
        var reviewOnly: Bool
        let output: OutputSnapshot
    }
    var recoveries: [Recovery] = []
    /// The recovery an explicit retry is processing, keyed by its generation.
    var retryingRecovery: (token: UUID, id: UUID)?
    var unsavedHistory: [(record: DictationRecord, samples: [Float]?)] = []
    let historyDirectory: URL?
    public internal(set) var historyStore: HistoryStore?
    public internal(set) var lastOutcome: DictationOutcome?
    /// Most recent input levels (0...1), oldest first. Drives the HUD waveform.
    public internal(set) var levelHistory: [Float] = []
    public static let levelHistoryLength = 22
    public internal(set) var recordingStartedAt: Date?
    public internal(set) var lastRecordingDuration: TimeInterval = 0

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

    let settings: AppSettings
    let dictionary: DictionaryStore
    let profiles: ProfileStore
    var history: HistoryStore? { historyStore }
    let factory: EngineFactory
    let recorder: any AudioRecording
    let contextReader: AppContextReader
    let insertText: ((String, InsertionMethod, InsertionTarget?) async -> InsertionResult)?
    let inserter: TextInserter

    var generation = UUID()
    var releaseTask: Task<Void, Never>?
    @MainActor final class RefinementPreparation {
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
    @MainActor final class RefinementAttempt {
        var preparationWaitMs = 0
        var requestStarted: TimeInterval?
        var requestMs = 0
        var requestFinished = false
    }
    var refinementPreparation: RefinementPreparation?
    /// Keeps the session's local speech engine out of idle unloading.
    var speechSessionPin: (token: UUID, pin: UUID)?
    var stopRequestedAt: TimeInterval?
    /// One recording request's press-to-capture measurement.
    struct CaptureLatency {
        let token: UUID
        let acceptedAt: TimeInterval
        var pressToCaptureMs: Int?
        var engineID: String?
    }
    var captureLatency: CaptureLatency?
    /// The session whose capture started before its recording state, while the
    /// destination and app context are being read.
    var startingCapture: UUID?
    var insertionTargetAtStart: InsertionTarget?
    /// The recording was started for onboarding practice's own editor.
    var practiceDeliveryAtStart = false
    /// How cursor delivery treats one processing run.
    enum DeliveryPolicy {
        /// Paste into the captured target; a caretless editor may be sent unverified.
        case normal
        /// An explicit retry: verified targets only, otherwise copy.
        case retry
        /// Onboarding practice's own editor.
        case practice
        /// Retries during practice never paste or run a script.
        case copyOnly
    }
    var contextAtStart: AppContext = .empty
    var processingTask: Task<Void, Never>?
    /// Returns a failure or notice to idle; replaced whenever the state changes.
    var resetTask: Task<Void, Never>?
    static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "pipeline")
    var autoStopTask: Task<Void, Never>?
    var stopping = false
    var recordingRequest: Task<Void, Never>?
    var recordingRequestID = UUID()
    let recordingPreflight: (@MainActor (ASRConfig, LLMConfig, Bool, MicrophonePreference, Bool) async throws -> Void)?
    let accessCheck: @MainActor () async throws -> Void
    public var speechConfig: ASRConfig { settings.speechConfig(for: profiles.activeProfile) }
    let requestMicrophoneAccess: @Sendable () async -> Bool

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

    public var isRecording: Bool { state == .recording }
    /// Work outside dictation that excludes a new recording.
    var exclusiveWorkReason: String? {
        if isMaintainingData {
            return maintenanceReason ?? String(localized: "Recording is unavailable while Airdraft manages its data.", bundle: .module)
        }
        if isCapturingMeeting { return String(localized: "Stop the meeting recording before dictating.", bundle: .module) }
        if isProcessingMedia { return String(localized: "Wait for the media transcription to finish before dictating.", bundle: .module) }
        return nil
    }
    public var isBusy: Bool { isMaintainingData || isProcessingMedia || isCapturingMeeting || state.isBusy || recordingRequest != nil }

    public func dismissIssue() { lastIssue = nil }

    // MARK: - Shared helpers

    static func elapsed(since start: TimeInterval) -> Int {
        Int(max(0, ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    func isCurrent(_ token: UUID) -> Bool { generation == token && !Task.isCancelled }

    func set(_ new: PipelineState) {
        resetTask?.cancel()
        resetTask = nil
        state = new
        onStateChange?(new)
    }

    /// `openRecovery` shows Home when this failure kept audio for retry.
    func fail(_ message: String, openRecovery: Bool = false) {
        lastIssue = message
        set(.failed(message))
        if openRecovery { onRecordingBlocked?() }
        resetLater(after: 4)
    }

    /// An earlier timer must not clear a newer failure or notice.
    func resetLater(after seconds: Double) {
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
