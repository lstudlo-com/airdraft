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
    private var recovery: (samples: [Float], seconds: Double, context: AppContext, target: InsertionTarget?)?
    private var unsavedHistory: [DictationRecord] = []
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
    /// Called with the LLM instance id that served a refinement.
    public var onLLMUsed: ((String) -> Void)?
    /// Returns true when the refinement model must be loaded before use.
    public var llmNeedsLoad: (() async -> Bool)?
    /// Loads the refinement model (called only when `llmNeedsLoad` said so).
    public var loadLLM: (() async -> Void)?
    /// When false the final text is not inserted anywhere (self-tests).
    public var insertionEnabled = true

    private let settings: AppSettings
    private let dictionary: DictionaryStore
    private let profiles: ProfileStore
    private var history: HistoryStore? { historyStore }
    private let factory: EngineFactory
    private let recorder: any AudioRecording
    private let contextReader: AppContextReader
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
        contextReader: AppContextReader? = nil,
        inserter: TextInserter? = nil,
        recordingPreflight: (@MainActor (ASRConfig, LLMConfig, Bool, MicrophonePreference, Bool) async throws -> Void)? = nil,
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
        self.contextReader = contextReader ?? AppContextReader()
        self.inserter = inserter ?? TextInserter()
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.recordingPreflight = recordingPreflight

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

    private func beginRecording(token: UUID) async {
        guard isCurrent(token) else { return }
        let asr = settings.asr
        let llm = settings.llm
        let microphone = settings.microphone
        do {
            if let recordingPreflight {
                try await recordingPreflight(asr, llm, profiles.activeProfile.usesLLM, microphone, insertionEnabled)
            } else {
                try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: profiles.activeProfile.usesLLM,
                                                 microphone: microphone, insertionEnabled: insertionEnabled)
                if asr.kind.isLocal {
                    let engine = await factory.transcriber(for: asr)
                    guard await engine.isReady() else {
                        throw RecordingPrerequisiteError("Recording did not start. The speech model is not ready. Load it in Models and wait for Loaded before dictating.")
                    }
                }
            }
            guard isCurrent(token) else { return }
            guard settings.asr == asr, settings.llm == llm, settings.microphone == microphone else {
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
            return
        }
        asrAtStart = asr
        insertionTargetAtStart = inserter.captureTarget()
        contextAtStart = settings.useAppContext ? contextReader.read() : .empty
        wireRecorder(for: token)
        do {
            try recorder.start(microphone: microphone)
        } catch {
            fail("Could not start recording: \(error.localizedDescription)")
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
        let token = generation
        prewarmRefiner(context: context)
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        levelHistory = []
        set(.transcribing)
        processingTask = Task { await process(samples: samples, seconds: seconds, context: context, target: nil, token: token) }
    }

    /// A CLI refiner takes seconds to start a session, so start it while the user
    /// is still speaking. Only the system prompt is needed for that, and it is
    /// already known: it does not depend on what is said.
    private func prewarmRefiner(context: AppContext) {
        let config = settings.llm
        guard config.kind.cliTool != nil else { return }
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
        set(.transcribing)
        processingTask = Task {
            await process(samples: recovery.samples, seconds: recovery.seconds,
                          context: recovery.context, target: recovery.target, token: token)
        }
    }

    private func retain(_ samples: [Float], context: AppContext, target: InsertionTarget?) {
        recovery = (samples, Double(samples.count) / AudioRecorder.sampleRate, context, target)
        hasRecoverableRecording = true
    }

    public func retryHistorySave() async {
        guard !isSavingHistory else { return }
        isSavingHistory = true
        defer { isSavingHistory = false }
        do {
            if historyStore == nil, let historyDirectory { historyStore = try HistoryStore(directory: historyDirectory) }
            guard let historyStore else { return }
            while let record = unsavedHistory.first {
                _ = try await Task.detached { try historyStore.save(record) }.value
                unsavedHistory.removeFirst()
            }
            historyStorageError = nil
        } catch {
            historyStorageError = "History could not be saved. Your unsaved dictations remain in memory. " + error.localizedDescription
        }
    }

    // MARK: - Processing

    private func process(samples: [Float], seconds: Double, context: AppContext, target: InsertionTarget?, token: UUID) async {
        guard isCurrent(token) else { return }
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
            retain(samples, context: context, target: target)
            fail("Transcription failed: \(error.localizedDescription) Captured audio is kept for retry.")
            return
        }
        guard isCurrent(token) else { return }
        recovery = nil
        hasRecoverableRecording = false
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
                    if let needs = llmNeedsLoad, await needs() {
                        try Task.checkCancellation()
                        guard isCurrent(token) else { throw CancellationError() }
                        await loadLLM?()
                    }
                    try Task.checkCancellation()
                    guard isCurrent(token) else { throw CancellationError() }
                    return try await refiner.refine(request)
                }
                guard isCurrent(token) else { return }
                if let served = result.servedBy { onLLMUsed?(served) }
                refined = result.text
                llmMs = result.latencyMs
                llmEngine = result.engine
                promptVersion = result.promptVersion
            } catch {
                llmError = error.localizedDescription
                skipReason = "LLM failed, inserted raw transcript"
            }
        } else {
            skipReason = "LLM off"
        }
        guard isCurrent(token) else { return }

        // 3. Script normalisation, then the dictionary always has the last word.
        let normalised = ChineseScriptConverter.convert(refined, to: asrConfig.chineseScript)
        let final = DictionaryPostProcessor.apply(normalised, entries: entries)

        // 4. Insert
        set(.inserting)
        var notice: String?
        let inserted: Bool
        if insertionEnabled {
            let result = await inserter.insert(final, method: settings.insertionMethod, target: target)
            inserted = result.didInsert
            notice = result.notice
        } else {
            inserted = false
        }
        if llmError != nil, notice == nil {
            notice = "LLM unavailable, raw text inserted"
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
            error: llmError
        )
        if history != nil || historyDirectory != nil {
            unsavedHistory.append(record)
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
        if hasRecoverableRecording { onRecordingBlocked?() }
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
