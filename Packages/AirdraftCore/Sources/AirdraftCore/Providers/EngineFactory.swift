import Foundation
import os

/// Resolves the configured engines at call time, so switching providers in
/// Settings takes effect on the next dictation. Local transcribers are cached
/// by engine id because loading them is expensive; at most one stays loaded.
public actor EngineFactory {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "transcription-timing")
    /// Observable load states, for the UI.
    public let status: EngineStatus
    /// Unload engines that have not been used for this long. 0 disables.
    private var idleUnloadMinutes = 30
    private var local: [String: any Transcriber] = [:]
    private var operationTail: Task<Void, Never>?
    /// Lease operations queued or running. Memory pressure never waits behind one.
    private var leaseOperations = 0
    /// Cancels the display-only preview decode holding the lease, if any (AD-084).
    private var previewPreemption: (id: UUID, cancel: @Sendable () -> Void)?
    private var idleTask: Task<Void, Never>?
    private let modelLoadTimeout: TimeInterval
    private var retiringLoads: [String: Task<Void, Never>] = [:]
    private let transcriberBuilder: (@Sendable (ASRConfig) -> any Transcriber)?
    private let refinerBuilder: (@Sendable (LLMConfig) -> (any Refiner)?)?
    private let credentialReader: @Sendable (String) throws -> String?
    private let now: @Sendable () -> Date
    /// Active dictation sessions keep their speech engine resident. Each pin
    /// has a hard deadline so a leaked session cannot hold a model forever.
    private var sessionPins: [UUID: (engineID: String, expiresAt: Date)] = [:]
    /// Processing after the recording cap: final ASR, refinement and delivery.
    public static let sessionPinProcessingSeconds: TimeInterval = 300

    public init(status: EngineStatus,
                modelLoadTimeout: TimeInterval = 120,
                credentialReader: @escaping @Sendable (String) throws -> String? = { try Keychain.read($0) },
                transcriberBuilder: (@Sendable (ASRConfig) -> any Transcriber)? = nil,
                refinerBuilder: (@Sendable (LLMConfig) -> (any Refiner)?)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transcriberBuilder = transcriberBuilder
        self.refinerBuilder = refinerBuilder
        self.status = status
        self.modelLoadTimeout = modelLoadTimeout
        self.credentialReader = credentialReader
        self.now = now
        Task { await self.startIdleWatch() }
    }

    /// Keeps `engineID` out of idle unloading while a dictation records and
    /// processes. The pin lasts at most the model-load bound, the recording
    /// limit and the processing allowance; explicit unloads (model switch,
    /// reset, quit) still apply. Readiness is checked again at transcription.
    public func pinForSession(_ engineID: String, recordingSeconds: TimeInterval) -> UUID {
        let token = UUID()
        let lifetime = modelLoadTimeout + max(0, recordingSeconds) + Self.sessionPinProcessingSeconds
        sessionPins[token] = (engineID, now().addingTimeInterval(lifetime))
        return token
    }

    /// Ends a session pin. The idle countdown restarts from the session's end.
    public func releaseSessionPin(_ token: UUID) async {
        guard let pin = sessionPins.removeValue(forKey: token) else { return }
        if let engine = local[pin.engineID] { await markUsed(engine.id) }
    }

    private func activePinnedEngineIDs() -> Set<String> {
        let date = now()
        sessionPins = sessionPins.filter { $0.value.expiresAt > date }
        return Set(sessionPins.values.map(\.engineID))
    }

    public func transcriber(for config: ASRConfig) -> any Transcriber {
        let id = config.engineID
        if let cached = local[id] { return cached }
        if let transcriberBuilder {
            let engine = transcriberBuilder(config)
            if config.kind.isLocal { local[id] = engine }
            return engine
        }
        let key: String?
        do { key = config.kind.isLocal ? nil : try credentialReader(config.keyRef) }
        catch { return CredentialFailureEngine(id: id, error: error) }
        let engine: any Transcriber
        switch config.kind {
        case .fluidAudio: engine = FluidAudioTranscriber(modelID: config.model)
        case .orukeet: engine = SherpaTranscriber(model: .orukeet)
        case .transcribeCpp: engine = GGUFTranscriber(modelID: config.model)
        case .whisperKit: engine = WhisperKitTranscriber(variant: config.whisperModel)
        case .qwen3: engine = Qwen3ASRTranscriber(modelId: config.qwen3Model)
        case .cohere: engine = CohereTranscriber(modelId: config.cohereModel)
        case .fireRed: engine = SherpaTranscriber(model: .fireRed)
        case .senseVoice: engine = SherpaTranscriber(model: .senseVoice)
        case .parakeet: engine = SherpaTranscriber(model: .parakeet)
        case .apple: engine = AppleSpeechTranscriber(locale: config.effectiveAppleLocale)
        case .openAI:
            return OpenAITranscriber(model: config.speechModelID, apiKey: key)
        case .openRouter:
            return OpenRouterTranscriber(model: config.model, apiKey: key)
        case .groq:
            let url = URL(string: config.kind.preset?.baseURL ?? LLMProviderKind.groq.defaultBaseURL)!
            return OpenAICompatibleTranscriber(baseURL: url, model: config.speechModelID,
                                               apiKey: key, id: config.engineID, requiresKey: true)
        case .elevenLabs:
            return ElevenLabsTranscriber(modelId: config.speechModelID, apiKey: key, id: config.engineID)
        case .deepgram:
            return DeepgramTranscriber(model: config.speechModelID, apiKey: key)
        case .soniox:
            return SonioxTranscriber(apiKey: key)
        case .assemblyAI:
            return AssemblyAITranscriber(model: config.speechModelID, apiKey: key)
        case .cartesia:
            return CartesiaTranscriber(apiKey: key)
        case .speechmatics:
            return SpeechmaticsTranscriber(apiKey: key)
        case .xAI:
            return XAITranscriber(apiKey: key)
        case .mistral:
            return MistralTranscriber(apiKey: key)
        case .gemini:
            return GeminiTranscriber(apiKey: key)
        case .openAICompatible:
            let url = URL(string: config.baseURL) ?? URL(string: "https://api.openai.com/v1")!
            return OpenAICompatibleTranscriber(baseURL: url, model: config.model, apiKey: key)
        }
        local[id] = engine
        return engine
    }

    public func mediaCredential(for reference: String) throws -> String? { try credentialReader(reference) }

    public func transcribeMediaWindow(_ samples: [Float], offset: Double, config: ASRConfig) async throws -> [TranscriptWord] {
        let language = try SpeechLanguagePolicy.resolve(config).language
        guard config.kind.isLocal else { throw MediaError.unsupportedModel }
        // Exact digital silence contains no speech; do not let generative models invent a segment.
        // Quiet nonzero audio still reaches the recognizer.
        guard samples.contains(where: { $0 != 0 }) else { return [] }
        return try await serialize {
            // Media setup owns explicit installation, including Apple's language assets.
            if config.kind == .apple, !(await self.transcriber(for: config).isReady()) {
                throw TranscriberError.modelNotDownloaded
            }
            let engine = try await self.prepareExclusive(config)
            try Task.checkCancellation()
            await self.markUsed(engine.id)
            let words: [TranscriptWord]
            if let whisper = engine as? WhisperKitTranscriber {
                words = try await whisper.transcribeWords(samples: samples, language: language, offset: offset)
            } else {
                let result = try await engine.transcribe(samples: samples, hints: .init(language: language, chineseScript: config.effectiveChineseScript))
                // Measured audio-segment bounds, never invented times for individual words.
                // AD-082: a decoder loop inside a media window is cut to one occurrence.
                let text = TranscriptRepetition.trimmed(result.text) ?? result.text
                words = result.isEmpty ? [] : [.init(start: offset, end: offset + Double(samples.count) / 16_000, text: text + " ", timing: .segment)]
            }
            try Task.checkCancellation()
            await self.markUsed(engine.id)
            return words
        }
    }

    /// Refiners are cheap value types built per call, so a key or model change
    /// in Settings takes effect on the next dictation.
    public func refiner(for config: LLMConfig) async -> (any Refiner)? {
        guard config.kind != .none else { return nil }
        if let refinerBuilder { return refinerBuilder(config) }
        if config.kind == .appleIntelligence { return AppleIntelligenceRefiner(timeout: config.timeoutSeconds) }
        if let tool = config.kind.cliTool {
            guard let executable = config.cliExecutable else { return nil }
            let models = try? await CLIModelCatalog.shared.models(tool: tool, executable: executable, timeout: 3)
            let info = CLIModelInfo.selected(config.model, in: models ?? [])
            let model = tool == .codex && config.model.isEmpty ? info?.id ?? config.kind.defaultModel : config.model
            return CLIRefiner(tool: tool, executable: executable, model: model, effort: config.thinkingEffort,
                              timeout: max(config.timeoutSeconds, 60), supportedEfforts: info?.dictationEfforts)
        }
        guard let url = config.endpoint else { return nil }
        let key: String?
        do { key = try credentialReader(config.keyRef) }
        catch { return CredentialFailureEngine(id: "credential-unavailable", error: error) }
        switch config.kind.wire {
        case .openAIChat:
            return OpenAICompatibleRefiner(
                baseURL: url,
                model: config.model,
                apiKey: key,
                temperature: config.temperature,
                timeout: config.timeoutSeconds,
                effort: config.thinkingEffort,
                provider: config.kind,
                openRouterRouting: config.openRouterRouting
            )
        case .anthropicMessages:
            return AnthropicRefiner(
                baseURL: url,
                model: config.model,
                apiKey: key,
                effort: config.thinkingEffort,
                timeout: config.timeoutSeconds
            )
        case .appleIntelligence, .cli:
            return nil  // handled above, where the executable is resolved
        case .geminiGenerateContent:
            return GeminiRefiner(
                baseURL: url,
                model: config.model,
                apiKey: key,
                temperature: config.temperature,
                timeout: config.timeoutSeconds,
                effort: config.thinkingEffort
            )
        }
    }

    /// Loads the engine for `config`, reports progress on `status`, and
    /// unloads every other cached engine so only one model sits in memory.
    public func prepare(_ config: ASRConfig) async throws {
        _ = try await serialize { try await self.prepareExclusive(config) }
    }

    /// Loading, inference and unloading share a lease. Actor isolation alone is
    /// insufficient because each await allows another actor call to enter.
    public func transcribe(_ samples: [Float], hints: TranscriptionHints, config: ASRConfig,
                           onPreparing: (@Sendable () async -> Void)? = nil) async throws -> Transcript {
        let started = ProcessInfo.processInfo.systemUptime
        let language = try SpeechLanguagePolicy.resolve(config)
        var resolvedHints = hints
        resolvedHints.language = language.language
        let effectiveHints = resolvedHints
        return try await serialize {
            let engine = try await self.prepareExclusive(config, onPreparing: onPreparing)
            let prepared = ProcessInfo.processInfo.systemUptime
            try Task.checkCancellation()
            await self.markUsed(engine.id)
            // AD-082: empty, wrong-language and looping local output is checked inside the same lease.
            var result = try await LocalASROutputGuard.transcribe(engine: engine, samples: samples,
                                                                  hints: effectiveHints, config: config)
            try Task.checkCancellation()
            await self.markUsed(engine.id)
            let finished = ProcessInfo.processInfo.systemUptime
            result.latencyMs = Int((finished - started) * 1000)
            Self.log.notice("engine=\(engine.id, privacy: .public) totalMs=\(result.latencyMs) preparationMs=\(Int((prepared - started) * 1000)) decodeMs=\(Int((finished - prepared) * 1000)) audioSeconds=\(Double(samples.count) / 16_000)")
            return result
        }
    }

    /// Display-only live text from the recording's loaded local model (AD-084).
    /// Never loads, downloads or queues: nil when the engine is not loaded or any
    /// lease operation (load, final inference, media, unload) is queued or running.
    /// Every other lease operation cancels it, so final inference waits at most for
    /// one bounded native window decode that ignores cancellation.
    public func transcribePreview(_ samples: [Float], hints: TranscriptionHints, config: ASRConfig) async throws -> String? {
        guard ModelSpeechPreview.supports(config), !samples.isEmpty else { return nil }
        // No await separates these checks from entering the lease.
        guard leaseOperations == 0, retiringLoads[config.engineID] == nil,
              let engine = local[config.engineID] else { return nil }
        return try await serialize(preview: true) { () async throws -> String? in
            guard await engine.isReady() else { return nil }
            if let sherpa = engine as? SherpaTranscriber, !(await sherpa.isWarm(for: hints)) { return nil }
            try Task.checkCancellation()
            let result = try await engine.transcribe(samples: samples, hints: hints)
            try Task.checkCancellation()
            await self.markUsed(engine.id)
            let text = TranscriptRepetition.trimmed(result.text) ?? result.text
            return ChineseScriptConverter.convert(text.trimmingCharacters(in: .whitespacesAndNewlines), to: hints.chineseScript)
        }
    }

    private func serialize<Value: Sendable>(preview: Bool = false,
                                            _ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        // Final inference, loading and unloading always take precedence over preview.
        if !preview, let preemption = previewPreemption {
            previewPreemption = nil
            preemption.cancel()
        }
        let previous = operationTail
        leaseOperations += 1
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        let previewID = UUID()
        if preview { previewPreemption = (previewID, { task.cancel() }) }
        defer { if preview, previewPreemption?.id == previewID { previewPreemption = nil } }
        operationTail = Task {
            _ = try? await task.value
            self.leaveLease()
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func leaveLease() { leaseOperations -= 1 }

    private func prepareExclusive(_ config: ASRConfig, onPreparing: (@Sendable () async -> Void)? = nil) async throws -> any Transcriber {
        try Task.checkCancellation()
        guard retiringLoads[config.engineID] == nil else {
            let error = TranscriberError.modelLoadStillStopping
            await MainActor.run { status.set(config.engineID, .failed(error.localizedDescription)) }
            throw error
        }
        let engine = transcriber(for: config)
        await unloadAllExclusive(except: engine.id)
        try Task.checkCancellation()
        if await engine.isReady() {
            let date = now()
            await MainActor.run { status.set(engine.id, .ready, at: date) }
            return engine
        }
        await onPreparing?()
        try Task.checkCancellation()
        await MainActor.run { status.set(engine.id, .loading) }
        let preparation = Task { try await engine.prepare() }
        do {
            try await OperationDeadline.run(seconds: modelLoadTimeout) {
                try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
            }
            try Task.checkCancellation()
            let date = now()
            await MainActor.run { status.set(engine.id, .ready, at: date) }
            return engine
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
            let failure: Error
            if cancelled { failure = CancellationError() }
            else if case RefinerError.timeout = error { failure = TranscriberError.modelLoadTimedOut }
            else { failure = error }
            preparation.cancel()
            // A native compiler may ignore cancellation. Retire this instance
            // outside the lease so another model can load, but do not unload it
            // or allow its files to be deleted until preparation really returns.
            local[engine.id] = nil
            await MainActor.run {
                status.setRetiring(engine.id, true)
                status.set(engine.id, cancelled ? .notLoaded : .failed(failure.localizedDescription))
            }
            retiringLoads[engine.id] = Task { [weak self] in
                _ = await preparation.result
                await engine.unload()
                await self?.finishRetiringLoad(engine.id)
            }
            throw failure
        }
    }

    private func finishRetiringLoad(_ engineID: String) async {
        retiringLoads[engineID] = nil
        await MainActor.run { status.setRetiring(engineID, false) }
    }

    public func markUsed(_ engineID: String) async {
        let date = now()
        await MainActor.run { status.touch(engineID, at: date) }
    }

    public func unloadAll(except keep: String? = nil) async {
        _ = try? await serialize { await self.unloadAllExclusive(except: keep) }
        // Reset and quit still wait for owned native work. This wait must stay
        // outside the lease, so it cannot block an unrelated model selection.
        let pending = Array(retiringLoads.values)
        for task in pending { await task.value }
    }

    private func unloadAllExclusive(except keep: String? = nil) async {
        for engine in local.values where engine.id != keep {
            await unload(engine)
        }
    }

    private func unload(_ engine: any Transcriber) async {
        guard await engine.isReady() else { return }
        await engine.unload()
        await MainActor.run { status.set(engine.id, .notLoaded) }
    }

    public func setIdleUnloadMinutes(_ minutes: Int) {
        idleUnloadMinutes = minutes
    }

    private func startIdleWatch() {
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                await self.unloadIdle()
            }
        }
    }

    /// One idle pass; the watch calls it every 30 seconds. Internal for tests.
    func unloadIdle() async {
        guard idleUnloadMinutes > 0 else { return }
        _ = try? await serialize { await self.unloadIdleExclusive() }
    }

    fileprivate func unloadForMemoryPressureExclusive(minimumIdleSeconds: TimeInterval) async -> MemoryPressureUnload {
        var result = MemoryPressureUnload()
        let cutoff = now().addingTimeInterval(-max(0, minimumIdleSeconds))
        let pinned = activePinnedEngineIDs()
        let (lastUsed, pendingLoads) = await MainActor.run { [local] in
            (status.lastUsedAt, Set(local.values.map(\.id).filter { status.hasPendingLoad(for: $0) }))
        }
        for (key, engine) in local.sorted(by: { $0.key < $1.key }) {
            guard retiringLoads[engine.id] == nil, !pendingLoads.contains(engine.id),
                  await engine.isReady() else { continue }
            if pinned.contains(key) || pinned.contains(engine.id) {
                result.keptPinned.append(engine.id)
            } else if let used = lastUsed[engine.id], used > cutoff {
                result.keptRecent.append(engine.id)
            } else {
                await unload(engine)
                result.unloaded.append(engine.id)
            }
        }
        return result
    }

    private func unloadIdleExclusive() async {
        guard idleUnloadMinutes > 0 else { return }
        let cutoff = now().addingTimeInterval(-Double(idleUnloadMinutes) * 60)
        let pinned = activePinnedEngineIDs()
        let stale = await MainActor.run { status.lastUsedAt.filter { $0.value < cutoff }.map(\.key) }
        // Pins name the config's engine ID, which is also the cache key.
        for (key, engine) in local where stale.contains(engine.id) && !pinned.contains(key) && !pinned.contains(engine.id) {
            await unload(engine)
        }
    }
}

extension EngineFactory {
    /// Frees resident local speech models under system memory pressure.
    /// Never waits behind the lease: an active load or inference (or one queued
    /// for it) skips the pass, so loads finish and inference keeps its model.
    /// Pinned engines, retiring loads and engines used within
    /// `minimumIdleSeconds` stay. Logs engine IDs and durations only.
    public func unloadForMemoryPressure(minimumIdleSeconds: TimeInterval) async -> MemoryPressureUnload {
        let started = ProcessInfo.processInfo.systemUptime
        guard leaseOperations == 0 else {
            Self.pressureLog.notice("memoryPressure skipped=busy")
            return MemoryPressureUnload(skippedBusy: true)
        }
        // No await separates the check above from entering the lease, so this
        // pass is first in line and nothing can start a load before it runs.
        let result = (try? await serialize { await self.unloadForMemoryPressureExclusive(minimumIdleSeconds: minimumIdleSeconds) })
            ?? MemoryPressureUnload(skippedBusy: true)
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        Self.pressureLog.notice("memoryPressure unloaded=\(result.unloaded.joined(separator: ","), privacy: .public) keptPinned=\(result.keptPinned.joined(separator: ","), privacy: .public) keptRecent=\(result.keptRecent.joined(separator: ","), privacy: .public) skippedBusy=\(result.skippedBusy, privacy: .public) durationMs=\(elapsed)")
        return result
    }

    private static let pressureLog = Logger(subsystem: AppIdentity.logSubsystem, category: "models")
}

/// Preserves the engine contracts and the pipeline's raw-text fallback while
/// reporting denied Keychain access without unauthenticated provider requests.
struct CredentialFailureEngine: Transcriber, Refiner {
    let id: String
    let error: Error
    func prepare() async throws { throw error }
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript { throw error }
    func refine(_ request: RefineRequest) async throws -> RefineResult { throw error }
}
