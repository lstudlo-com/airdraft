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
            if CommandLine.arguments.contains("--e2e-meetings") {
                let app = AppContainer.shared
                if let history = app.history, (try? history.meetings().isEmpty) == true { try? MediaPreview.seedMeetings(history) }
                MeetingVerification.installSilentCapture(in: app)
                app.navigation.page = .meetings
            }
            return false
        }
        if action == "microphones" {
            MicrophoneSelfTest.run()
            return true
        }
        Task {
            let app = AppContainer.shared
            var actionPipeline: DictationPipeline?
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
                    app.settings.asr.language = locale
                }
                if let language = argument("--e2e-language") { app.settings.asr.language = language }
                if let bias = argument("--e2e-vocabulary-bias") {
                    guard ["on", "off"].contains(bias) else { throw E2EError.unknownAction }
                    app.settings.vocabularyBiasesOnDeviceSpeech = bias == "on"
                }
                switch action {
                case "architecture":
                    report["status"] = await ArchitectureVerification.run() ? "passed" : "failed"
                case "accessibility":
                    report = try InsertionE2E.probe()
                case "insert":
                    report = try await InsertionE2E.run(bundleID: argument("--e2e-target-bundle"),
                        token: argument("--e2e-insertion-token"), method: argument("--e2e-insertion-method"),
                        field: argument("--e2e-insertion-field"))
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
                        print("E2E download \(progress.detail) \(progress.currentFile)")
                    }
                    guard LocalModels.isInstalled(app.settings.asr) else { throw E2EError.missingModel }
                    report["status"] = "passed"
                case "transcribe":
                    guard let path = argument("--e2e-audio") else { throw E2EError.missingAudio }
                    let recordingMilliseconds: Int?
                    if let value = argument("--e2e-recording-ms") {
                        guard let milliseconds = Int(value), (0...120_000).contains(milliseconds) else {
                            throw E2EError.unknownAction
                        }
                        recordingMilliseconds = milliseconds
                    } else { recordingMilliseconds = nil }
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
                    var pipeline = app.pipeline
                    var replay: RefinementLatencyVerification.Session?
                    pipeline.insertionEnabled = false
                    pipeline.prepareRefinement = { [weak models = app.models] config in
                        guard let models else { throw CancellationError() }
                        return try await models.prepareLLMBackend(config: config)
                    }
                    pipeline.onLLMUsed = { [weak models = app.models] instance, config in
                        models?.noteLLMUsed(instance, config: config)
                    }
                    pipeline.onStateChange = { [weak pipeline, weak models = app.models] _ in
                        models?.setDictationBusy(pipeline?.isBusy == true)
                    }
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
                        // Mirror recording start: the prewarm builds the decoder the
                        // captured vocabulary choice needs (AD-081).
                        SherpaTranscriber.anticipate(TranscriptionHints(
                            language: try SpeechLanguagePolicy.resolve(app.settings.asr).language,
                            vocabulary: DictionaryPostProcessor.vocabulary(app.dictionary.entries),
                            biasOnDeviceSpeech: app.settings.vocabularyBiasesOnDeviceSpeech))
                        try await app.factory.prepare(app.settings.asr)
                        report["prepared"] = true
                    }
                    var processingStarted = ContinuousClock.now
                    let livePreview = CommandLine.arguments.contains("--e2e-live-preview")
                    if livePreview {
                        // AD-084: the selected model's live text through production recording.
                        guard recordingMilliseconds != nil else { throw E2EError.unknownAction }
                        app.settings.livePreviewEnabled = true
                        app.settings.livePreviewSource = .speechModel
                        if app.settings.hudStyle == .none { app.settings.hudStyle = .classic }
                    } else {
                        app.settings.livePreviewEnabled = false
                    }
                    if let milliseconds = recordingMilliseconds {
                        let session = try RefinementLatencyVerification.makeSession(app: app, samples: samples)
                        replay = session
                        pipeline = session.pipeline
                        actionPipeline = pipeline
                        let observer = livePreview ? PreviewObserver(pipeline: pipeline) : nil
                        try await session.startAndStop(recordingMilliseconds: milliseconds)
                        if let observer {
                            let observed = observer.finish()
                            report["livePreview"] = observed
                        }
                        processingStarted = .now
                    } else {
                        actionPipeline = pipeline
                        pipeline.processSamples(samples)
                    }
                    if let delay = argument("--e2e-cancel-ms").flatMap(Int.init) {
                        try await Task.sleep(for: .milliseconds(delay))
                        report["stateBeforeCancel"] = String(describing: pipeline.state)
                        report["busyBeforeCancel"] = pipeline.isBusy
                        report["outcomeBeforeCancel"] = pipeline.lastOutcome != nil
                        let processingDuration = processingStarted.duration(to: .now).components
                        report["processingMillisecondsBeforeCancel"] = Double(processingDuration.seconds) * 1_000 +
                            Double(processingDuration.attoseconds) / 1e15
                        pipeline.cancel()
                        let start = ContinuousClock.now
                        await app.factory.unloadAll()
                        report["cancelled"] = !pipeline.isBusy && pipeline.lastOutcome == nil
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
                    while pipeline.isBusy || pipeline.isFinishingDelivery, ContinuousClock.now < deadline {
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    if livePreview {
                        report["previewClearedAfterStop"] = pipeline.previewText.isEmpty && pipeline.previewIssue == nil &&
                            !pipeline.previewEnabledForRecording
                    }
                    if CommandLine.arguments.contains("--e2e-expect-silence") {
                        report["historyEmpty"] = try app.history?.recent(limit: 1).isEmpty == true
                        report["noOutcome"] = pipeline.lastOutcome == nil
                        report["status"] = pipeline.state == .idle && report["historyEmpty"] as? Bool == true &&
                            report["noOutcome"] as? Bool == true ? "passed" : "failed"
                        break
                    }
                    guard !pipeline.isBusy, let outcome = pipeline.lastOutcome,
                          !outcome.raw.isEmpty,
                          let record = try app.history?.recent(limit: 1).first,
                          record.finalText == outcome.final else { throw E2EError.pipeline(String(describing: pipeline.state)) }
                    report["raw"] = outcome.raw
                    report["final"] = outcome.final
                    report["profile"] = app.profiles.activeProfile.name
                    report["asrMs"] = outcome.asrMs
                    report["llmMs"] = outcome.llmMs
                    report["timings"] = RefinementLatencyVerification.timingReport(outcome.timings)
                    if let replay { report["recordingReplay"] = replay.report }
                    report["refinementSkipped"] = outcome.llmSkippedReason ?? ""
                    report["refinementStatus"] = app.settings.llm.kind == .none || !app.profiles.activeProfile.usesLLM ? "excluded" :
                        (outcome.llmSkippedReason == nil ? "passed" : "fallback")
                    report["audioSaved"] = record.audioFilename != nil
                    report["inserted"] = record.inserted
                    report["delivery"] = record.deliveryStatus.rawValue
                    report["pipelineStatus"] = "passed"
                    let refinementPassed = report["refinementStatus"] as? String != "fallback"
                    report["status"] = refinementPassed ? "passed" : "failed"
                    if !refinementPassed {
                        report["error"] = "Requested refinement did not complete. The pipeline preserved the original transcript."
                    }
                case "capture-latency":
                    // Real default input, only with existing microphone access; never requests it.
                    let trials = argument("--e2e-trials").flatMap(Int.init) ?? 5
                    let hold = argument("--e2e-recording-ms").flatMap(Int.init) ?? 600
                    guard (1...20).contains(trials), (300...5_000).contains(hold) else { throw E2EError.unknownAction }
                    report = try await CaptureLatencyVerification.run(app: app, trials: trials, holdMilliseconds: hold)
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
                case "model-preview":
                    report = try await modelPreview(app: app)
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
                    while app.pipeline.isBusy || app.pipeline.isFinishingDelivery, ContinuousClock.now < deadline {
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
            (actionPipeline ?? app.pipeline).cancel()
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

    /// Samples the pipeline's published preview every 50 ms while it records.
    @MainActor
    private final class PreviewObserver {
        private var texts: [String] = []
        private var issues: [String] = []
        private var firstTextMs: Int?
        private var task: Task<Void, Never>?
        init(pipeline: DictationPipeline) {
            let started = ProcessInfo.processInfo.systemUptime
            task = Task { @MainActor [weak self, weak pipeline] in
                while !Task.isCancelled, let pipeline {
                    if pipeline.isRecording, let self {
                        let text = pipeline.previewText
                        if !text.isEmpty, text != self.texts.last {
                            self.texts.append(text)
                            if self.firstTextMs == nil { self.firstTextMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000) }
                        }
                        if let issue = pipeline.previewIssue, issue != self.issues.last { self.issues.append(issue) }
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        func finish() -> [String: Any] {
            task?.cancel()
            return ["updates": texts.count, "lastText": texts.last ?? "", "texts": Array(texts.suffix(8)),
                    "issues": issues, "firstTextMs": firstTextMs.map { $0 as Any } ?? NSNull()]
        }
    }

    /// AD-084: the selected local model's live text on a file input, its cadence,
    /// and the final transcript with and without preview contention.
    private static func modelPreview(app: AppContainer) async throws -> [String: Any] {
        guard let path = argument("--e2e-audio") else { throw E2EError.missingAudio }
        let asr = app.settings.asr
        if let reason = ModelSpeechPreview.unavailableReason(for: asr) { throw E2EError.pipeline(reason) }
        let samples = try AudioFile.load(path: path)
        let hints = TranscriptionHints(language: try SpeechLanguagePolicy.resolve(asr).language,
                                       vocabulary: DictionaryPostProcessor.vocabulary(app.dictionary.entries),
                                       chineseScript: asr.chineseScript,
                                       biasOnDeviceSpeech: app.settings.vocabularyBiasesOnDeviceSpeech)
        func ms(_ start: ContinuousClock.Instant) -> Double {
            let duration = start.duration(to: .now).components
            return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        }
        var report: [String: Any] = ["engine": asr.engineID, "audioSeconds": Double(samples.count) / 16_000]
        SherpaTranscriber.anticipate(hints)
        let loadStart = ContinuousClock.now
        try await app.factory.prepare(asr)
        report["loadMs"] = ms(loadStart)
        // 1. Final transcript without any preview.
        let baselineStart = ContinuousClock.now
        let baseline = try await app.factory.transcribe(samples, hints: hints, config: asr)
        var baselineMs = [ms(baselineStart)]
        for _ in 0..<2 {
            let repeatStart = ContinuousClock.now
            _ = try await app.factory.transcribe(samples, hints: hints, config: asr)
            baselineMs.append(ms(repeatStart))
        }
        report["baselineFinalMs"] = baselineMs.sorted()[1]
        report["baselineFinalRunsMs"] = baselineMs
        report["baselineFinal"] = baseline.text

        // 2. Real-time preview of the file (100 ms chunks), then final ASR at once.
        let events = TimedEvents()
        let request = ModelPreviewRequest(asr: asr, hints: hints)
        let session = ModelSpeechPreview.start(decode: ModelSpeechPreview.decoder(factory: app.factory, request: request),
                                               onText: { events.text($0) }, onIssue: { events.issue($0) })
        for offset in stride(from: 0, to: samples.count, by: 1600) {
            session.append(Array(samples[offset..<min(offset + 1600, samples.count)]))
            try await Task.sleep(for: .milliseconds(100))
        }
        session.cancel()
        let finalStart = ContinuousClock.now
        let final = try await app.factory.transcribe(samples, hints: hints, config: asr)
        report["finalAfterPreviewMs"] = ms(finalStart)
        let metrics = session.metrics
        let decodeMs = metrics.decodeSeconds.map { $0 * 1_000 }.sorted()
        report["decodes"] = metrics.decodes
        report["commits"] = metrics.commits
        report["skippedBusy"] = metrics.skippedBusy
        report["preempted"] = metrics.preempted
        report["droppedSamples"] = metrics.droppedSamples
        report["longestWindowSeconds"] = Double(metrics.longestWindowSamples) / 16_000
        report["decodeMsMean"] = decodeMs.isEmpty ? 0 : decodeMs.reduce(0, +) / Double(decodeMs.count)
        report["decodeMsP50"] = decodeMs.isEmpty ? 0 : decodeMs[decodeMs.count / 2]
        report["decodeMsMax"] = decodeMs.last ?? 0
        report["intervalMsMin"] = (metrics.intervals.min() ?? 0) * 1_000
        report["intervalMsMean"] = metrics.intervals.isEmpty ? 0 : metrics.intervals.reduce(0, +) / Double(metrics.intervals.count) * 1_000
        let snapshot = events.snapshot
        report["previewUpdates"] = snapshot.texts.count
        report["firstTextMs"] = snapshot.firstTextMs.map { $0 as Any } ?? NSNull()
        report["previewTexts"] = Array(snapshot.texts.map(\.text).suffix(6))
        report["previewIssues"] = snapshot.issues
        report["finalAfterPreview"] = final.text
        report["finalIdentical"] = final.text == baseline.text

        // 3. Callbacks stop with the session.
        session.append(samples)
        try await Task.sleep(for: .milliseconds(300))
        report["stoppedCallbacks"] = events.snapshot.texts.count == snapshot.texts.count

        // 4. Final inference requested while a preview decode of a 9.5 s window may
        // hold the lease. Each trial starts the final request at a different point.
        var contendedMs: [Double] = []
        var contendedIdentical = true
        var contendedPreempted = 0
        var contendedDecodes = 0
        for delay in [20, 60, 100, 140, 180] {
            let contended = ModelSpeechPreview.start(policy: ModelPreviewPolicy(minimumInterval: 0, minimumNewAudioSeconds: 0, pollSeconds: 0.005),
                decode: ModelSpeechPreview.decoder(factory: app.factory, request: request),
                onText: { _ in }, onIssue: { _ in })
            contended.append(Array(samples.prefix(Int(9.5 * 16_000))))
            try await Task.sleep(for: .milliseconds(delay))
            let contendedStart = ContinuousClock.now
            let contendedFinal = try await app.factory.transcribe(samples, hints: hints, config: asr)
            contendedMs.append(ms(contendedStart))
            contended.cancel()
            contendedIdentical = contendedIdentical && contendedFinal.text == baseline.text
            contendedPreempted += contended.metrics.preempted
            contendedDecodes += contended.metrics.decodes
        }
        report["contendedFinalMs"] = contendedMs
        report["contendedFinalExtraMsMax"] = (contendedMs.max() ?? 0) - (report["baselineFinalMs"] as? Double ?? 0)
        report["contendedPreviewPreempted"] = contendedPreempted
        report["contendedPreviewDecodes"] = contendedDecodes
        report["contendedIdentical"] = contendedIdentical
        report["status"] = snapshot.texts.count > 0 && snapshot.issues.isEmpty &&
            report["finalIdentical"] as? Bool == true && report["contendedIdentical"] as? Bool == true &&
            report["stoppedCallbacks"] as? Bool == true ? "passed" : "failed"
        return report
    }

    private final class TimedEvents: @unchecked Sendable {
        private let lock = NSLock()
        private let started = ProcessInfo.processInfo.systemUptime
        private var texts: [(ms: Int, text: String)] = []
        private var issues: [String] = []
        func text(_ value: String) {
            let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            lock.withLock { texts.append((ms, value)) }
        }
        func issue(_ value: String) { lock.withLock { issues.append(value) } }
        var snapshot: (texts: [(ms: Int, text: String)], issues: [String], firstTextMs: Int?) {
            lock.withLock { (texts: texts, issues: issues, firstTextMs: texts.first?.ms) }
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
