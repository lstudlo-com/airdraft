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
    private let lmStudio = LMStudioControl()
    private var lastLLM: LLMConfig?
    private var lastASR: ASRConfig?
    private var speechLoadTask: Task<Void, Never>?
    private var llmGeneration = UUID()
    private var dictationBusy = false

    func setDictationBusy(_ busy: Bool) {
        dictationBusy = busy
        if !busy { handleSettingsChange() }
    }

    init(settings: AppSettings, factory: EngineFactory, engineStatus: EngineStatus) {
        self.settings = settings
        self.factory = factory
        self.engineStatus = engineStatus
    }

    func start() {
        lastASR = settings.asr
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
        let config = settings.asr
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
    func llmNeedsLoad() async -> Bool {
        let config = settings.llm
        guard let url = await lmStudioURL(config) else { return false }
        return ((try? await lmStudio.instances(baseURL: url, modelKey: config.model)) ?? []).isEmpty
    }

    func loadLLM() {
        Task { await loadLLMIfNeeded() }
    }

    /// Loads the configured model in LM Studio unless an instance is already up.
    func loadLLMIfNeeded() async {
        let token = UUID()
        llmGeneration = token
        let config = settings.llm
        guard let url = await lmStudioURL(config) else { return await refreshLLMStatus() }
        if let existing = try? await lmStudio.instances(baseURL: url, modelKey: config.model).first {
            guard !Task.isCancelled, token == llmGeneration, settings.llm == config else { return }
            llmStatus.markUsed(existing)
            llmStatus.set(.loaded(instance: existing))
            return
        }
        // Set the outcome directly: refreshLLMStatus leaves a `.loading` state alone.
        guard !Task.isCancelled, token == llmGeneration, settings.llm == config else { return }
        llmStatus.set(.loading)
        do {
            let id = try await lmStudio.load(baseURL: url, modelKey: config.model)
            guard !Task.isCancelled, token == llmGeneration, settings.llm == config else {
                try? await lmStudio.unload(baseURL: url, instanceID: id)
                return
            }
            llmStatus.markUsed(id)
            llmStatus.set(.loaded(instance: id))
            Self.log.notice("LLM loaded instance=\(id, privacy: .public)")
        } catch {
            guard token == llmGeneration, settings.llm == config else { return }
            llmStatus.set(Task.isCancelled ? .notLoaded : .failed(error.localizedDescription))
        }
    }

    func unloadLLM() {
        guard !dictationBusy else { return }
        llmGeneration = UUID()
        Task {
            await unloadInstances(of: settings.llm, onlyUsedByApp: false)
            await refreshLLMStatus()
        }
    }

    func noteLLMUsed(_ instance: String) {
        // This set is used to unload LM Studio instances. Cloud provider names
        // reported by OpenRouter are not local model instance IDs.
        guard settings.llm.kind == .openAICompatible else { return }
        llmStatus.markUsed(instance)
        Task { await refreshLLMStatus() }
    }

    private func unloadInstances(of config: LLMConfig, onlyUsedByApp: Bool) async {
        guard let url = await lmStudioURL(config) else { return }
        let ids = (try? await lmStudio.instances(baseURL: url, modelKey: config.model)) ?? []
        for id in ids where !onlyUsedByApp || llmStatus.usedInstances.contains(id) {
            try? await lmStudio.unload(baseURL: url, instanceID: id)
            llmStatus.forget(id)
            Self.log.notice("LLM unloaded instance=\(id, privacy: .public)")
        }
    }

    // MARK: Quit

    /// Frees everything the app is responsible for. Bounded so quitting never hangs.
    func shutdown() async {
        speechLoadTask?.cancel()
        llmGeneration = UUID()
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
        guard settings.unloadLLMOnQuit,
              let url = URL(string: settings.llm.baseURL),
              !llmStatus.usedInstances.isEmpty else { return }
        for id in llmStatus.usedInstances {
            try? await lmStudio.unload(baseURL: url, instanceID: id)
        }
    }

    // MARK: Observation

    private func observe() {
        observeChanges({ [weak self] in
            guard let self else { return }
            _ = self.settings.asr
            _ = self.settings.llm
            _ = self.settings.idleUnloadMinutes
        }) { [weak self] in self?.handleSettingsChange() }
    }

    private func handleSettingsChange() {
        guard !dictationBusy else { return }
        Task { await factory.setIdleUnloadMinutes(settings.idleUnloadMinutes) }

        if settings.asr.engineID != lastASR?.engineID {
            loadSpeechModel()
        }
        lastASR = settings.asr

        let previous = lastLLM
        lastLLM = settings.llm
        if let previous, previous.model != settings.llm.model || previous.baseURL != settings.llm.baseURL || previous.kind != settings.llm.kind {
            Task {
                // Unload what this app was using on the old endpoint or model.
                await unloadInstances(of: previous, onlyUsedByApp: true)
                await refreshLLMStatus()
            }
        }
    }
}
