import Foundation

/// Resolves the configured engines at call time, so switching providers in
/// Settings takes effect on the next dictation. Local transcribers are cached
/// by engine id because loading them is expensive; at most one stays loaded.
public actor EngineFactory {
    /// Observable load states, for the UI.
    public let status: EngineStatus
    /// Unload engines that have not been used for this long. 0 disables.
    private var idleUnloadMinutes = 10
    private var local: [String: any Transcriber] = [:]
    private var idleTask: Task<Void, Never>?

    public init(status: EngineStatus) {
        self.status = status
        Task { await self.startIdleWatch() }
    }

    public func transcriber(for config: ASRConfig) -> any Transcriber {
        let id = config.engineID
        if let cached = local[id] { return cached }
        let engine: any Transcriber
        switch config.kind {
        case .whisperKit: engine = WhisperKitTranscriber(variant: config.whisperModel)
        case .qwen3: engine = Qwen3ASRTranscriber(modelId: config.qwen3Model)
        case .cohere: engine = CohereTranscriber(modelId: config.cohereModel)
        case .fireRed: engine = SherpaTranscriber(model: .fireRed)
        case .senseVoice: engine = SherpaTranscriber(model: .senseVoice)
        case .apple: engine = AppleSpeechTranscriber(locale: config.appleLocale)
        case .elevenLabs:
            // Remote engines are cheap to build and pick up key changes this way.
            return ElevenLabsTranscriber(modelId: config.elevenLabsModel, apiKey: Keychain.get(EndpointPreset.elevenLabsKeyRef))
        case .openAICompatible:
            let url = URL(string: config.baseURL) ?? URL(string: "https://api.openai.com/v1")!
            return OpenAICompatibleTranscriber(baseURL: url, model: config.model, apiKey: Keychain.get(config.apiKeyRef))
        }
        local[id] = engine
        return engine
    }

    /// Refiners are cheap value types built per call, so a key or model change
    /// in Settings takes effect on the next dictation.
    public func refiner(for config: LLMConfig) async -> (any Refiner)? {
        guard config.kind != .none else { return nil }
        if let tool = config.kind.cliTool {
            guard let executable = config.cliExecutable else { return nil }
            let models = try? await CLIModelCatalog.shared.models(tool: tool, executable: executable, timeout: 3)
            let info = CLIModelInfo.selected(config.model, in: models ?? [])
            let model = tool == .codex && config.model.isEmpty ? info?.id ?? config.kind.defaultModel : config.model
            return CLIRefiner(tool: tool, executable: executable, model: model, effort: config.thinkingEffort,
                              timeout: max(config.timeoutSeconds, 60), supportedEfforts: info?.dictationEfforts)
        }
        guard let url = config.endpoint else { return nil }
        let key = Keychain.get(config.keyRef)
        switch config.kind.wire {
        case .openAIChat:
            return OpenAICompatibleRefiner(
                baseURL: url,
                model: config.model,
                apiKey: key,
                temperature: config.temperature,
                timeout: config.timeoutSeconds,
                effort: config.thinkingEffort,
                provider: config.kind
            )
        case .anthropicMessages:
            return AnthropicRefiner(
                baseURL: url,
                model: config.model,
                apiKey: key,
                effort: config.thinkingEffort,
                timeout: config.timeoutSeconds
            )
        case .cli:
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
        let engine = transcriber(for: config)
        await unloadAll(except: engine.id)
        if await engine.isReady() {
            await MainActor.run { status.set(engine.id, .ready) }
            return
        }
        await MainActor.run { status.set(engine.id, .loading) }
        do {
            try await engine.prepare()
            await MainActor.run { status.set(engine.id, .ready) }
        } catch {
            await MainActor.run { status.set(engine.id, .failed(error.localizedDescription)) }
            throw error
        }
    }

    public func markUsed(_ engineID: String) async {
        await MainActor.run { status.touch(engineID) }
    }

    public func unloadAll(except keep: String? = nil) async {
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

    private func unloadIdle() async {
        guard idleUnloadMinutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(idleUnloadMinutes) * 60)
        let stale = await MainActor.run { status.lastUsedAt.filter { $0.value < cutoff }.map(\.key) }
        for engine in local.values where stale.contains(engine.id) {
            await unload(engine)
        }
    }
}
