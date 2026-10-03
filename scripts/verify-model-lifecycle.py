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
captured = 'func llmNeedsLoad(config:' in source
needs_call = 'await lifecycle.llmNeedsLoad(config: config)' if captured else 'await lifecycle.llmNeedsLoad()'
load_call = 'await lifecycle.loadLLMIfNeeded(config: config)' if captured else 'await lifecycle.loadLLMIfNeeded()'
stubs = r'''
import Foundation
import Observation
import Darwin

enum AppIdentity { static let logSubsystem = "airdraft.lifecycle.test" }
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
    var endpoint: URL? { URL(string: baseURL) }
}
@MainActor @Observable final class AppSettings {
    var asr = ASRConfig()
    var llm = LLMConfig(baseURL: "http://127.0.0.1:9001/v1")
    var idleUnloadMinutes = 10
    var unloadLLMOnQuit = true
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
    func prepare(_ config: ASRConfig) async throws { prepared.append(config.engineID) }
    func unloadAll() async {}
    func setIdleUnloadMinutes(_ minutes: Int) async {}
}
@MainActor final class LLMStatus {
    enum State: Equatable {
        case unknown, ready(String), remote, unreachable, loaded(instance: String), loading, notLoaded, failed(String)
    }
    var state: State = .remote
    var usedInstances: Set<String> = []
    func set(_ state: State) { self.state = state }
    func markUsed(_ id: String) { usedInstances.insert(id) }
    func forget(_ id: String) { usedInstances.remove(id) }
}
@MainActor func observeChanges(_ read: () -> Void, onChange: @escaping () -> Void) { read() }
enum OperationDeadline {
    static func run<Value: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await operation()
    }
}
actor CLIWarmPool {
    static let shared = CLIWarmPool()
    func shutdown() async {}
}
@MainActor final class LMStudioControl {
    enum Kind { case lmStudio, unmanaged, unreachable }
    struct Call: Equatable { let url: URL; let id: String }
    static var unloadCalls: [Call] = []
    static var failures: [URL: Int] = [:]
    static var existing: [String] = []
    static var onLoad: (() -> Void)?
    static var onInstances: ((URL, String) async -> Void)?
    static var onUnload: ((URL, String) async -> Void)?
    static var instanceCalls: [Call] = []
    static var loadCalls: [Call] = []
    static func reset() {
        unloadCalls = []; failures = [:]; existing = []; onLoad = nil
        onInstances = nil; onUnload = nil; instanceCalls = []; loadCalls = []
    }
    func serverKind(baseURL: URL) async -> Kind { .lmStudio }
    func instances(baseURL: URL, modelKey: String) async throws -> [String] {
        Self.instanceCalls.append(.init(url: baseURL, id: modelKey))
        await Self.onInstances?(baseURL, modelKey)
        return Self.existing
    }
    func load(baseURL: URL, modelKey: String) async throws -> String {
        Self.loadCalls.append(.init(url: baseURL, id: modelKey))
        Self.onLoad?()
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
@MainActor func needsLoad(_ lifecycle: ModelLifecycle, config: LLMConfig) async -> Bool { __NEEDS_CALL__ }
@MainActor func loadCaptured(_ lifecycle: ModelLifecycle, config: LLMConfig) async { __LOAD_CALL__ }
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
                let needed = await needsLoad(lifecycle, config: original)
                try require(needed, "Missing captured model did not need loading")
                await loadCaptured(lifecycle, config: original)
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
                    if await needsLoad(lifecycle, config: original) { await loadCaptured(lifecycle, config: original) }
                    prepared = true
                }
                for _ in 0..<100 { await Task.yield() }
                let waited = !prepared && LMStudioControl.instanceCalls.count == discoveryCount
                gate.release()
                await preparation.value
                try require(waited, "Preparation reported ready while its instance was still unloading")
                try require(LMStudioControl.loadCalls == [.init(url: original.endpoint!, id: original.model)], "Preparation did not reload after unload finished")
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
'''.replace('__NOTE_CALL__', call).replace('__NEEDS_CALL__', needs_call).replace('__LOAD_CALL__', load_call)
(root/'Verification.swift').write_text(stubs)
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(root/'ModelLifecycle.swift'), str(root/'Verification.swift'), '-o', str(root/'verify')], check=True, timeout=60)
result = subprocess.run([str(root/'verify')], timeout=30)
raise SystemExit(result.returncode)
