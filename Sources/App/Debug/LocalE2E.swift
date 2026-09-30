#if DEBUG
import AppKit
import AirdraftCore
import Foundation
import CryptoKit

/// Explicit, local-only automation. All durable app data belongs to the supplied
/// test directory. This entry point and its argument handling never ship.
@MainActor
enum LocalE2E {
    nonisolated static func argument(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    nonisolated static var isActive: Bool { argument("--e2e-local") != nil }
    static var directory: URL { URL(fileURLWithPath: argument("--e2e-local")!, isDirectory: true) }

    static func makeContainer() -> AppContainer {
        if ProcessInfo.processInfo.environment["AIRDRAFT_E2E_MODEL_ROOT"]?.hasPrefix("/") != true {
            let modelRoot = directory.appendingPathComponent("Models", isDirectory: true)
            setenv("AIRDRAFT_E2E_MODEL_ROOT", modelRoot.path, 1)
        }
        let digest = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let suite = "airdraft.local-e2e." + digest
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        if defaults.data(forKey: "settings.asr") == nil {
            settings.asr = ASRConfig(kind: .apple, appleLocale: "en-US", language: "en")
            settings.llm.select(.none)
            settings.useAppContext = false
            settings.audioRetention = .forever
        }
        // A reused test directory must not restore a cloud selection.
        if !settings.asr.kind.isLocal { settings.asr = ASRConfig(kind: .apple, appleLocale: "en-US") }
        if !allowsRefinement(settings.llm) { settings.llm.select(.none) }
        return AppContainer(settings: settings, dataDirectory: directory)
    }

    private static func allowsRefinement(_ config: LLMConfig) -> Bool {
        switch config.kind {
        case .none, .appleIntelligence, .claudeCode, .codex: return true
        case .openAICompatible:
            guard let endpoint = config.endpoint,
                  ["http", "https"].contains(endpoint.scheme?.lowercased() ?? "") else { return false }
            return ["localhost", "127.0.0.1", "::1"].contains(endpoint.host?.lowercased() ?? "")
        default: return false
        }
    }

    static func checkRecording(asr: ASRConfig, llm: LLMConfig, refinementEnabled: Bool,
                               microphone: MicrophonePreference, insertionEnabled: Bool) throws {
        guard asr.kind.isLocal else {
            throw RecordingPrerequisiteError("Local E2E verification requires on-device speech recognition.")
        }
        guard !refinementEnabled || allowsRefinement(llm) else {
            throw RecordingPrerequisiteError("Local E2E verification allows only on-device, subscription CLI or loopback refinement.")
        }
        var environment = RecordingPrerequisites.Environment.live
        environment.readCredential = { _ in nil }
        try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: refinementEnabled,
                                         microphone: microphone, insertionEnabled: insertionEnabled,
                                         environment: environment)
    }

    /// Returns false for the interactive window and offscreen renders.
    static func runAction() -> Bool {
        guard let action = argument("--e2e-action") else {
            if CommandLine.arguments.contains("--e2e-seed") { seed() }
            return false
        }
        if action == "microphones" {
            MicrophoneSelfTest.run()
            return true
        }
        Task {
            let app = AppContainer.shared
            var report: [String: Any] = ["action": action, "status": "failed"]
            do {
                if let id = argument("--e2e-model") {
                    guard let entry = ModelCatalogue.entries.first(where: { $0.id == id }) else {
                        throw E2EError.invalidModel
                    }
                    app.settings.asr = entry.config(from: app.settings.asr)
                }
                if let locale = argument("--e2e-locale") {
                    app.settings.asr.appleLocale = locale
                    app.settings.asr.language = String(locale.prefix(2))
                }
                switch action {
                case "insert":
                    report = try await InsertionE2E.run(bundleID: argument("--e2e-target-bundle"),
                        token: argument("--e2e-insertion-token"), method: argument("--e2e-insertion-method"))
                case "inventory":
                    report["models"] = ModelCatalogue.entries.map { entry in
                        let config = entry.config(from: app.settings.asr)
                        return ["id": entry.id, "installed": LocalModels.isInstalled(config),
                                "path": LocalModels.folder(for: config)?.path ?? "system"] as [String: Any]
                    }
                    report["appleIntelligenceUnavailable"] = AppleIntelligenceRefiner.unavailableReason ?? ""
                    report["status"] = "passed"
                case "download":
                    try await ModelDownloader.shared.download(app.settings.asr) { progress in
                        print("E2E download \(Int(progress.fraction * 100))% \(progress.currentFile)")
                    }
                    guard LocalModels.isInstalled(app.settings.asr) else { throw E2EError.missingModel }
                    report["status"] = "passed"
                case "transcribe":
                    guard let path = argument("--e2e-audio") else { throw E2EError.missingAudio }
                    if let name = argument("--e2e-profile") {
                        guard let profile = app.profiles.profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                            throw E2EError.unknownAction
                        }
                        app.profiles.setActive(profile.id)
                    }
                    app.settings.llm.select(.none)
                    if let value = argument("--e2e-refiner") {
                        guard let kind = LLMProviderKind(rawValue: value),
                              [.appleIntelligence, .claudeCode, .codex, .openAICompatible].contains(kind) else {
                            throw E2EError.unknownAction
                        }
                        app.settings.llm.select(kind)
                        app.settings.llm.minWordsForLLM = 0
                        if kind == .openAICompatible {
                            guard let endpoint = argument("--e2e-endpoint"), let url = URL(string: endpoint),
                                  ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "") else {
                                throw E2EError.unknownAction
                            }
                            app.settings.llm.baseURL = endpoint
                            app.settings.llm.model = argument("--e2e-llm-model") ?? ""
                        }
                    }
                    app.pipeline.insertionEnabled = false
                    let samples = try AudioFile.load(path: path)
                    if CommandLine.arguments.contains("--e2e-prepare") {
                        guard app.settings.asr.kind.isLocal, LocalModels.isInstalled(app.settings.asr) else {
                            throw E2EError.missingModel
                        }
                        // Warming this fixture must not install language assets.
                        if app.settings.asr.kind == .apple {
                            let engine = await app.factory.transcriber(for: app.settings.asr)
                            guard await engine.isReady() else { throw E2EError.missingModel }
                        }
                        try await app.factory.prepare(app.settings.asr)
                        report["prepared"] = true
                    }
                    let processingStarted = ContinuousClock.now
                    app.pipeline.processSamples(samples)
                    if let delay = argument("--e2e-cancel-ms").flatMap(Int.init) {
                        try await Task.sleep(for: .milliseconds(delay))
                        report["stateBeforeCancel"] = String(describing: app.pipeline.state)
                        report["busyBeforeCancel"] = app.pipeline.isBusy
                        report["outcomeBeforeCancel"] = app.pipeline.lastOutcome != nil
                        let processingDuration = processingStarted.duration(to: .now).components
                        report["processingMillisecondsBeforeCancel"] = Double(processingDuration.seconds) * 1_000 +
                            Double(processingDuration.attoseconds) / 1e15
                        app.pipeline.cancel()
                        let start = ContinuousClock.now
                        await app.factory.unloadAll()
                        report["cancelled"] = !app.pipeline.isBusy && app.pipeline.lastOutcome == nil
                        report["historyEmpty"] = try app.history?.recent(limit: 1).isEmpty == true
                        report["cleanupSeconds"] = Double(start.duration(to: .now).components.seconds)
                        let cleanupDuration = start.duration(to: .now).components
                        report["cleanupMilliseconds"] = Double(cleanupDuration.seconds) * 1_000 +
                            Double(cleanupDuration.attoseconds) / 1e15
                        let cancellationStartedDuringWork = report["busyBeforeCancel"] as? Bool == true &&
                            report["outcomeBeforeCancel"] as? Bool == false
                        let preparedInferenceStarted = report["prepared"] as? Bool != true ||
                            report["stateBeforeCancel"] as? String == "transcribing"
                        report["status"] = cancellationStartedDuringWork && preparedInferenceStarted &&
                            report["cancelled"] as? Bool == true && report["historyEmpty"] as? Bool == true ? "passed" : "failed"
                        break
                    }
                    let deadline = ContinuousClock.now.advanced(by: .seconds(240))
                    while app.pipeline.isBusy, ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    if CommandLine.arguments.contains("--e2e-expect-silence") {
                        report["historyEmpty"] = try app.history?.recent(limit: 1).isEmpty == true
                        report["noOutcome"] = app.pipeline.lastOutcome == nil
                        report["status"] = app.pipeline.state == .idle && report["historyEmpty"] as? Bool == true &&
                            report["noOutcome"] as? Bool == true ? "passed" : "failed"
                        break
                    }
                    guard !app.pipeline.isBusy, let outcome = app.pipeline.lastOutcome,
                          !outcome.raw.isEmpty,
                          let record = try app.history?.recent(limit: 1).first,
                          record.finalText == outcome.final else { throw E2EError.pipeline(String(describing: app.pipeline.state)) }
                    report["raw"] = outcome.raw
                    report["final"] = outcome.final
                    report["profile"] = app.profiles.activeProfile.name
                    report["asrMs"] = outcome.asrMs
                    report["llmMs"] = outcome.llmMs
                    report["refinementSkipped"] = outcome.llmSkippedReason ?? ""
                    report["refinementStatus"] = app.settings.llm.kind == .none || !app.profiles.activeProfile.usesLLM ? "excluded" :
                        (outcome.llmSkippedReason == nil ? "passed" : "fallback")
                    report["audioSaved"] = record.audioFilename != nil
                    report["inserted"] = record.inserted
                    report["pipelineStatus"] = "passed"
                    let refinementPassed = report["refinementStatus"] as? String != "fallback"
                    report["status"] = refinementPassed ? "passed" : "failed"
                    if !refinementPassed {
                        report["error"] = "Requested refinement did not complete. The pipeline preserved the original transcript."
                    }
                case "preview":
                    guard let path = argument("--e2e-audio") else { throw E2EError.missingAudio }
                    let locale = argument("--e2e-locale") ?? "en-US"
                    if let reason = await SpeechPreview.unavailableReason(locale: locale) {
                        throw E2EError.pipeline(reason)
                    }
                    let events = PreviewEvents()
                    let preview = SpeechPreview.start(locale: locale, onText: { events.text($0) }, onIssue: { events.issue($0) })
                    let samples = try AudioFile.load(path: path)
                    for offset in stride(from: 0, to: samples.count, by: 1600) {
                        preview.append(Array(samples[offset..<min(offset + 1600, samples.count)]))
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    try await Task.sleep(for: .seconds(2))
                    preview.cancel()
                    let before = events.snapshot
                    preview.append(samples)
                    try await Task.sleep(for: .milliseconds(200))
                    let after = events.snapshot
                    report["previewTexts"] = after.texts
                    report["previewIssues"] = after.issues
                    report["stoppedCallbacks"] = before.texts == after.texts && before.issues == after.issues
                    report["status"] = !after.texts.isEmpty && after.issues.isEmpty &&
                        report["stoppedCallbacks"] as? Bool == true ? "passed" : "failed"
                case "automation":
                    guard let path = argument("--e2e-audio") else { throw E2EError.missingAudio }
                    let script = directory.appendingPathComponent("receive.sh")
                    try Data("#!/bin/sh\n/bin/cat > \"$(dirname \"$0\")/delivery.txt\"\n".utf8).write(to: script)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
                    app.settings.outputDestination = .script
                    app.settings.outputScriptPath = script.path
                    app.settings.hudStyle = .none
                    app.settings.llm.select(.none)
                    app.settings.livePreviewEnabled = true
                    app.settings.livePreviewLocale = "en-US"
                    app.start()
                    let wasActive = NSApp.isActive
                    _ = try await StartDictationIntent().perform()
                    report["startAwaitedCapture"] = app.pipeline.state == .recording
                    _ = try await CancelDictationIntent().perform()
                    report["cancelled"] = !app.pipeline.isBusy
                    _ = try await StartDictationIntent().perform()
                    let duration = Double(try AudioFile.load(path: path).count) / AudioRecorder.sampleRate
                    try Data().write(to: directory.appendingPathComponent("ready-for-playback"))
                    let captureDeadline = ContinuousClock.now.advanced(by: .seconds(min(45, duration + 3)))
                    var peak: Float = 0
                    while ContinuousClock.now < captureDeadline {
                        peak = max(peak, app.pipeline.levelHistory.max() ?? 0)
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    report["meterPeak"] = peak
                    _ = try await StopDictationIntent().perform()
                    let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                    while app.pipeline.isBusy, ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    guard let outcome = app.pipeline.lastOutcome, !outcome.raw.isEmpty,
                          let record = try app.history?.recent(limit: 1).first,
                          record.outputSucceeded == true,
                          try String(contentsOf: directory.appendingPathComponent("delivery.txt"), encoding: .utf8) == outcome.final
                    else { throw E2EError.pipeline(String(describing: app.pipeline.state)) }
                    report["raw"] = outcome.raw
                    report["final"] = outcome.final
                    report["audioSaved"] = record.audioFilename != nil
                    report["didNotActivate"] = NSApp.isActive == wasActive
                    report["scriptDelivered"] = true
                    report["status"] = report["startAwaitedCapture"] as? Bool == true &&
                        report["cancelled"] as? Bool == true &&
                        report["didNotActivate"] as? Bool == true ? "passed" : "failed"
                default: throw E2EError.unknownAction
                }
            } catch {
                report["error"] = error.localizedDescription
            }
            report["engine"] = app.settings.asr.engineID
            app.pipeline.cancel()
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("result.json"), options: .atomic)
                print(String(decoding: data, as: UTF8.self))
            } catch {
                print("E2E result write failed: \(error)")
                report["status"] = "failed"
            }
            app.beginShutdown()
            await app.models.shutdown()
            exit(report["status"] as? String == "passed" ? 0 : 1)
        }
        return true
    }

    private static func seed() {
        let app = AppContainer.shared
        guard (try? app.history?.recent(limit: 1).isEmpty) == true else { return }
        let phrases = ["Please send the report tomorrow.", "這是一段中文與 English 混合的測試。", "Keep the original punctuation, names, and numbers: 42."]
        let samples = argument("--e2e-audio").flatMap { try? AudioFile.load(path: $0) }
        for index in 0..<160 {
            let text = String(repeating: phrases[index % phrases.count] + " ", count: index % 9 == 0 ? 30 : 1)
            _ = try? app.history?.save(DictationRecord(createdAt: Date().addingTimeInterval(-Double(index) * 3600),
                appName: "E2E Fixture", mode: "Clean", family: "general", rawTranscript: "um " + text,
                refinedText: text, finalText: text, asrEngine: "fixture", audioSeconds: 5,
                asrMs: 100, llmMs: 0, inserted: false), samples: index < 3 ? samples : nil)
        }
        if app.dictionary.entries.isEmpty {
            app.dictionary.add(DictionaryEntry(term: "Airdraft", aliases: ["air draft", "air draught"]))
        }
    }

    private enum E2EError: LocalizedError {
        case invalidModel, missingModel, missingAudio, unknownAction, pipeline(String)
        var errorDescription: String? {
            switch self {
            case .invalidModel: return "Unknown local model."
            case .missingModel: return "Model files are incomplete."
            case .missingAudio: return "Provide --e2e-audio."
            case .unknownAction: return "Unknown E2E action."
            case .pipeline(let state): return "Pipeline failed or timed out: \(state)"
            }
        }
    }

    private final class PreviewEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var texts: [String] = []
        private var issues: [String] = []
        func text(_ value: String) { lock.withLock { texts.append(value) } }
        func issue(_ value: String) { lock.withLock { issues.append(value) } }
        var snapshot: (texts: [String], issues: [String]) { lock.withLock { (texts, issues) } }
    }
}
#endif
