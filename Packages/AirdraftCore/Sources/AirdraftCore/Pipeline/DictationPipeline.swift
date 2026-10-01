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
    case notice(String)

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
}

/// Record -> transcribe -> (refine) -> dictionary -> insert -> history.
/// The LLM is best-effort: any failure or timeout falls back to the raw
/// transcript so dictation never blocks on a slow model.
@MainActor
@Observable
public final class DictationPipeline {
    public private(set) var state: PipelineState = .idle
    public private(set) var lastIssue: String?
    public private(set) var hasRecoverableRecording = false
    public private(set) var historyStorageError: String?
    public private(set) var isSavingHistory = false
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
    private var outputAtStart: OutputSnapshot?
    private let sendScript: @Sendable (String, String) async throws -> Void
    private var recovery: (samples: [Float], seconds: Double, context: AppContext, target: InsertionTarget?, reviewOnly: Bool, output: OutputSnapshot)?
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
    /// Paste delivery means the command was posted, not that the editor acknowledged it.
    public var onOutputDelivered: (() -> Void)?
    /// Called with the LLM instance id that served a refinement.
    public var onLLMUsed: ((String, LLMConfig) -> Void)?
    /// Returns true when the refinement model must be loaded before use.
    public var llmNeedsLoad: ((LLMConfig) async -> Bool)?
    /// Loads the refinement model (called only when `llmNeedsLoad` said so).
    public var loadLLM: ((LLMConfig) async -> Void)?
    /// When false the final text is not inserted anywhere (self-tests).
    public var insertionEnabled = true

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
    private var warmTask: Task<Void, Never>?
    private var insertionTargetAtStart: InsertionTarget?
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
    private var asrAtStart: ASRConfig?
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
        if history == nil && historyDirectory != nil { historyStorageError = "History is unavailable. Dictations stay in memory until saved. Retry saving or check the data folder." }
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
                self.cancel()
                if !samples.isEmpty { self.retain(samples, context: context, target: target) }
                self.fail(reason.localizedDescription + (samples.isEmpty ? "" : " Captured audio is kept for retry."))
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
    public var isBusy: Bool { state.isBusy || recordingRequest != nil }

    // MARK: - Control

    public func toggle() {
        if recordingRequest != nil && !isRecording { cancel() }
        else if isRecording { stopAndProcess() } else { startRecording() }
    }

    public func startRecording() {
        guard !state.isBusy, recordingRequest == nil else { return }
        guard !hasRecoverableRecording else {
            fail("A recording is waiting for retry. Open Airdraft to retry or discard it before recording again.")
            return
        }
        let token = UUID()
        recordingRequestID = token
        generation = token
        recordingRequest = Task {
            await beginRecording(token: token)
            if recordingRequestID == token { recordingRequest = nil }
        }
    }

    /// App Intents use the same startup task and only report success once capture begins.
    public func startFromAutomation() async throws {
        if isRecording { return }
        guard !isBusy else { throw RecordingPrerequisiteError("Airdraft is already starting or processing a recording.") }
        guard !hasRecoverableRecording else { throw RecordingPrerequisiteError("Retry or discard the saved recording in Airdraft first.") }
        try Task.checkCancellation()
        startRecording()
        let token = recordingRequestID
        guard let request = recordingRequest else {
            throw RecordingPrerequisiteError(lastIssue ?? "Recording could not start.")
        }
        do {
            try await OperationDeadline.run(seconds: 15) { await request.value }
            try Task.checkCancellation()
        } catch {
            if recordingRequestID == token, generation == token { cancel() }
            if case RefinerError.timeout = error {
                throw RecordingPrerequisiteError("Recording startup timed out. Open Airdraft to check the selected model and permissions.")
            }
            throw error
        }
        guard generation == token else { throw CancellationError() }
        guard isRecording else { throw RecordingPrerequisiteError(lastIssue ?? "Recording did not start.") }
    }

    public func stopFromAutomation() throws {
        guard isRecording || recordingRequest != nil || !isBusy else {
            throw RecordingPrerequisiteError("Airdraft is already processing a recording.")
        }
        stopAndProcess()
    }

    public func cancelFromAutomation() throws {
        guard state != .inserting else {
            throw RecordingPrerequisiteError("Text delivery has started and cannot be cancelled safely.")
        }
        cancel()
    }

    private func selectedOutput() -> OutputSnapshot {
        OutputSnapshot(destination: settings.outputDestination, scriptPath: settings.outputScriptPath,
                       insertionMethod: settings.insertionMethod)
    }

    private func beginRecording(token: UUID) async {
        guard isCurrent(token) else { return }
        let asr = settings.asr
        let llm = settings.llm
        let profile = profiles.activeProfile
        let microphone = settings.microphone
        let output = selectedOutput()
        let needsInsertion = insertionEnabled && output.destination == .cursor
        do {
            try await accessCheck()
            guard isCurrent(token) else { return }
            if insertionEnabled, output.destination == .script, let reason = ScriptDelivery.unavailableReason(path: output.scriptPath) {
                throw RecordingPrerequisiteError("Recording did not start. " + reason)
            }
            if let recordingPreflight {
                try await recordingPreflight(asr, llm, profile.usesLLM, microphone, needsInsertion)
            } else {
                try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: profile.usesLLM,
                                                 microphone: microphone, insertionEnabled: needsInsertion)
                if asr.kind.isLocal {
                    let engine = await factory.transcriber(for: asr)
                    guard await engine.isReady() else {
                        throw RecordingPrerequisiteError("Recording did not start. The speech model is not ready. Load it in Models and wait for Loaded before dictating.")
                    }
                }
            }
            guard isCurrent(token) else { return }
            guard settings.asr == asr, settings.llm == llm, profiles.activeProfile == profile,
                  settings.microphone == microphone, selectedOutput() == output else {
                throw RecordingPrerequisiteError("Recording did not start because setup changed. Try your shortcut again.")
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
            fail("Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.")
            onRecordingBlocked?()
            return
        }
        guard settings.asr == asr, settings.llm == llm, profiles.activeProfile == profile,
              settings.microphone == microphone, selectedOutput() == output else {
            fail("Recording did not start because setup changed. Try your shortcut again.")
            onRecordingBlocked?()
            return
        }
        let insertionTarget = needsInsertion ? await inserter.captureTarget() : nil
        guard isCurrent(token) else { return }
        guard settings.asr == asr, settings.llm == llm, profiles.activeProfile == profile,
              settings.microphone == microphone, selectedOutput() == output else {
            fail("Recording did not start because setup changed. Try your shortcut again.")
            onRecordingBlocked?()
            return
        }
        asrAtStart = asr
        outputAtStart = output
        insertionTargetAtStart = insertionTarget
        contextAtStart = settings.useAppContext ? contextReader.read() : .empty
        wireRecorder(for: token)
        startPreview(for: token)
        do {
            try recorder.start(microphone: microphone)
        } catch {
            stopPreview()
            fail("Could not start recording: \(error.localizedDescription)")
            onRecordingBlocked?()
            return
        }
        recordingStartedAt = Date()
        levelHistory = []
        set(.recording)
        prewarmRefiner(context: contextAtStart)

        let limit = SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: settings.asr.kind)
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
        guard state == .recording else { return }
        autoStopTask?.cancel()
        releaseTask?.cancel()
        stopping = false
        stopPreview()
        let samples = recorder.stop()
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        recordingStartedAt = nil

        guard seconds >= 0.3 else {
            set(.idle)
            return
        }
        set(.transcribing)
        let ctx = contextAtStart
        let token = generation
        let target = insertionTargetAtStart
        processingTask = Task { await process(samples: samples, seconds: seconds, context: ctx, target: target, token: token) }
    }

    /// Runs 16 kHz mono samples through transcription, refinement, dictionary and
    /// history exactly like a recording would. Used by self-tests and the CLI.
    public func processSamples(_ samples: [Float], context: AppContext = .empty) {
        guard !isBusy else { return }
        generation = UUID()
        asrAtStart = nil
        outputAtStart = selectedOutput()
        let token = generation
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        levelHistory = []
        set(.transcribing)
        processingTask = Task {
            do {
                try await accessCheck()
                guard isCurrent(token) else { return }
                prewarmRefiner(context: context)
                await process(samples: samples, seconds: seconds, context: context, target: nil, token: token)
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
        guard !isBusy, !hasRecoverableRecording, let history else { return }
        generation = UUID()
        let token = generation
        reviewGeneration = token
        reviewOutcome = nil
        lastIssue = nil
        asrAtStart = nil
        set(.transcribing)
        processingTask = Task {
            do {
                try await accessCheck()
                guard isCurrent(token) else { return }
                let samples = try await Task.detached { try history.audioSamples(for: record) }.value
                guard isCurrent(token) else { return }
                await process(samples: samples, seconds: Double(samples.count) / AudioRecorder.sampleRate,
                              context: .empty, target: nil, token: token, reviewOnly: true)
            } catch {
                guard isCurrent(token) else { return }
                fail("Recording could not be opened. " + error.localizedDescription)
                if error is LicenseError { onRecordingBlocked?() }
            }
        }
    }

    public func dismissReview() {
        if reviewGeneration == generation {
            cancel()
            reviewOutcome = nil
            reviewGeneration = nil
            lastIssue = nil
        }
    }

    public func pruneSavedAudio() async {
        guard let history else { return }
        let cutoff = settings.audioRetention.cutoff()
        do {
            try await Task.detached { try history.pruneAudio(olderThan: cutoff) }.value
            audioStorageError = nil
            audioRevision += 1
        } catch { audioStorageError = "Saved audio could not be removed. " + error.localizedDescription }
    }

    /// A CLI refiner takes seconds to start a session, so start it while the user
    /// is still speaking. Only the system prompt is needed for that, and it is
    /// already known: it does not depend on what is said.
    private func prewarmRefiner(context: AppContext) {
        let config = settings.llm
        guard profiles.activeProfile.usesLLM, config.kind.cliTool != nil else { return }
        let request = RefineRequest(
            transcript: "",
            profile: profiles.activeProfile,
            baseRules: profiles.baseRules,
            context: context,
            family: AppFamily.classify(context),
            dictionary: dictionary.entries,
            chineseScript: settings.asr.chineseScript
        )
        let systemPrompt = PromptBuilder.systemPrompt(for: request)
        warmTask?.cancel()
        warmTask = Task { [factory] in
            guard !Task.isCancelled else { return }
            guard var refiner = await factory.refiner(for: config) as? CLIRefiner else { return }
            guard !Task.isCancelled else { return }
            refiner.warmSystemPrompt = systemPrompt
            await refiner.prewarm()
        }
    }

    public func cancel() {
        // Once a write begins, finish recording its outcome before accepting a new session.
        guard state != .inserting else { return }
        stopPreview()
        generation = UUID()
        recovery = nil
        hasRecoverableRecording = false
        releaseTask?.cancel()
        warmTask?.cancel()
        recordingRequestID = UUID()
        recordingRequest?.cancel()
        recordingRequest = nil
        stopping = false
        autoStopTask?.cancel()
        processingTask?.cancel()
        if recorder.isRecording { recorder.cancel() }
        recordingStartedAt = nil
        set(.idle)
    }

    public func dismissIssue() { lastIssue = nil }

    public func discardRecording() {
        guard !isBusy else { return }
        recovery = nil
        hasRecoverableRecording = false
        lastIssue = nil
        set(.idle)
    }

    public func retryRecording() {
        guard !isBusy, let recovery else { return }
        asrAtStart = nil
        generation = UUID()
        let token = generation
        outputAtStart = recovery.output
        if recovery.reviewOnly { reviewGeneration = token }
        set(.transcribing)
        processingTask = Task {
            await process(samples: recovery.samples, seconds: recovery.seconds,
                          context: recovery.context, target: recovery.target, token: token, reviewOnly: recovery.reviewOnly)
        }
    }

    private func retain(_ samples: [Float], context: AppContext, target: InsertionTarget?, reviewOnly: Bool = false, output: OutputSnapshot? = nil) {
        recovery = (samples, Double(samples.count) / AudioRecorder.sampleRate, context, target, reviewOnly, output ?? outputAtStart ?? selectedOutput())
        hasRecoverableRecording = true
    }

    public func retryHistorySave() async {
        guard !isSavingHistory else { return }
        isSavingHistory = true
        defer { isSavingHistory = false }
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
            historyStorageError = "History could not be saved. Your unsaved dictations remain in memory. " + error.localizedDescription
        }
    }

    // MARK: - Processing

    private func process(samples: [Float], seconds: Double, context: AppContext, target: InsertionTarget?, token: UUID, reviewOnly: Bool = false) async {
        guard isCurrent(token) else { return }
        // Muted/digital-silence recordings contain no speech. Some recognizers
        // hallucinate on them; never let that text reach delivery or history.
        // Use exact silence, not a volume threshold that could reject quiet speech.
        guard samples.contains(where: { $0 != 0 }) else {
            recovery = nil
            hasRecoverableRecording = false
            lastIssue = nil
            set(.idle)
            return
        }
        let output = outputAtStart ?? selectedOutput()
        let entries = dictionary.entries
        let asrConfig = asrAtStart ?? settings.asr
        let llmConfig = settings.llm
        let profile = profiles.activeProfile
        let baseRules = profiles.baseRules
        let family = AppFamily.classify(context)
        var context = context
        if settings.useAppContext && context.recentDictations.isEmpty {
            context.recentDictations = (try? history?.recentFinals(appBundleId: context.bundleId)) ?? []
        }

        // 1. ASR
        let transcript: Transcript
        do {
            try SpeechInputLimits.validate(sampleCount: samples.count, for: asrConfig.kind)
            let transcriber = await factory.transcriber(for: asrConfig)
            guard isCurrent(token) else { return }
            let ready = await transcriber.isReady()
            guard isCurrent(token) else { return }
            if !ready { set(.preparingModel) }
            let hints = TranscriptionHints(
                language: asrConfig.language.isEmpty ? nil : asrConfig.language,
                vocabulary: DictionaryPostProcessor.vocabulary(entries),
                chineseScript: asrConfig.chineseScript
            )
            transcript = try await factory.transcribe(samples, hints: hints, config: asrConfig)
        } catch {
            guard isCurrent(token) else { return }
            retain(samples, context: context, target: target, reviewOnly: reviewOnly, output: output)
            fail("Transcription failed: \(error.localizedDescription) Captured audio is kept for retry.")
            return
        }
        guard isCurrent(token) else { return }
        recovery = nil
        hasRecoverableRecording = false
        lastIssue = nil
        guard !transcript.isEmpty else {
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
            do {
                let timeout = llmConfig.kind.isCLI ? max(60, llmConfig.timeoutSeconds) : llmConfig.timeoutSeconds
                let result = try await OperationDeadline.run(seconds: timeout) { @MainActor [self] in
                    guard isCurrent(token) else { throw CancellationError() }
                    guard let refiner = await factory.refiner(for: llmConfig) else { throw RefinerError.invalidResponse }
                    try Task.checkCancellation()
                    if let needs = llmNeedsLoad, await needs(llmConfig) {
                        try Task.checkCancellation()
                        guard isCurrent(token) else { throw CancellationError() }
                        await loadLLM?(llmConfig)
                    }
                    try Task.checkCancellation()
                    guard isCurrent(token) else { throw CancellationError() }
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
                    llmMs = result.latencyMs
                    llmEngine = result.engine
                    promptVersion = result.promptVersion
                }
            } catch {
                llmError = error.localizedDescription
                skipReason = "LLM failed, using raw transcript"
            }
        } else {
            skipReason = "LLM off"
        }
        guard isCurrent(token) else { return }

        // 3. Script normalisation, then the dictionary always has the last word.
        let normalised = ChineseScriptConverter.convert(refined, to: asrConfig.chineseScript)
        let final = DictionaryPostProcessor.apply(normalised, entries: entries)

        if reviewOnly {
            reviewOutcome = DictationOutcome(raw: transcript.text, refined: refined, final: final,
                asrMs: transcript.latencyMs, llmMs: llmMs, llmSkippedReason: skipReason)
            lastIssue = llmError.map { "Refinement failed; the original transcript is shown. " + $0 }
            set(.idle)
            return
        }

        // 4. Deliver once. A script can have external side effects, so never retry it
        // or fall back to pasting when its completion is uncertain.
        set(.inserting)
        var notice: String?
        var deliveryError: String?
        var inserted = false
        var outputSucceeded = false
        var reportedDelivery = false
        let reportDelivery: () -> Void = { [weak self] in
            guard let self, self.isCurrent(token), !reportedDelivery else { return }
            reportedDelivery = true
            self.onOutputDelivered?()
        }
        if insertionEnabled {
            switch output.destination {
            case .cursor:
                let result: InsertionResult
                if let insertText { result = await insertText(final, output.insertionMethod, target) }
                else {
                    result = await inserter.insert(final, method: output.insertionMethod, target: target,
                                                   onDelivered: reportDelivery)
                }
                inserted = result.didInsert
                outputSucceeded = result.didInsert
                notice = result.notice
            case .script:
                do {
                    try await sendScript(final, output.scriptPath)
                    outputSucceeded = true
                } catch {
                    deliveryError = "Script delivery failed or was interrupted. It may already have acted; it was not retried. Your text is kept in History. " + error.localizedDescription
                    notice = deliveryError
                }
            }
        }
        if outputSucceeded { reportDelivery() }
        if llmError != nil, notice == nil {
            let reason = llmRejected ? "Refinement didn't match your speech" : "Refinement unavailable"
            notice = outputSucceeded
                ? (output.destination == .script ? "\(reason); raw text sent to script." : "\(reason); raw text inserted.")
                : "\(reason); raw text is available in History."
        }

        // 5. History
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
        if history != nil || historyDirectory != nil {
            unsavedHistory.append((record, settings.audioRetention == .off ? nil : samples))
            await retryHistorySave()
        }
        guard isCurrent(token) else { return }

        let outcome = DictationOutcome(
            raw: transcript.text, refined: refined, final: final,
            asrMs: transcript.latencyMs, llmMs: llmMs, llmSkippedReason: skipReason
        )
        lastOutcome = outcome
        onOutcome?(outcome)
        if let notice {
            lastIssue = notice
            set(.notice(notice))
            resetLater(after: 3)
        } else {
            lastIssue = nil
            set(.idle)
        }
    }

    // MARK: - Helpers

    private func isCurrent(_ token: UUID) -> Bool { generation == token && !Task.isCancelled }

    private func set(_ new: PipelineState) {
        resetTask?.cancel()
        resetTask = nil
        state = new
        onStateChange?(new)
    }

    private func fail(_ message: String) {
        lastIssue = message
        set(.failed(message))
        if hasRecoverableRecording && recovery?.reviewOnly != true { onRecordingBlocked?() }
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
