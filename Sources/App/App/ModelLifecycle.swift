import AppKit
import Foundation
import Observation
import AirdraftCore
import os

/// Owns when models are in memory.
/// - Speech: exactly one local engine is resident; switching unloads the old one,
///   idle engines unload after `idleUnloadMinutes`, quitting frees everything.
/// - LLM (LM Studio): loaded by the app before the first refinement, switched
///   cleanly, and unloaded when the app quits.
@MainActor
@Observable
final class ModelLifecycle {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "models")

    let engineStatus: EngineStatus
    let llmStatus = LLMStatus()
    private let factory: EngineFactory
    private let settings: AppSettings
    private let profiles: ProfileStore?
    private var speechConfig: ASRConfig { profiles?.activeProfile.speechConfig(default: settings.asr) ?? settings.asr }
    private let lmStudio = LMStudioControl()
    private var lastLLM: LLMConfig?
    private var lastASR: ASRConfig?
    private var speechLoadTask: Task<Void, Never>?
    private var llmGeneration = UUID()
    private var llmCleanupGeneration = UUID()
    private var dictationBusy = false
    private var usedLLMEndpoints: [URL: Set<String>] = [:]
    private var llmUnloads: [UUID: (url: URL, task: Task<Void, Error>)] = [:]

    func setDictationBusy(_ busy: Bool) {
        if busy && !dictationBusy { llmCleanupGeneration = UUID() }
        dictationBusy = busy
        if !busy { handleSettingsChange() }
    }

    init(settings: AppSettings, factory: EngineFactory, engineStatus: EngineStatus, profiles: ProfileStore? = nil) {
        self.settings = settings
        self.factory = factory
        self.engineStatus = engineStatus
        self.profiles = profiles
    }

    func start() {
        lastASR = speechConfig
        lastLLM = settings.llm
        Task { await factory.setIdleUnloadMinutes(settings.idleUnloadMinutes) }
        Task { await refreshLLMStatus() }
        observe()
        loadSpeechModel()
    }

    // MARK: Speech

    /// Load the selected local speech engine now, so status is visible before the first dictation.
    func loadSpeechModel() {
        guard !dictationBusy else { return }
        speechLoadTask?.cancel()
        let config = speechConfig
        guard config.kind.isLocal else { return unloadSpeechModels() }
        speechLoadTask = Task {
            do { try await factory.prepare(config) }
            catch { Self.log.error("speech load failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func unloadSpeechModels() {
        guard !dictationBusy else { return }
        speechLoadTask?.cancel()
        Task { await factory.unloadAll() }
    }

    // MARK: LLM

    /// Base URL when `config` points at a running LM Studio, the only server whose models the app manages.
    private func lmStudioURL(_ config: LLMConfig) async -> URL? {
        guard config.kind == .openAICompatible, let url = URL(string: config.baseURL),
              await lmStudio.serverKind(baseURL: url) == .lmStudio else { return nil }
        return url
    }

    func refreshLLMStatus() async {
        let config = settings.llm
        if config.kind.isCLI {
            llmStatus.set(.ready(config.cliExecutable == nil ? "CLI not found" : "Ready"))
            return
        }
        guard config.kind == .openAICompatible, let url = URL(string: config.baseURL) else {
            llmStatus.set(.remote)
            return
        }
        let server = await lmStudio.serverKind(baseURL: url)
        guard config == settings.llm, !Task.isCancelled else { return }
        switch server {
        case .unmanaged:
            llmStatus.set(.remote)
        case .unreachable:
            llmStatus.set(.unreachable)
        case .lmStudio:
            if case .loading = llmStatus.state { return }
            do {
                let instances = try await lmStudio.instances(baseURL: url, modelKey: config.model)
                guard config == settings.llm, !Task.isCancelled else { return }
                llmStatus.set(instances.first.map { .loaded(instance: $0) } ?? .notLoaded)
            } catch {
                guard config == settings.llm, !Task.isCancelled else { return }
                llmStatus.set(.failed(error.localizedDescription))
            }
        }
    }

    /// True when LM Studio is reachable but the configured model is not loaded,
    /// so the app should load it (small context) instead of letting LM Studio
    /// JIT-load it with its huge default context.
    func llmNeedsLoad(config: LLMConfig) async -> Bool {
        await waitForLLMUnloads(config)
        guard !Task.isCancelled else { return false }
        guard let url = await lmStudioURL(config) else { return false }
        return ((try? await lmStudio.instances(baseURL: url, modelKey: config.model)) ?? []).isEmpty
    }

    func loadLLM() {
        Task { await loadLLMIfNeeded() }
    }

    /// Explicit configs belong to an in-flight dictation; UI loads follow selection.
    func loadLLMIfNeeded(config requestedConfig: LLMConfig? = nil) async {
        let token = UUID()
        llmGeneration = token
        llmCleanupGeneration = UUID()
        let config = requestedConfig ?? settings.llm
        let followsSelection = requestedConfig == nil
        await waitForLLMUnloads(config)
        guard !Task.isCancelled, token == llmGeneration else { return }
        guard let url = await lmStudioURL(config) else {
            if config == settings.llm { await refreshLLMStatus() }
            return
        }
        if let existing = try? await lmStudio.instances(baseURL: url, modelKey: config.model).first {
            guard !Task.isCancelled, token == llmGeneration,
                  !followsSelection || settings.llm == config else { return }
            markLLMUsed(existing, config: config)
            if settings.llm == config { llmStatus.set(.loaded(instance: existing)) }
            return
        }
        // Set the outcome directly: refreshLLMStatus leaves a `.loading` state alone.
        guard !Task.isCancelled, token == llmGeneration,
              !followsSelection || settings.llm == config else { return }
        if settings.llm == config { llmStatus.set(.loading) }
        do {
            let id = try await lmStudio.load(baseURL: url, modelKey: config.model)
            markLLMUsed(id, config: config)
            guard !Task.isCancelled, token == llmGeneration,
                  !followsSelection || settings.llm == config else {
                // Another session may now use the same model. Keep ownership for
                // quit cleanup instead of unloading a reselected or active model.
                guard !dictationBusy, !sameManagedModel(config, settings.llm) else { return }
                do {
                    try await unloadLLMInstance(id, at: url)
                } catch {
                    Self.log.error("Stale LLM load cleanup failed; retaining instance for cleanup retry")
                }
                return
            }
            if settings.llm == config { llmStatus.set(.loaded(instance: id)) }
            Self.log.notice("LLM loaded instance=\(id, privacy: .public)")
        } catch {
            guard token == llmGeneration, settings.llm == config else { return }
            llmStatus.set(Task.isCancelled ? .notLoaded : .failed(error.localizedDescription))
        }
    }

    func unloadLLM() {
        guard !dictationBusy else { return }
        llmGeneration = UUID()
        let cleanupToken = UUID()
        llmCleanupGeneration = cleanupToken
        let config = settings.llm
        Task {
            if await unloadInstances(of: config, onlyUsedByApp: false, generation: cleanupToken), settings.llm == config {
                await refreshLLMStatus()
            }
        }
    }

    func noteLLMUsed(_ instance: String, config: LLMConfig) {
        // This set is used to unload LM Studio instances. Cloud provider names
        // reported by OpenRouter are not local model instance IDs.
        guard config.kind == .openAICompatible else { return }
        markLLMUsed(instance, config: config)
        Task { await refreshLLMStatus() }
    }

    private func markLLMUsed(_ id: String, config: LLMConfig) {
        llmStatus.markUsed(id)
        if let url = config.endpoint { usedLLMEndpoints[url, default: []].insert(id) }
    }

    private func forgetLLM(_ id: String, at url: URL) {
        usedLLMEndpoints[url]?.remove(id)
        if !usedLLMEndpoints.values.contains(where: { $0.contains(id) }) { llmStatus.forget(id) }
    }

    private func sameManagedModel(_ lhs: LLMConfig, _ rhs: LLMConfig) -> Bool {
        lhs.kind == rhs.kind && lhs.baseURL == rhs.baseURL && lhs.model == rhs.model
    }

    private func canUnload(_ config: LLMConfig, onlyUsedByApp: Bool, generation: UUID) -> Bool {
        !Task.isCancelled && !dictationBusy && generation == llmCleanupGeneration
            && (!onlyUsedByApp || !sameManagedModel(config, settings.llm))
    }

    private func waitForLLMUnloads(_ config: LLMConfig) async {
        guard let url = config.endpoint else { return }
        let pending = llmUnloads.values.filter { $0.url == url }.map(\.task)
        for task in pending { _ = try? await task.value }
    }

    /// Once sent, an unload may still succeed after selection changes. New
    /// preparation waits for its response before relying on instance discovery.
    private func unloadLLMInstance(_ id: String, at url: URL) async throws {
        let token = UUID()
        let task = Task {
            try await lmStudio.unload(baseURL: url, instanceID: id)
            forgetLLM(id, at: url)
        }
        llmUnloads[token] = (url, task)
        defer { llmUnloads[token] = nil }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @discardableResult
    private func unloadInstances(of config: LLMConfig, onlyUsedByApp: Bool, generation: UUID) async -> Bool {
        guard canUnload(config, onlyUsedByApp: onlyUsedByApp, generation: generation) else { return false }
        guard let url = await lmStudioURL(config) else { return true }
        guard canUnload(config, onlyUsedByApp: onlyUsedByApp, generation: generation) else { return false }
        do {
            let ids = try await lmStudio.instances(baseURL: url, modelKey: config.model)
            guard canUnload(config, onlyUsedByApp: onlyUsedByApp, generation: generation) else { return false }
            for id in ids where !onlyUsedByApp || usedLLMEndpoints[url]?.contains(id) == true {
                guard canUnload(config, onlyUsedByApp: onlyUsedByApp, generation: generation) else { return false }
                try await unloadLLMInstance(id, at: url)
                Self.log.notice("LLM unloaded instance=\(id, privacy: .public)")
            }
            return true
        } catch {
            if canUnload(config, onlyUsedByApp: onlyUsedByApp, generation: generation), settings.llm == config {
                llmStatus.set(.failed(error.localizedDescription))
            }
            Self.log.error("LLM unload failed; retaining instance for cleanup retry")
            return false
        }
    }

    // MARK: Quit

    /// Frees everything the app is responsible for. Bounded so quitting never hangs.
    func shutdown() async {
        speechLoadTask?.cancel()
        llmGeneration = UUID()
        llmCleanupGeneration = UUID()
        do {
            try await OperationDeadline.run(seconds: 5) { [self] in
                await factory.unloadAll()
                await CLIWarmPool.shared.shutdown()
                await self.unloadUsedLLMOnQuit()
            }
        } catch {
            Self.log.error("Model cleanup reached its deadline; allowing quit")
        }
    }

    private func unloadUsedLLMOnQuit() async {
        guard settings.unloadLLMOnQuit else { return }
        for (url, ids) in usedLLMEndpoints {
            for id in ids {
                do {
                    try await unloadLLMInstance(id, at: url)
                } catch {
                    Self.log.error("LLM cleanup failed")
                }
            }
        }
    }

    // MARK: Observation

    private func observe() {
        observeChanges({ [weak self] in
            guard let self else { return }
            _ = self.speechConfig
            _ = self.settings.llm
            _ = self.settings.idleUnloadMinutes
        }) { [weak self] in self?.handleSettingsChange() }
    }

    private func handleSettingsChange() {
        guard !dictationBusy else { return }
        Task { await factory.setIdleUnloadMinutes(settings.idleUnloadMinutes) }

        if speechConfig.engineID != lastASR?.engineID {
            loadSpeechModel()
        }
        lastASR = speechConfig

        let previous = lastLLM
        lastLLM = settings.llm
        if let previous, !sameManagedModel(previous, settings.llm) {
            llmGeneration = UUID()
            let cleanupToken = UUID()
            llmCleanupGeneration = cleanupToken
            llmStatus.set(.unknown)
            Task {
                // Unload what this app was using on the old endpoint or model.
                await unloadInstances(of: previous, onlyUsedByApp: true, generation: cleanupToken)
                if cleanupToken == llmCleanupGeneration { await refreshLLMStatus() }
            }
        }
    }
}
