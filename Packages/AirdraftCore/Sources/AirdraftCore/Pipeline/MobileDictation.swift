import Foundation
import Observation
import os

/// One dictation's setup, captured when recording starts like the macOS
/// pipeline's snapshot: settings changed mid-recording apply to the next one.
public struct MobileDictationSnapshot: Sendable, Equatable {
    public var asr: ASRConfig
    public var profile: RefinementProfile
    public var llm: LLMConfig
    public var baseRules: String
    public var dictionary: [DictionaryEntry]
    public var vocabularyBiasesOnDeviceSpeech: Bool
    public var keepsAudio: Bool
    public var recordingSeconds: Int

    public init(asr: ASRConfig, profile: RefinementProfile, llm: LLMConfig, baseRules: String,
                dictionary: [DictionaryEntry], vocabularyBiasesOnDeviceSpeech: Bool = true,
                keepsAudio: Bool = false, recordingSeconds: Int = SpeechInputLimits.defaultRecordingSeconds) {
        self.asr = asr
        self.profile = profile
        self.llm = llm
        self.baseRules = baseRules
        self.dictionary = dictionary
        self.vocabularyBiasesOnDeviceSpeech = vocabularyBiasesOnDeviceSpeech
        self.keepsAudio = keepsAudio
        self.recordingSeconds = recordingSeconds
    }
}

/// What one dictation produced. `final` is what reaches the user; a failed or
/// rejected refinement leaves the raw transcript there and says why.
public struct MobileDictationResult: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var transcript: Transcript
    public var refined: String
    public var final: String
    public var llmEngine: String?
    public var promptVersion: String?
    public var llmMs: Int
    public var refinementError: String?
    public var refinementRejected: Bool
    public var audioSeconds: Double
    public var profileName: String

    public init(id: UUID = UUID(), transcript: Transcript, refined: String, final: String,
                llmEngine: String? = nil, promptVersion: String? = nil, llmMs: Int = 0,
                refinementError: String? = nil, refinementRejected: Bool = false,
                audioSeconds: Double, profileName: String) {
        self.id = id
        self.transcript = transcript
        self.refined = refined
        self.final = final
        self.llmEngine = llmEngine
        self.promptVersion = promptVersion
        self.llmMs = llmMs
        self.refinementError = refinementError
        self.refinementRejected = refinementRejected
        self.audioSeconds = audioSeconds
        self.profileName = profileName
    }
}

/// Where an iOS dictation went. The app cannot paste into other apps; the text
/// reaches them through the Airdraft keyboard or the clipboard.
public enum MobileDelivery: Sendable, Equatable {
    /// The Airdraft keyboard inserted it; `confirmed` when the field shows it.
    case keyboard(confirmed: Bool)
    /// Copied to the clipboard for the user to paste.
    case copied
    /// Shown in Airdraft only.
    case shown
}

/// The iOS dictation flow: record, transcribe, refine, then hand the text to the
/// app for the keyboard or clipboard. It composes the same stages as the macOS
/// `DictationPipeline` and keeps its contracts: speech-language and input-limit
/// checks before inference, best-effort refinement that falls back to the raw
/// transcript on any error, timeout or fidelity rejection, the Chinese script
/// converter, and the dictionary last. Shared by every platform so the Core
/// tests cover it on the Mac.
@MainActor
@Observable
public final class MobileDictation {
    public enum Phase: Sendable, Equatable {
        case idle
        case recording
        case transcribing
        case refining
    }

    public enum StartError: LocalizedError {
        case busy
        public var errorDescription: String? {
            String(localized: "Airdraft is already starting or processing a recording.", bundle: .module)
        }
    }

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "mobile-dictation")

    public private(set) var phase: Phase = .idle
    /// Most recent input levels (0...1), oldest first, for the recording waveform.
    public private(set) var levels: [Float] = []
    public private(set) var recordingStartedAt: Date?
    public private(set) var lastResult: MobileDictationResult?
    /// A failure the user should see; cleared when the next recording starts.
    public private(set) var lastError: String?
    /// Called when a recording reaches its limit and stops on its own.
    public var onAutomaticStop: (@MainActor () -> Void)?

    private let settings: AppSettings
    private let profiles: ProfileStore
    private let dictionary: DictionaryStore
    private let factory: EngineFactory
    private let history: HistoryStore?
    private let recorder: any AudioRecording
    private let environment: () -> RecordingPrerequisites.Environment
    private var snapshot: MobileDictationSnapshot?
    private var token = UUID()
    private var limitTask: Task<Void, Never>?
    private var pendingSamples: [Float]?
    private static let levelHistoryLength = 48

    public init(settings: AppSettings, profiles: ProfileStore, dictionary: DictionaryStore,
                factory: EngineFactory, history: HistoryStore?, recorder: any AudioRecording,
                environment: @escaping () -> RecordingPrerequisites.Environment = { .live }) {
        self.settings = settings
        self.profiles = profiles
        self.dictionary = dictionary
        self.factory = factory
        self.history = history
        self.recorder = recorder
        self.environment = environment
    }

    public var isBusy: Bool { phase != .idle }

    /// The setup the next recording would use: the active profile, its speech
    /// binding or the app default, and the shared dictionary.
    public func currentSnapshot() -> MobileDictationSnapshot {
        let profile = settings.effectiveProfile(profiles.activeProfile)
        let asr = profile.speechConfig(default: settings.asr)
        return MobileDictationSnapshot(
            asr: asr, profile: profile, llm: settings.llm, baseRules: profiles.baseRules,
            dictionary: dictionary.entries,
            vocabularyBiasesOnDeviceSpeech: settings.vocabularyBiasesOnDeviceSpeech,
            keepsAudio: settings.audioRetention != .off,
            recordingSeconds: SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: asr.kind))
    }

    /// Checks the setup without opening the microphone; nil when ready.
    public func readinessIssue() -> String? {
        let snapshot = currentSnapshot()
        do {
            try Self.check(snapshot, environment: environment())
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Checks prerequisites, captures the setup and starts recording.
    public func start() throws {
        guard phase == .idle else { throw StartError.busy }
        let snapshot = currentSnapshot()
        try Self.check(snapshot, environment: environment())
        lastError = nil
        levels.removeAll()
        recorder.levelHandler = { [weak self] level in
            Task { @MainActor in self?.append(level: level) }
        }
        try recorder.start(microphone: .systemDefault)
        self.snapshot = snapshot
        token = UUID()
        phase = .recording
        recordingStartedAt = Date()
        let limit = snapshot.recordingSeconds
        let started = token
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self, self.token == started, self.phase == .recording else { return }
            Self.log.notice("recording reached its limit seconds=\(limit)")
            self.onAutomaticStop?()
        }
        Self.log.notice("recording started engine=\(snapshot.asr.engineID, privacy: .public)")
    }

    /// Stops recording and processes the capture. Nil for silence, cancellation
    /// or a speech failure, which `lastError` describes.
    @discardableResult
    public func stop() async -> MobileDictationResult? {
        guard phase == .recording, let snapshot else { return nil }
        limitTask?.cancel()
        let samples = recorder.stop()
        recorder.levelHandler = nil
        let current = token
        phase = .transcribing
        defer {
            if token == current {
                phase = .idle
                recordingStartedAt = nil
            }
        }
        do {
            let result = try await Self.process(samples: samples, snapshot: snapshot, factory: factory,
                                                owner: current) { [weak self] stage in
                guard let self, self.token == current else { return }
                self.phase = stage
            }
            guard token == current else { return nil }
            pendingSamples = snapshot.keepsAudio ? samples : nil
            lastResult = result
            return result
        } catch is CancellationError {
            return nil
        } catch {
            guard token == current else { return nil }
            lastError = error.localizedDescription
            Self.log.error("dictation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Discards the recording in progress or ignores a result still processing.
    public func cancel() {
        limitTask?.cancel()
        token = UUID()
        if recorder.isRecording { recorder.cancel() }
        recorder.levelHandler = nil
        phase = .idle
        recordingStartedAt = nil
        snapshot = nil
    }

    /// Saves a delivered result to History; delivered text always reaches it.
    @discardableResult
    public func record(_ result: MobileDictationResult, delivery: MobileDelivery) -> DictationRecord? {
        guard let history else { return nil }
        let destination: String?
        let inserted: Bool
        let succeeded: Bool?
        switch delivery {
        case .keyboard(let confirmed):
            destination = TextOutputDestination.cursor.rawValue
            inserted = confirmed
            succeeded = true
        case .copied:
            destination = DictationRecord.copyDestination
            inserted = false
            succeeded = true
        case .shown:
            destination = nil
            inserted = false
            succeeded = nil
        }
        let record = DictationRecord(
            mode: result.profileName,
            family: AppFamily.classify(.empty).rawValue,
            rawTranscript: result.transcript.text,
            refinedText: result.refined,
            finalText: result.final,
            language: result.transcript.language,
            asrEngine: result.transcript.engine,
            llmEngine: result.llmEngine,
            promptVersion: result.promptVersion,
            audioSeconds: result.audioSeconds,
            asrMs: result.transcript.latencyMs,
            llmMs: result.llmMs,
            inserted: inserted,
            error: result.refinementError,
            outputDestination: destination,
            outputSucceeded: succeeded)
        let samples = lastResult?.id == result.id ? pendingSamples : nil
        pendingSamples = nil
        do {
            return try history.save(record, samples: samples)
        } catch {
            lastError = String(localized: "History could not save this dictation: \(error.localizedDescription)", bundle: .module)
            return nil
        }
    }

    private func append(level: Float) {
        guard phase == .recording else { return }
        levels.append(level)
        if levels.count > Self.levelHistoryLength { levels.removeFirst(levels.count - Self.levelHistoryLength) }
    }

    // MARK: - Stages

    static func check(_ snapshot: MobileDictationSnapshot, environment: RecordingPrerequisites.Environment) throws {
        if let reason = snapshot.profile.speechModel?.unavailableReason {
            throw RecordingPrerequisiteError(reason)
        }
        try RecordingPrerequisites.check(asr: snapshot.asr, llm: snapshot.llm,
                                         refinementEnabled: snapshot.profile.usesLLM,
                                         microphone: .systemDefault, insertionEnabled: false,
                                         environment: environment)
    }

    /// Transcribes and refines one capture with its captured setup. Throws for
    /// a speech failure; refinement never throws. Silence returns nothing to deliver.
    public static func process(samples: [Float], snapshot: MobileDictationSnapshot, factory: EngineFactory,
                               owner: UUID = UUID(),
                               stage: @MainActor (Phase) -> Void = { _ in }) async throws -> MobileDictationResult? {
        // Silent recordings contain no speech; recognizers hallucinate on them
        // (AD-143), so nothing reaches delivery or history.
        guard !AudioActivity.isSilent(samples) else { return nil }
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        let asr = snapshot.asr
        let language = try SpeechLanguagePolicy.resolve(asr)
        try SpeechInputLimits.validate(sampleCount: samples.count, for: asr.kind)
        let hints = TranscriptionHints(language: language.language,
                                       vocabulary: DictionaryPostProcessor.vocabulary(snapshot.dictionary),
                                       chineseScript: asr.effectiveChineseScript,
                                       biasOnDeviceSpeech: snapshot.vocabularyBiasesOnDeviceSpeech)
        let transcript = try await factory.transcribe(samples, hints: hints, config: asr)
        try Task.checkCancellation()
        guard !transcript.isEmpty else { return nil }

        var result = MobileDictationResult(transcript: transcript, refined: transcript.text, final: transcript.text,
                                           audioSeconds: seconds, profileName: snapshot.profile.name)
        if let skipped = refinementSkipReason(transcript, snapshot: snapshot) {
            log.notice("refinement skipped: \(skipped, privacy: .public)")
        } else {
            stage(.refining)
            await refine(&result, snapshot: snapshot, factory: factory, owner: owner)
        }
        // Script normalisation, then the dictionary always has the last word.
        let normalised = ChineseScriptConverter.convert(result.refined, to: asr.effectiveChineseScript)
        result.final = DictionaryPostProcessor.apply(normalised, entries: snapshot.dictionary)
        return result
    }

    static func refinementSkipReason(_ transcript: Transcript, snapshot: MobileDictationSnapshot) -> String? {
        guard snapshot.profile.usesLLM else { return "\(snapshot.profile.name): no LLM" }
        let words = ApproximateWordCount.of(transcript.text)
        guard words >= snapshot.llm.minWordsForLLM else { return "short utterance (\(words) words)" }
        guard snapshot.llm.kind != .none else { return "LLM off" }
        return nil
    }

    /// Best effort: errors, timeouts and fidelity rejections keep the raw transcript.
    static func refine(_ result: inout MobileDictationResult, snapshot: MobileDictationSnapshot,
                       factory: EngineFactory, owner: UUID) async {
        let transcript = result.transcript
        let llm = snapshot.llm
        let request = RefineRequest(
            transcript: transcript.text,
            profile: snapshot.profile,
            baseRules: snapshot.baseRules,
            context: .empty,
            family: AppFamily.classify(.empty),
            dictionary: snapshot.dictionary,
            chineseScript: snapshot.asr.effectiveChineseScript,
            speechLanguages: snapshot.asr.refinementLanguages())
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let refined = try await OperationDeadline.run(seconds: llm.timeoutSeconds) {
                guard let refiner = await factory.refiner(for: llm) else { throw RefinerError.invalidResponse }
                let prepared = try await refiner.prepare(request, backend: .unmanaged, owner: owner)
                return try await prepared.refine(request)
            }
            let allowsLanguageChange = !snapshot.profile.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let violation = RefinementFidelity.violation(output: refined.text, transcript: transcript.text,
                                                            recentDictations: [],
                                                            allowsLanguageChange: allowsLanguageChange) {
                log.notice("refinement rejected: \(String(describing: violation), privacy: .public) engine=\(refined.engine, privacy: .public)")
                result.refinementError = violation.message
                result.refinementRejected = true
            } else {
                result.refined = refined.text
                result.llmEngine = refined.engine
                result.promptVersion = refined.promptVersion
            }
        } catch {
            result.refinementError = error.localizedDescription
        }
        result.llmMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
    }
}
