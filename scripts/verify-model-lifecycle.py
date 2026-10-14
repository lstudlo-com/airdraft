#!/usr/bin/env python3
"""Compile the real app lifecycle source against disposable, network-free test doubles."""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
repository = Path(__file__).resolve().parent.parent
parser.add_argument('--source', type=Path, default=repository / 'Sources/App/App/ModelLifecycle.swift')
parser.add_argument('--output', type=Path, help='Directory for generated Swift sources and executable; temporary by default')
args = parser.parse_args()
temporary = tempfile.TemporaryDirectory(prefix='airdraft-lifecycle-') if args.output is None else None
root = args.output.resolve() if args.output is not None else Path(temporary.name)
root.mkdir(parents=True, exist_ok=True)
source = args.source.read_text().replace('import AirdraftCore\n', '')
(root/'ModelLifecycle.swift').write_text(source)
explicit = 'func noteLLMUsed(_ instance: String, config: LLMConfig)' in source
call = 'lifecycle.noteLLMUsed(instance, config: config)' if explicit else 'lifecycle.noteLLMUsed(instance)'
load_call = 'try await lifecycle.prepareLLM(config: config)'
(root/'OperationDeadline.swift').write_text((repository/'Packages/AirdraftCore/Sources/AirdraftCore/Pipeline/OperationDeadline.swift').read_text())
stubs = r'''
import Foundation
import Observation
import Darwin

enum AppIdentity { static let logSubsystem = "airdraft.lifecycle.test" }
enum RefinementPreparationBackend: Sendable, Equatable { case unmanaged, lmStudio }
struct ASRConfig: Equatable {
    struct Kind: Equatable { var isLocal = true }
    var kind = Kind()
    var engineID = "fixture-speech"
}
enum LLMProviderKind: Equatable {
    case openAICompatible, none, cli
    var isCLI: Bool { self == .cli }
}
struct LLMConfig: Equatable {
    var kind: LLMProviderKind = .openAICompatible
    var baseURL: String
    var model = "fixture-model"
    var cliExecutable: String? = nil
    var temperature: Double = 0
    var endpoint: URL? { URL(string: baseURL) }
}
@MainActor @Observable final class AppSettings {
    var asr = ASRConfig()
    var llm = LLMConfig(baseURL: "http://127.0.0.1:9001/v1")
    var idleUnloadMinutes = 10
    var unloadLLMOnQuit = true
    func speechConfig(for profile: RefinementProfile) -> ASRConfig { profile.speechConfig(default: asr) }
}
@MainActor final class EngineStatus {}
struct RefinementProfile {
    var override: ASRConfig?
    func speechConfig(default appDefault: ASRConfig) -> ASRConfig { override ?? appDefault }
}
@MainActor @Observable final class ProfileStore {
    var activeProfile = RefinementProfile()
}
actor EngineFactory {
    var prepared: [String] = []
    var unloadCount = 0
    func prepare(_ config: ASRConfig) async throws { prepared.append(config.engineID) }
    func unloadAll() async { unloadCount += 1 }
    func setIdleUnloadMinutes(_ minutes: Int) async {}
}
@MainActor final class LLMStatus {
    enum State: Equatable {
        case unknown, ready(String), remote, unreachable, loaded(instance: String), loading, notLoaded, failed(String)
    }
    var state: State = .remote
    var usedInstances: Set<String> = []
    var isLoaded: Bool { if case .loaded = state { return true }; return false }
    func set(_ state: State) { self.state = state }
    func markUsed(_ id: String) { usedInstances.insert(id) }
    func forget(_ id: String) { usedInstances.remove(id) }
}
@MainActor func observeChanges(_ read: () -> Void, onChange: @escaping () -> Void) { read() }
enum RefinerError: Error { case timeout }
actor CLIWarmPool {
    static let shared = CLIWarmPool()
    var shutdownCount = 0
    func shutdown() async { shutdownCount += 1 }
}
@MainActor final class LMStudioControl {
    enum Kind { case lmStudio, unmanaged, unreachable }
    struct ModelSnapshot { let server: Kind; let instances: [String] }
    struct Call: Equatable { let url: URL; let id: String }
    static var unloadCalls: [Call] = []
    static var failures: [URL: Int] = [:]
    static var existing: [String] = []
    static var kind: Kind = .lmStudio
    static var loadFailures = 0
    static var onLoad: (() -> Void)?
    static var onLoading: (() async -> Void)?
    static var onInstances: ((URL, String) async -> Void)?
    static var onUnload: ((URL, String) async -> Void)?
    static var instanceCalls: [Call] = []
    static var snapshotCalls: [Call] = []
    static var loadCalls: [Call] = []
    static func reset() {
        unloadCalls = []; failures = [:]; existing = []; kind = .lmStudio; loadFailures = 0; onLoad = nil; onLoading = nil
        snapshotCalls = []
        onInstances = nil; onUnload = nil; instanceCalls = []; loadCalls = []
    }
    func serverKind(baseURL: URL) async -> Kind { .lmStudio }
    func modelSnapshot(baseURL: URL, modelKey: String) async throws -> ModelSnapshot {
        Self.snapshotCalls.append(.init(url: baseURL, id: modelKey))
        return .init(server: Self.kind, instances: try await instances(baseURL: baseURL, modelKey: modelKey))
    }
    func instances(baseURL: URL, modelKey: String) async throws -> [String] {
        Self.instanceCalls.append(.init(url: baseURL, id: modelKey))
        await Self.onInstances?(baseURL, modelKey)
        return Self.existing
    }
    func load(baseURL: URL, modelKey: String) async throws -> String {
        Self.loadCalls.append(.init(url: baseURL, id: modelKey))
        Self.onLoad?()
        await Self.onLoading?()
        if Self.loadFailures > 0 {
            Self.loadFailures -= 1
            throw NSError(domain: "fixture.load", code: 19)
        }
        return "loaded-instance"
    }
    func unload(baseURL: URL, instanceID: String) async throws {
        Self.unloadCalls.append(.init(url: baseURL, id: instanceID))
        await Self.onUnload?(baseURL, instanceID)
        if Self.failures[baseURL, default: 0] > 0 {
            Self.failures[baseURL, default: 0] -= 1
            throw NSError(domain: "fixture.unload", code: 17)
        }
    }
}
@MainActor func recordUse(_ lifecycle: ModelLifecycle, instance: String, config: LLMConfig) {
    __NOTE_CALL__
}
@MainActor func loadCaptured(_ lifecycle: ModelLifecycle, config: LLMConfig) async throws { __LOAD_CALL__ }
@MainActor final class DiscoveryGate {
    var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func suspend() async {
        guard !waiting else { return }
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
@MainActor func fixture() -> (AppSettings, ModelLifecycle) {
    let settings = AppSettings()
    let lifecycle = ModelLifecycle(settings: settings, factory: EngineFactory(), engineStatus: EngineStatus())
    return (settings, lifecycle)
}
struct VerificationFailure: Error { let message: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw VerificationFailure(message: message) }
}
@main struct VerifyModelLifecycle {
    @MainActor static func main() async {
        var failures = 0
        let checks: [(String, @MainActor () async throws -> Void)] = [
            ("profile speech selection loads after recording and restores app default", {
                let settings = AppSettings()
                let profiles = ProfileStore()
                profiles.activeProfile.override = ASRConfig(engineID: "profile-speech")
                let factory = EngineFactory()
                let lifecycle = ModelLifecycle(settings: settings, factory: factory, engineStatus: EngineStatus(), profiles: profiles)
                lifecycle.start()
                for _ in 0..<50 { await Task.yield() }
                var loaded = await factory.prepared
                try require(loaded == ["profile-speech"], "Startup did not use the profile model")
                lifecycle.setDictationBusy(true)
                profiles.activeProfile.override = nil
                lifecycle.loadSpeechModel()
                for _ in 0..<50 { await Task.yield() }
                loaded = await factory.prepared
                try require(loaded == ["profile-speech"], "Profile switch interrupted recording")
                lifecycle.setDictationBusy(false)
                for _ in 0..<50 { await Task.yield() }
                loaded = await factory.prepared
                try require(loaded == ["profile-speech", "fixture-speech"], "Opt-out did not restore the app default")
                await lifecycle.shutdown()
            }),
            ("in-flight refinement keeps original endpoint", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                recordUse(lifecycle, instance: "served-old", config: original)
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls == [.init(url: original.endpoint!, id: "served-old")], "Result was attributed to the changed endpoint")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Successful cleanup was not forgotten")
            }),
            ("existing loaded instance is tracked across provider switch", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                LMStudioControl.existing = ["already-loaded"]
                await lifecycle.loadLLMIfNeeded()
                settings.llm.kind = .none
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls == [.init(url: original.endpoint!, id: "already-loaded")], "Existing instance was not tracked")
            }),
            ("failed stale load cleanup remains retryable", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                LMStudioControl.failures[original.endpoint!] = 1
                LMStudioControl.onLoad = { settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1") }
                await lifecycle.loadLLMIfNeeded()
                try require(lifecycle.llmStatus.usedInstances.contains("loaded-instance"), "Failed stale cleanup forgot its instance")
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls == [.init(url: original.endpoint!, id: "loaded-instance"), .init(url: original.endpoint!, id: "loaded-instance")], "Quit did not retry the original endpoint")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Successful retry remained tracked")
            }),
            ("successful stale load cleanup is not retried", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                LMStudioControl.onLoad = { settings.llm.kind = .none }
                await lifecycle.loadLLMIfNeeded()
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls == [.init(url: original.endpoint!, id: "loaded-instance")], "Successful cleanup was repeated")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Cleaned instance remained tracked")
            }),
            ("unload failure stays visible and retryable", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                LMStudioControl.existing = ["used"]
                LMStudioControl.failures[original.endpoint!] = 1
                recordUse(lifecycle, instance: "used", config: original)
                for _ in 0..<20 { await Task.yield() }
                lifecycle.unloadLLM()
                for _ in 0..<100 { await Task.yield() }
                if case .failed = lifecycle.llmStatus.state {} else { throw VerificationFailure(message: "Unload failure was overwritten by refresh") }
                try require(lifecycle.llmStatus.usedInstances.contains("used"), "Failed unload forgot its instance")
                settings.llm.kind = .none
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls.count == 2, "Shutdown did not retry failed unload")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Successful retry remained tracked")
            }),
            ("same instance id on two endpoints is tracked separately", {
                let (settings, lifecycle) = fixture()
                let first = settings.llm
                let second = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                recordUse(lifecycle, instance: "shared-id", config: first)
                settings.llm = second
                recordUse(lifecycle, instance: "shared-id", config: second)
                LMStudioControl.failures[second.endpoint!] = 1
                await lifecycle.shutdown()
                try require(lifecycle.llmStatus.usedInstances.contains("shared-id"), "Cleanup of one endpoint forgot another endpoint's instance")
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls.filter { $0.url == first.endpoint! }.count == 1, "Successful endpoint was retried")
                try require(LMStudioControl.unloadCalls.filter { $0.url == second.endpoint! }.count == 2, "Failed endpoint was not retried")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Successful cleanup remained tracked")
            }),
            ("explicit unload snapshots endpoint before task launch", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                LMStudioControl.existing = ["used"]
                recordUse(lifecycle, instance: "used", config: original)
                lifecycle.unloadLLM()
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls == [.init(url: original.endpoint!, id: "used")], "Explicit unload moved to the newly selected endpoint")
            }),
            ("switching model during load clears the stale loading state", {
                let (settings, lifecycle) = fixture()
                lifecycle.start()
                for _ in 0..<50 { await Task.yield() }
                LMStudioControl.onLoad = {
                    settings.llm.model = "replacement-model"
                    lifecycle.setDictationBusy(false)
                }
                await lifecycle.loadLLMIfNeeded()
                for _ in 0..<100 { await Task.yield() }
                try require(lifecycle.llmStatus.state == .notLoaded, "The replacement model remained in the old model's loading state")
                await lifecycle.shutdown()
            }),
            ("disabled unload-on-quit leaves instance untouched", {
                let (settings, lifecycle) = fixture()
                recordUse(lifecycle, instance: "used", config: settings.llm)
                settings.unloadLLMOnQuit = false
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls.isEmpty, "Disabled unload setting was ignored")
                try require(lifecycle.llmStatus.usedInstances.contains("used"), "Unused cleanup incorrectly forgot the instance")
            }),
            ("switching back during cleanup discovery cannot unload the active model", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                lifecycle.start()
                LMStudioControl.existing = ["used"]
                recordUse(lifecycle, instance: "used", config: original)
                for _ in 0..<50 { await Task.yield() }
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onInstances = { url, _ in
                    if url == original.endpoint! { await gate.suspend() }
                }
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                lifecycle.setDictationBusy(false)
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting, "Cleanup did not reach delayed discovery")
                settings.llm = original
                lifecycle.setDictationBusy(false)
                lifecycle.setDictationBusy(true)
                gate.release()
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls.isEmpty, "Stale cleanup unloaded the reselected model during dictation")
                try require(lifecycle.llmStatus.usedInstances.contains("used"), "Skipped cleanup forgot the active instance")
            }),
            ("starting dictation during explicit unload discovery cancels cleanup", {
                let (settings, lifecycle) = fixture()
                LMStudioControl.existing = ["used"]
                recordUse(lifecycle, instance: "used", config: settings.llm)
                for _ in 0..<50 { await Task.yield() }
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onInstances = { _, _ in await gate.suspend() }
                lifecycle.unloadLLM()
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting, "Explicit unload did not reach delayed discovery")
                lifecycle.setDictationBusy(true)
                gate.release()
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls.isEmpty, "Pending explicit unload interrupted a new dictation")
            }),
            ("dictation loading uses its captured configuration without changing selected status", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1", model: "replacement")
                lifecycle.llmStatus.set(.ready("selected replacement"))
                try await loadCaptured(lifecycle, config: original)
                try require(LMStudioControl.snapshotCalls.count == 1, "Captured preparation repeated model discovery")
                try require(LMStudioControl.instanceCalls.allSatisfy { $0.url == original.endpoint! && $0.id == original.model }, "Discovery used the newer selection")
                try require(LMStudioControl.loadCalls == [.init(url: original.endpoint!, id: original.model)], "Load used the newer selection")
                try require(lifecycle.llmStatus.state == .ready("selected replacement"), "Background loading overwrote selected-model status")
                try require(LMStudioControl.unloadCalls.isEmpty, "Captured model was unloaded before refinement")
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls == [.init(url: original.endpoint!, id: "loaded-instance")], "Captured model was not tracked for cleanup")
            }),
            ("preparation waits for an already-started unload before checking readiness", {
                let (settings, lifecycle) = fixture()
                let original = settings.llm
                LMStudioControl.existing = ["used"]
                recordUse(lifecycle, instance: "used", config: original)
                for _ in 0..<50 { await Task.yield() }
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onUnload = { _, _ in
                    await gate.suspend()
                    LMStudioControl.existing = []
                }
                lifecycle.unloadLLM()
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting, "Unload request did not start")
                lifecycle.setDictationBusy(true)
                let discoveryCount = LMStudioControl.instanceCalls.count
                var prepared = false
                let preparation = Task {
                    try await loadCaptured(lifecycle, config: original)
                    prepared = true
                }
                for _ in 0..<100 { await Task.yield() }
                let waited = !prepared && LMStudioControl.instanceCalls.count == discoveryCount
                gate.release()
                try await preparation.value
                try require(waited, "Preparation reported ready while its instance was still unloading")
                try require(LMStudioControl.loadCalls == [.init(url: original.endpoint!, id: original.model)], "Preparation did not reload after unload finished")
            }),
            ("overlapping explicit unloads share one native request", {
                let (settings, lifecycle) = fixture()
                LMStudioControl.existing = ["used"]
                recordUse(lifecycle, instance: "used", config: settings.llm)
                for _ in 0..<50 { await Task.yield() }
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onUnload = { _, _ in await gate.suspend() }
                lifecycle.unloadLLM()
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting, "First unload did not start")
                lifecycle.unloadLLM()
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls.count == 1, "Overlapping cleanup sent two native unloads")
                gate.release()
                for _ in 0..<100 { await Task.yield() }
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls.count == 1, "Successful shared cleanup was repeated on quit")
            }),
            ("recording and final refinement share one discovery and native load", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onInstances = { _, _ in await gate.suspend() }
                let first = Task { try await lifecycle.prepareLLMBackend(config: config) }
                for _ in 0..<100 { await Task.yield() }
                let second = Task { try await lifecycle.prepareLLMBackend(config: config) }
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting && LMStudioControl.snapshotCalls.count == 1, "Concurrent preparation repeated discovery")
                gate.release()
                let firstBackend = try await first.value
                let secondBackend = try await second.value
                try require(firstBackend == .lmStudio && secondBackend == .lmStudio, "Joined preparation lost its discovered backend metadata")
                try require(LMStudioControl.loadCalls.count == 1, "Concurrent preparation loaded two native instances")
                await lifecycle.shutdown()
            }),
            ("cancelling one waiter returns promptly without poisoning the shared load", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                var cancelled = false
                let first = Task {
                    do { try await loadCaptured(lifecycle, config: config) }
                    catch is CancellationError { cancelled = true }
                }
                for _ in 0..<100 { await Task.yield() }
                var secondFinished = false
                let second = Task {
                    try await loadCaptured(lifecycle, config: config)
                    secondFinished = true
                }
                for _ in 0..<100 { await Task.yield() }
                first.cancel()
                for _ in 0..<100 { await Task.yield() }
                try require(cancelled && !secondFinished, "Cancelled waiter remained blocked on native loading")
                try require(LMStudioControl.loadCalls.count == 1, "Cancellation restarted or duplicated native loading")
                gate.release()
                try await first.value
                try await second.value
                try require(secondFinished && lifecycle.llmStatus.isLoaded, "Cancellation poisoned the other waiter")
                await lifecycle.shutdown()
            }),
            ("cancelled abandoned preparation cleans its late native instance", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try? await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                preparation.cancel()
                await preparation.value
                gate.release()
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls == [.init(url: config.endpoint!, id: "loaded-instance")], "Abandoned load leaked or unloaded the wrong endpoint")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Successful late cleanup was not forgotten")
                await lifecycle.shutdown()
            }),
            ("completed preparation sees an external unload on the next request", {
                let (settings, lifecycle) = fixture()
                LMStudioControl.existing = ["external-instance"]
                try await loadCaptured(lifecycle, config: settings.llm)
                LMStudioControl.existing = []
                try await loadCaptured(lifecycle, config: settings.llm)
                try require(LMStudioControl.snapshotCalls.count == 2, "Completed readiness was cached after an external unload")
                try require(LMStudioControl.loadCalls.count == 1, "External unload did not cause preparation to reload")
                await lifecycle.shutdown()
            }),
            ("abandoned load finishing during another recording cleans up when idle", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try? await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                preparation.cancel()
                await preparation.value
                lifecycle.setDictationBusy(true)
                gate.release()
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls.isEmpty, "Abandoned load cleanup interrupted the new recording")
                lifecycle.setDictationBusy(false)
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls == [.init(url: config.endpoint!, id: "loaded-instance")], "Idle transition leaked the abandoned native instance")
                await lifecycle.shutdown()
                try require(LMStudioControl.unloadCalls.count == 1, "Successful deferred cleanup was repeated on quit")
            }),
            ("deferred cleanup protects a reselected model", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try? await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                preparation.cancel()
                await preparation.value
                lifecycle.setDictationBusy(true)
                gate.release()
                for _ in 0..<100 { await Task.yield() }
                settings.llm = config
                lifecycle.setDictationBusy(false)
                for _ in 0..<100 { await Task.yield() }
                try require(LMStudioControl.unloadCalls.isEmpty, "Deferred cleanup unloaded the reselected native model")
                await lifecycle.shutdown()
            }),
            ("captured waiter keeps a joined UI load after selection changes", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onInstances = { _, _ in await gate.suspend() }
                let ui = Task { await lifecycle.loadLLMIfNeeded() }
                for _ in 0..<100 { await Task.yield() }
                let captured = Task { try await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                settings.llm = LLMConfig(baseURL: "http://127.0.0.1:9002/v1")
                lifecycle.llmStatus.set(.ready("replacement"))
                gate.release()
                await ui.value
                try await captured.value
                try require(LMStudioControl.loadCalls.count == 1 && LMStudioControl.snapshotCalls.count == 1, "Joined captured load was discarded or repeated")
                try require(LMStudioControl.unloadCalls.isEmpty, "UI selection change unloaded a model required by captured refinement")
                try require(lifecycle.llmStatus.state == .ready("replacement"), "Captured load overwrote new selection status")
                await lifecycle.shutdown()
            }),
            ("changing inference options during native loading still publishes model readiness", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                settings.llm.temperature = 0.4
                gate.release()
                try await preparation.value
                try require(lifecycle.llmStatus.isLoaded, "An unrelated inference setting left the model stuck loading")
                try require(LMStudioControl.unloadCalls.isEmpty, "An unrelated inference setting unloaded the model")
                await lifecycle.shutdown()
            }),
            ("quit waits for pending native loading and cleans its late instance", {
                let settings = AppSettings()
                let factory = EngineFactory()
                let lifecycle = ModelLifecycle(settings: settings, factory: factory, engineStatus: EngineStatus())
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try? await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                let cliBefore = await CLIWarmPool.shared.shutdownCount
                var finished = false
                let quit = Task { await lifecycle.shutdown(); finished = true }
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting && !finished && LMStudioControl.unloadCalls.isEmpty, "Quit skipped pending instance ownership")
                let speechUnloads = await factory.unloadCount
                let cliAfter = await CLIWarmPool.shared.shutdownCount
                try require(speechUnloads == 1 && cliAfter == cliBefore + 1, "Pending remote load starved independent speech/CLI quit cleanup")
                gate.release()
                await preparation.value
                await quit.value
                try require(LMStudioControl.unloadCalls == [.init(url: config.endpoint!, id: "loaded-instance")], "Quit lost or repeated late-instance cleanup")
                try require(lifecycle.llmStatus.usedInstances.isEmpty, "Quit retained a successfully cleaned late instance")
            }),
            ("quit preference also protects an instance still loading", {
                let (settings, lifecycle) = fixture()
                let config = settings.llm
                settings.unloadLLMOnQuit = false
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try? await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                let quit = Task { await lifecycle.shutdown() }
                for _ in 0..<100 { await Task.yield() }
                gate.release()
                await preparation.value
                await quit.value
                try require(LMStudioControl.unloadCalls.isEmpty, "Pending load ignored disabled quit cleanup")
                try require(lifecycle.llmStatus.usedInstances.contains("loaded-instance"), "Untouched pending instance ownership was lost")
            }),
            ("late status discovery cannot publish readiness after shutdown", {
                let (_, lifecycle) = fixture()
                lifecycle.llmStatus.set(.unknown)
                LMStudioControl.existing = ["external-instance"]
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onInstances = { _, _ in await gate.suspend() }
                let refresh = Task { await lifecycle.refreshLLMStatus() }
                for _ in 0..<100 { await Task.yield() }
                try require(gate.waiting, "Status discovery did not reach the shutdown race")
                await lifecycle.shutdown()
                gate.release()
                await refresh.value
                try require(lifecycle.llmStatus.state == .unknown, "Late discovery published readiness after shutdown")
            }),
            ("reset drains pending model preparation before removing files", {
                let settings = AppSettings()
                let factory = EngineFactory()
                let lifecycle = ModelLifecycle(settings: settings, factory: factory, engineStatus: EngineStatus())
                let config = settings.llm
                let gate = DiscoveryGate()
                defer { gate.release() }
                LMStudioControl.onLoading = { await gate.suspend() }
                let preparation = Task { try? await loadCaptured(lifecycle, config: config) }
                for _ in 0..<100 { await Task.yield() }
                let cliBefore = await CLIWarmPool.shared.shutdownCount
                var resetFinished = false
                let reset = Task { try await lifecycle.prepareForDataReset(); resetFinished = true }
                for _ in 0..<100 { await Task.yield() }
                try require(!resetFinished, "Reset returned while its model was still loading")
                let speechUnloads = await factory.unloadCount
                let cliAfter = await CLIWarmPool.shared.shutdownCount
                try require(speechUnloads == 1 && cliAfter == cliBefore + 1, "Pending remote load starved independent speech/CLI reset cleanup")
                gate.release()
                await preparation.value
                try await reset.value
                try require(resetFinished && LMStudioControl.unloadCalls == [.init(url: config.endpoint!, id: "loaded-instance")], "Reset failed to retire pending native preparation")
            }),
            ("failed preparation is retryable without a stale readiness cache", {
                let (settings, lifecycle) = fixture()
                LMStudioControl.loadFailures = 1
                do {
                    try await loadCaptured(lifecycle, config: settings.llm)
                    throw VerificationFailure(message: "Native load failure was swallowed")
                } catch let failure as VerificationFailure { throw failure }
                catch {}
                try await loadCaptured(lifecycle, config: settings.llm)
                try require(LMStudioControl.snapshotCalls.count == 2 && LMStudioControl.loadCalls.count == 2, "Failed preparation was reused instead of retried")
                try require(lifecycle.llmStatus.isLoaded, "Retry did not replace failed status")
                await lifecycle.shutdown()
            }),
            ("unmanaged and unavailable servers never receive native loads", {
                let (settings, lifecycle) = fixture()
                LMStudioControl.kind = .unmanaged
                try await loadCaptured(lifecycle, config: settings.llm)
                try require(lifecycle.llmStatus.state == .remote, "Unmanaged server was not preserved")
                LMStudioControl.kind = .unreachable
                do {
                    try await loadCaptured(lifecycle, config: settings.llm)
                    throw VerificationFailure(message: "Unreachable preparation was treated as ready")
                } catch let failure as VerificationFailure { throw failure }
                catch {}
                try require(LMStudioControl.loadCalls.isEmpty && lifecycle.llmStatus.state == .unreachable, "Unavailable server received a native load or wrong state")
                await lifecycle.shutdown()
            }),
            ("backend classification comes from one fresh preparation snapshot", {
                let (settings, lifecycle) = fixture()
                LMStudioControl.existing = ["external-instance"]
                let loaded = try await lifecycle.prepareLLMBackend(config: settings.llm)
                try require(loaded == .lmStudio, "An existing LM Studio instance lost backend classification")
                try require(LMStudioControl.snapshotCalls.count == 1 && LMStudioControl.loadCalls.isEmpty, "Backend metadata required a second inventory query")
                LMStudioControl.kind = .unmanaged
                let changed = try await lifecycle.prepareLLMBackend(config: settings.llm)
                try require(changed == .unmanaged, "Completed preparation cached stale backend classification")
                try require(LMStudioControl.snapshotCalls.count == 2 && LMStudioControl.loadCalls.isEmpty, "Fresh classification repeated discovery or loaded an unmanaged server")
                await lifecycle.shutdown()
            }),
            ("non-native providers are classified without contacting an endpoint", {
                let (settings, lifecycle) = fixture()
                var config = settings.llm
                config.kind = .cli
                let cli = try await lifecycle.prepareLLMBackend(config: config)
                config.kind = .none
                let disabled = try await lifecycle.prepareLLMBackend(config: config)
                try require(cli == .unmanaged && disabled == .unmanaged, "Non-native provider gained LM Studio preparation privileges")
                try require(LMStudioControl.snapshotCalls.isEmpty && LMStudioControl.loadCalls.isEmpty, "Non-native classification contacted an endpoint")
                await lifecycle.shutdown()
            }),
        ]
        for (name, check) in checks {
            LMStudioControl.reset()
            do {
                try await check()
                print("PASS: \(name)")
            } catch {
                failures += 1
                print("FAIL: \(name): \(error)")
            }
            for _ in 0..<50 { await Task.yield() }
        }
        print("\(checks.count) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
'''.replace('__NOTE_CALL__', call).replace('__LOAD_CALL__', load_call)
(root/'Verification.swift').write_text(stubs)
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(root/'ModelLifecycle.swift'), str(root/'OperationDeadline.swift'), str(root/'Verification.swift'), '-o', str(root/'verify')], check=True, timeout=60)
result = subprocess.run([str(root/'verify')], timeout=30)
raise SystemExit(result.returncode)
