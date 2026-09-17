import Foundation
import Observation

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
    public private(set) var lastOutcome: DictationOutcome?
    /// Most recent input levels (0...1), oldest first. Drives the HUD waveform.
    public private(set) var levelHistory: [Float] = []
    public static let levelHistoryLength = 22
    public private(set) var recordingStartedAt: Date?
    public private(set) var lastRecordingDuration: TimeInterval = 0

    public var onStateChange: ((PipelineState) -> Void)?
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
    private let history: HistoryStore?
    private let factory: EngineFactory
    private let recorder: AudioRecorder
    private let contextReader: AppContextReader
    private let inserter: TextInserter

    private var contextAtStart: AppContext = .empty
    private var processingTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var stopping = false

    public init(
        settings: AppSettings,
        dictionary: DictionaryStore,
        profiles: ProfileStore,
        history: HistoryStore?,
        factory: EngineFactory,
        recorder: AudioRecorder = AudioRecorder(),
        contextReader: AppContextReader? = nil,
        inserter: TextInserter? = nil
    ) {
        self.settings = settings
        self.dictionary = dictionary
        self.profiles = profiles
        self.history = history
        self.factory = factory
        self.recorder = recorder
        self.contextReader = contextReader ?? AppContextReader()
        self.inserter = inserter ?? TextInserter()

        recorder.levelHandler = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.levelHistory.append(level)
                if self.levelHistory.count > Self.levelHistoryLength {
                    self.levelHistory.removeFirst(self.levelHistory.count - Self.levelHistoryLength)
                }
            }
        }
    }

    public var isRecording: Bool { state == .recording }

    // MARK: - Control

    public func toggle() {
        if isRecording { stopAndProcess() } else { startRecording() }
    }

    public func startRecording() {
        guard !state.isBusy else { return }
        Task { await beginRecording() }
    }

    private func beginRecording() async {
        guard await AudioRecorder.requestMicrophoneAccess() else {
            fail("Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.")
            return
        }
        contextAtStart = settings.useAppContext ? contextReader.read() : .empty
        do {
            try recorder.start()
        } catch {
            fail("Could not start recording: \(error.localizedDescription)")
            return
        }
        recordingStartedAt = Date()
        levelHistory = []
        set(.recording)
        prewarmRefiner(context: contextAtStart)

        let limit = settings.maxRecordingSeconds
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finishRecording() }
        }
    }

    /// Keep capturing briefly after the key is released: people let go while
    /// the last syllable is still sounding.
    public static let releaseGraceSeconds: Double = 0.35

    public func stopAndProcess() {
        guard state == .recording, !stopping else { return }
        stopping = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.releaseGraceSeconds))
            self.stopping = false
            self.finishRecording()
        }
    }

    private func finishRecording() {
        guard state == .recording else { return }
        autoStopTask?.cancel()
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
        processingTask = Task { await process(samples: samples, seconds: seconds, context: ctx) }
    }

    /// Runs 16 kHz mono samples through transcription, refinement, dictionary and
    /// history exactly like a recording would. Used by self-tests and the CLI.
    public func processSamples(_ samples: [Float], context: AppContext = .empty) {
        guard !state.isBusy else { return }
        prewarmRefiner(context: context)
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        levelHistory = []
        set(.transcribing)
        processingTask = Task { await process(samples: samples, seconds: seconds, context: context) }
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
        Task { [factory] in
            guard var refiner = await factory.refiner(for: config) as? CLIRefiner else { return }
            refiner.warmSystemPrompt = systemPrompt
            await refiner.prewarm()
        }
    }

    public func cancel() {
        stopping = false
        autoStopTask?.cancel()
        processingTask?.cancel()
        if recorder.isRecording { recorder.cancel() }
        recordingStartedAt = nil
        set(.idle)
    }

    // MARK: - Processing

    private func process(samples: [Float], seconds: Double, context: AppContext) async {
        let entries = dictionary.entries
        let asrConfig = settings.asr
        let llmConfig = settings.llm
        let profile = profiles.activeProfile
        let baseRules = profiles.baseRules
        let family = AppFamily.classify(context)
        var context = context
        if context.recentDictations.isEmpty {
            context.recentDictations = (try? history?.recentFinals(appBundleId: context.bundleId)) ?? []
        }

        // 1. ASR
        let transcript: Transcript
        do {
            let transcriber = await factory.transcriber(for: asrConfig)
            if await !transcriber.isReady() {
                set(.preparingModel)
                try await factory.prepare(asrConfig)
                guard !Task.isCancelled else { set(.idle); return }
                set(.transcribing)
            }
            await factory.markUsed(transcriber.id)
            let hints = TranscriptionHints(
                language: asrConfig.language.isEmpty ? nil : asrConfig.language,
                vocabulary: DictionaryPostProcessor.vocabulary(entries),
                chineseScript: asrConfig.chineseScript
            )
            transcript = try await transcriber.transcribe(samples: samples, hints: hints)
        } catch {
            fail("Transcription failed: \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled else { set(.idle); return }
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
        } else if let refiner = await factory.refiner(for: llmConfig) {
            if let needs = llmNeedsLoad, await needs() {
                set(.preparingModel)
                await loadLLM?()
            }
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
                let result = try await refiner.refine(request)
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
        guard !Task.isCancelled else { set(.idle); return }

        // 3. Script normalisation, then the dictionary always has the last word.
        let normalised = ChineseScriptConverter.convert(refined, to: asrConfig.chineseScript)
        let final = DictionaryPostProcessor.apply(normalised, entries: entries)

        // 4. Insert
        set(.inserting)
        var notice: String?
        let inserted: Bool
        if insertionEnabled {
            let result = await inserter.insert(final, method: settings.insertionMethod, target: context)
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
        _ = try? history?.save(record)

        let outcome = DictationOutcome(
            raw: transcript.text, refined: refined, final: final,
            asrMs: transcript.latencyMs, llmMs: llmMs, llmSkippedReason: skipReason
        )
        lastOutcome = outcome
        onOutcome?(outcome)
        if let notice {
            set(.notice(notice))
            Task {
                try? await Task.sleep(for: .seconds(3))
                if case .notice = state { set(.idle) }
            }
        } else {
            set(.idle)
        }
    }

    // MARK: - Helpers

    private func set(_ new: PipelineState) {
        state = new
        onStateChange?(new)
    }

    private func fail(_ message: String) {
        set(.failed(message))
        Task {
            try? await Task.sleep(for: .seconds(4))
            if case .failed = state { set(.idle) }
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
