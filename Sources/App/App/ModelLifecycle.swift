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
    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "models")

    let engineStatus: EngineStatus
    let llmStatus = LLMStatus()
    private let factory: EngineFactory
    private let settings: AppSettings
    private let lmStudio = LMStudioControl()
    private var lastLLM: LLMConfig?
    private var lastASR: ASRConfig?

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
        let config = settings.asr
        guard config.kind.isLocal else { return unloadSpeechModels() }
        Task {
            do { try await factory.prepare(config) }
            catch { Self.log.error("speech load failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func unloadSpeechModels() {
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
        switch await lmStudio.serverKind(baseURL: url) {
        case .unmanaged:
            llmStatus.set(.remote)
        case .unreachable:
            llmStatus.set(.unreachable)
        case .lmStudio:
            if case .loading = llmStatus.state { return }
            do {
                let instances = try await lmStudio.instances(baseURL: url, modelKey: config.model)
                llmStatus.set(instances.first.map { .loaded(instance: $0) } ?? .notLoaded)
            } catch {
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
        let config = settings.llm
        guard let url = await lmStudioURL(config) else { return await refreshLLMStatus() }
        if let existing = try? await lmStudio.instances(baseURL: url, modelKey: config.model).first {
            llmStatus.markUsed(existing)
            llmStatus.set(.loaded(instance: existing))
            return
        }
        // Set the outcome directly: refreshLLMStatus leaves a `.loading` state alone.
        llmStatus.set(.loading)
        do {
            let id = try await lmStudio.load(baseURL: url, modelKey: config.model)
            llmStatus.markUsed(id)
            llmStatus.set(.loaded(instance: id))
            Self.log.notice("LLM loaded instance=\(id, privacy: .public)")
        } catch {
            llmStatus.set(.failed(error.localizedDescription))
        }
    }

    func unloadLLM() {
        Task {
            await unloadInstances(of: settings.llm, onlyUsedByApp: false)
            await refreshLLMStatus()
        }
    }

    func noteLLMUsed(_ instance: String) {
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
        await factory.unloadAll()
        await CLIWarmPool.shared.shutdown()
        guard settings.unloadLLMOnQuit,
              let url = URL(string: settings.llm.baseURL),
              !llmStatus.usedInstances.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for id in await self.llmStatus.usedInstances {
                    try? await self.lmStudio.unload(baseURL: url, instanceID: id)
                    Self.log.notice("quit: unloaded LLM instance=\(id, privacy: .public)")
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(4)) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: Observation

    private func observe() {
        withObservationTracking {
            _ = settings.asr
            _ = settings.llm
            _ = settings.idleUnloadMinutes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.handleSettingsChange()
                self.observe()
            }
        }
    }

    private func handleSettingsChange() {
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
