import AppKit
import Foundation
import AirdraftCore
import os

/// Drives the real pipeline without a hotkey so the result can be verified
/// from the log and the history database. Never inserts text.
@MainActor
enum SelfTest {
    static func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : -1
    }

    /// Load speech model -> unload -> load LLM -> quit (quit must unload the LLM).
    static func runLifecycle(_ c: AppContainer, restoring originalASR: ASRConfig) {
        Task {
            let id = c.settings.asr.engineID
            log.notice("lifecycle: start rss=\(residentMB())MB engine=\(id, privacy: .public)")
            try? await c.factory.prepare(c.settings.asr)
            log.notice("lifecycle: speech \(c.engineStatus.state(for: id).label, privacy: .public) rss=\(residentMB())MB")
            await c.factory.unloadAll()
            try? await Task.sleep(for: .seconds(2))
            log.notice("lifecycle: speech \(c.engineStatus.state(for: id).label, privacy: .public) rss=\(residentMB())MB")
            await c.models.refreshLLMStatus()
            log.notice("lifecycle: llm before=\(c.models.llmStatus.label, privacy: .public)")
            await c.models.loadLLMIfNeeded()
            log.notice("lifecycle: llm after load=\(c.models.llmStatus.label, privacy: .public) used=\(c.models.llmStatus.usedInstances.sorted().joined(separator: ","), privacy: .public)")
            log.notice("lifecycle: quitting")
            c.settings.asr = originalASR
            NSApp.terminate(nil)
        }
    }

    /// Open the main window -> the app must be a regular app; close it -> back to menu-bar only.
    static func runWindow(_ c: AppContainer) {
        Task {
            try? await Task.sleep(for: .seconds(1))
            c.showMainWindow()
            try? await Task.sleep(for: .seconds(1.5))
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            log.notice("window: open policy=\(NSApp.activationPolicy().rawValue) frontmost=\(front, privacy: .public)")
            NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }?.close()
            try? await Task.sleep(for: .seconds(1))
            log.notice("window: closed policy=\(NSApp.activationPolicy().rawValue)")
            NSApp.terminate(nil)
        }
    }

    /// One refinement through whichever provider is configured: proves the request
    /// shape is accepted, and times it.
    static func runLLM(_ c: AppContainer) {
        Task {
            let config = c.settings.llm
            guard let refiner = await c.factory.refiner(for: config) else {
                log.error("llm: no refiner for \(config.engineLabel, privacy: .public)")
                NSApp.terminate(nil)
                return
            }
            let request = RefineRequest(
                transcript: "嗯 那個 我們今天要討論三件事 第一 專案進度 第二 預算問題 第三 下週排程",
                profile: c.profiles.activeProfile,
                baseRules: c.profiles.baseRules,
                context: .empty, family: .general, dictionary: []
            )
            let started = Date()
            do {
                let result = try await refiner.refine(request)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                log.notice("llm: OK \(config.engineLabel, privacy: .public) effort=\(config.thinkingEffort.rawValue, privacy: .public) \(ms)ms servedBy=\(result.servedBy ?? "-", privacy: .public) text=\(result.text, privacy: .public)")
            } catch {
                log.error("llm: FAILED \(config.engineLabel, privacy: .public) \(error.localizedDescription, privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }

    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "selftest")

    static func run(mode: String) {
        let container = AppContainer.shared
        container.pipeline.insertionEnabled = false

        // AIRDRAFT_SELFTEST_ASR=<ASRProviderKind raw value>[:model or locale], e.g. qwen3:<modelId>,
        // whisperKit, senseVoice, apple:en-US, openAICompatible. Restored on exit.
        let originalASR = container.settings.asr
        if let engine = ProcessInfo.processInfo.environment["AIRDRAFT_SELFTEST_ASR"] {
            let parts = engine.split(separator: ":", maxSplits: 1).map(String.init)
            if let kind = ASRProviderKind(rawValue: parts[0]) {
                container.settings.asr.kind = kind
                if parts.count > 1 {
                    switch kind {
                    case .qwen3: container.settings.asr.qwen3Model = parts[1]
                    case .cohere: container.settings.asr.cohereModel = parts[1]
                    case .whisperKit: container.settings.asr.whisperModel = parts[1]
                    case .apple: container.settings.asr.appleLocale = parts[1]
                    default: break
                    }
                }
            }
            log.notice("self-test: engine override \(container.settings.asr.engineLabel, privacy: .public)")
        }
        container.pipeline.onOutcome = { outcome in
            log.notice("outcome raw=\(outcome.raw, privacy: .public)")
            log.notice("outcome final=\(outcome.final, privacy: .public) asrMs=\(outcome.asrMs) llmMs=\(outcome.llmMs) skipped=\(outcome.llmSkippedReason ?? "-", privacy: .public)")
        }
        if mode == "llm" {
            runLLM(container)
            return
        }
        if mode == "window" {
            runWindow(container)
            return
        }
        if mode == "lifecycle" {
            runLifecycle(container, restoring: originalASR)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if mode == "mic" {
                log.notice("self-test: recording from microphone for 3 s")
                container.pipeline.startRecording()
                try? await Task.sleep(for: .seconds(3))
                container.pipeline.stopAndProcess()
            } else {
                do {
                    let samples = try AudioFile.load(path: mode)
                    log.notice("self-test: processing \(mode, privacy: .public) (\(samples.count) samples)")
                    container.pipeline.processSamples(samples, context: AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack"))
                } catch {
                    log.error("self-test: could not load audio: \(error.localizedDescription, privacy: .public)")
                    NSApp.terminate(nil)
                    return
                }
            }
            // Wait for the pipeline to settle, then quit.
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(500))
                if !container.pipeline.state.isBusy { break }
            }
            try? await Task.sleep(for: .seconds(1))
            log.notice("self-test: done state=\(String(describing: container.pipeline.state), privacy: .public)")
            container.settings.asr = originalASR
            NSApp.terminate(nil)
        }
    }
}
