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
    var speechConfig: ASRConfig { profiles.map { settings.speechConfig(for: $0.activeProfile) } ?? settings.asr }
    private let lmStudio = LMStudioControl()
    private var lastLLM: LLMConfig?
    private var lastASR: ASRConfig?
    private var speechLoadTask: Task<Void, Never>?
    private var llmCleanupGeneration = UUID()
    private(set) var dictationBusy = false
    private var started = false
    private var usedLLMEndpoints: [URL: Set<String>] = [:]
    private var llmUnloads: [UUID: (url: URL, id: String, task: Task<Void, Error>)] = [:]
    private var deferredLLMInstances: [URL: [String: LLMConfig]] = [:]
    private struct LLMPreparation {
        let config: LLMConfig
        let task: Task<RefinementPreparationBackend, Error>
        /// A captured dictation may need a model after the UI selection changes.
        var waiters: [UUID: Bool]
    }
    private var llmPreparations: [UUID: LLMPreparation] = [:]
    private var llmStopping = false
    private var unloadPendingLLM = false

    func setDictationBusy(_ busy: Bool) {
        if busy && !dictationBusy { llmCleanupGeneration = UUID() }
        dictationBusy = busy
        if !busy && started { handleSettingsChange() }
        if !busy && !llmStopping { cleanDeferredLLMInstances() }
    }

    init(settings: AppSettings, factory: EngineFactory, engineStatus: EngineStatus, profiles: ProfileStore? = nil) {
        self.settings = settings
        self.factory = factory
        self.engineStatus = engineStatus
        self.profiles = profiles
    }

    func start() {
        guard !started else { return }
        started = true
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

    func refreshLLMStatus() async {
        guard !llmStopping else { return }
        let config = settings.llm
        if config.kind.isCLI {
            llmStatus.set(.ready(config.cliExecutable == nil ? "CLI not found" : "Ready"))
            return
        }
        guard config.kind == .openAICompatible, let url = URL(string: config.baseURL) else {
            llmStatus.set(.remote)
            return
        }
        let snapshot: LMStudioControl.ModelSnapshot
        do { snapshot = try await lmStudio.modelSnapshot(baseURL: url, modelKey: config.model) }
        catch {
            guard config == settings.llm, !Task.isCancelled, !llmStopping else { return }
            llmStatus.set(.failed(error.localizedDescription))
            return
        }
        guard config == settings.llm, !Task.isCancelled, !llmStopping else { return }
        switch snapshot.server {
        case .unmanaged:
            llmStatus.set(.remote)
        case .unreachable:
            llmStatus.set(.unreachable)
        case .lmStudio:
            if case .loading = llmStatus.state { return }
            llmStatus.set(snapshot.instances.first.map { .loaded(instance: $0) } ?? .notLoaded)
        }
    }

    func loadLLM() {
        Task { await loadLLMIfNeeded() }
    }

    /// Recording and final refinement join the same discovery/load operation.
    /// Completed preparations are never cached: the next recording sees external unloads.
    func prepareLLM(config: LLMConfig) async throws {
        _ = try await prepareLLMBackend(config: config)
    }

    /// Reuses the same inventory that prepared the model to identify supported
    /// speculative work; callers must not discover the backend a second time.
    func prepareLLMBackend(config: LLMConfig) async throws -> RefinementPreparationBackend {
        try await prepareLLMBackend(config: config, followsSelection: false)
    }

    /// UI loads follow selection; captured dictations keep their original configuration.
    func loadLLMIfNeeded(config requestedConfig: LLMConfig? = nil) async {
        let config = requestedConfig ?? settings.llm
        do { _ = try await prepareLLMBackend(config: config, followsSelection: requestedConfig == nil) }
        catch is CancellationError {}
        catch { Self.log.error("LLM preparation failed: \(error.localizedDescription, privacy: .public)") }
    }

    private func prepareLLMBackend(config: LLMConfig, followsSelection: Bool) async throws -> RefinementPreparationBackend {
        try Task.checkCancellation()
        guard !llmStopping else { throw CancellationError() }
        guard config.kind == .openAICompatible, config.endpoint != nil else { return .unmanaged }
        let waiter = UUID()
        let token: UUID
        let task: Task<RefinementPreparationBackend, Error>
        if let pending = llmPreparations.first(where: { sameManagedModel($0.value.config, config) }) {
            token = pending.key
            task = pending.value.task
            llmPreparations[token]?.waiters[waiter] = !followsSelection
        } else {
            token = UUID()
            llmCleanupGeneration = UUID()
            task = Task { [self] in
                defer { llmPreparations[token] = nil }
                return try await performLLMPreparation(config, token: token)
            }
            llmPreparations[token] = .init(config: config, task: task, waiters: [waiter: !followsSelection])
        }
        defer { llmPreparations[token]?.waiters[waiter] = nil }
        // Cancel only this waiter. Cancelling the native load request can lose
        // the instance ID while LM Studio keeps loading it on the server.
        let backend = try await OperationDeadline.run(seconds: 300) { try await task.value }
        try Task.checkCancellation()
        return backend
    }

    private func preparationIsNeeded(_ config: LLMConfig, token: UUID) -> Bool {
        !llmStopping && (sameManagedModel(config, settings.llm)
            || llmPreparations[token]?.waiters.values.contains(true) == true)
    }

    private func performLLMPreparation(_ config: LLMConfig, token: UUID) async throws -> RefinementPreparationBackend {
        guard let url = config.endpoint else { return .unmanaged }
        await waitForLLMUnloads(config)
        guard preparationIsNeeded(config, token: token) else { throw CancellationError() }
        do {
            let snapshot = try await lmStudio.modelSnapshot(baseURL: url, modelKey: config.model)
            guard preparationIsNeeded(config, token: token) else { throw CancellationError() }
            switch snapshot.server {
            case .unmanaged:
                if sameManagedModel(config, settings.llm) { llmStatus.set(.remote) }
                return .unmanaged
            case .unreachable:
                if sameManagedModel(config, settings.llm) { llmStatus.set(.unreachable) }
                throw URLError(.cannotConnectToHost)
            case .lmStudio: break
            }
            if let existing = snapshot.instances.first {
                markLLMUsed(existing, config: config)
                if sameManagedModel(config, settings.llm) { llmStatus.set(.loaded(instance: existing)) }
                return .lmStudio
            }
            if sameManagedModel(config, settings.llm) { llmStatus.set(.loading) }
            let id = try await lmStudio.load(baseURL: url, modelKey: config.model)
            markLLMUsed(id, config: config)
            guard preparationIsNeeded(config, token: token) else {
                if (llmStopping && unloadPendingLLM)
                    || (!llmStopping && !dictationBusy && !sameManagedModel(config, settings.llm)) {
                    do { try await unloadLLMInstance(id, at: url) }
                    catch { Self.log.error("Stale LLM load cleanup failed; retaining instance for cleanup retry") }
                } else if !llmStopping && !sameManagedModel(config, settings.llm) {
                    // Do not interrupt another recording. Revisit this exact
                    // abandoned instance when the aggregate pipeline becomes idle.
                    deferredLLMInstances[url, default: [:]][id] = config
                }
                throw CancellationError()
            }
            if sameManagedModel(config, settings.llm) { llmStatus.set(.loaded(instance: id)) }
            Self.log.notice("LLM loaded instance=\(id, privacy: .public)")
            return .lmStudio
        } catch {
            if preparationIsNeeded(config, token: token), sameManagedModel(config, settings.llm),
               !(error is CancellationError), llmStatus.state != .unreachable {
                llmStatus.set(.failed(error.localizedDescription))
            }
            throw error
        }
    }

    func unloadLLM() {
        guard !dictationBusy else { return }
        let cleanupToken = UUID()
        llmCleanupGeneration = cleanupToken
        let config = settings.llm
        Task {
            await waitForLLMPreparations(config)
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
        deferredLLMInstances[url]?[id] = nil
        if !usedLLMEndpoints.values.contains(where: { $0.contains(id) }) { llmStatus.forget(id) }
    }

    private func cleanDeferredLLMInstances() {
        guard !deferredLLMInstances.isEmpty else { return }
        let pending = deferredLLMInstances
        let generation = llmCleanupGeneration
        Task {
            for (url, instances) in pending {
                for (id, config) in instances {
                    if sameManagedModel(config, settings.llm) {
                        deferredLLMInstances[url]?[id] = nil
                        continue
                    }
                    guard usedLLMEndpoints[url]?.contains(id) == true,
                          canUnload(config, onlyUsedByApp: true, generation: generation) else { continue }
                    do { try await unloadLLMInstance(id, at: url) }
                    catch { Self.log.error("Deferred LLM cleanup failed; retaining instance for cleanup retry") }
                }
            }
        }
    }

    private func sameManagedModel(_ lhs: LLMConfig, _ rhs: LLMConfig) -> Bool {
        lhs.kind == rhs.kind && lhs.baseURL == rhs.baseURL && lhs.model == rhs.model
    }

    private func canUnload(_ config: LLMConfig, onlyUsedByApp: Bool, generation: UUID) -> Bool {
        !Task.isCancelled && !dictationBusy && generation == llmCleanupGeneration
            && !llmPreparations.values.contains(where: { sameManagedModel($0.config, config) && $0.waiters.values.contains(true) })
            && (!onlyUsedByApp || !sameManagedModel(config, settings.llm))
    }

    private func waitForLLMUnloads(_ config: LLMConfig) async {
        guard let url = config.endpoint else { return }
        let pending = llmUnloads.values.filter { $0.url == url }.map(\.task)
        for task in pending { _ = try? await task.value }
    }

    private func waitForLLMPreparations(_ config: LLMConfig? = nil) async {
        let pending = llmPreparations.values.filter { preparation in
            config.map { sameManagedModel(preparation.config, $0) } ?? true
        }.map(\.task)
        for task in pending { _ = try? await task.value }
    }

    /// Once sent, an unload may still succeed after selection changes. New
    /// preparation waits for its response before relying on instance discovery.
    private func unloadLLMInstance(_ id: String, at url: URL) async throws {
        if let pending = llmUnloads.values.first(where: { $0.url == url && $0.id == id }) {
            try await pending.task.value
            return
        }
        let token = UUID()
        let task = Task {
            try await lmStudio.unload(baseURL: url, instanceID: id)
            forgetLLM(id, at: url)
        }
        llmUnloads[token] = (url, id, task)
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
        guard config.kind == .openAICompatible, let url = config.endpoint else { return true }
        do {
            let snapshot = try await lmStudio.modelSnapshot(baseURL: url, modelKey: config.model)
            guard snapshot.server == .lmStudio else { return true }
            let ids = snapshot.instances
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

    /// Stop pending automatic loads before reset removes their files.
    func prepareForDataReset() async throws {
        dictationBusy = true
        speechLoadTask?.cancel()
        llmStopping = true
        unloadPendingLLM = true
        llmCleanupGeneration = UUID()
        try await OperationDeadline.run(seconds: 30) { [self] in
            async let speech: Void = retireSpeechForReset()
            async let cli: Void = CLIWarmPool.shared.shutdown()
            async let llm: Void = waitForLLMPreparations()
            _ = await (speech, cli, llm)
        }
    }

    private func retireSpeechForReset() async {
        await speechLoadTask?.value
        await factory.unloadAll()
    }

    // MARK: Quit

    /// Frees everything the app is responsible for. Bounded so quitting never hangs.
    func shutdown() async {
        speechLoadTask?.cancel()
        llmStopping = true
        unloadPendingLLM = settings.unloadLLMOnQuit
        llmCleanupGeneration = UUID()
        do {
            try await OperationDeadline.run(seconds: 5) { [self] in
                async let speech: Void = factory.unloadAll()
                async let cli: Void = CLIWarmPool.shared.shutdown()
                async let llm: Void = retireLLMOnQuit()
                _ = await (speech, cli, llm)
            }
        } catch {
            Self.log.error("Model cleanup reached its deadline; allowing quit")
        }
    }

    private func retireLLMOnQuit() async {
        await waitForLLMPreparations()
        await unloadUsedLLMOnQuit()
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
