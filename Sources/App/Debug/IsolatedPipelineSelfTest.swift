#if DEBUG
// Offscreen renders and self-tests use the app's permissions, so they never ship in Release.
import AppKit
import AirdraftCore
import os

/// A real file-to-history run with temporary settings/data and no cloud requests.
@MainActor
enum IsolatedPipelineSelfTest {
    static func run(path: String) {
        Task {
            let log = Logger(subsystem: AppIdentity.logSubsystem, category: "selftest")
            let suite = "airdraft.pipeline-selftest.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: directory)
            }
            do {
                let settings = AppSettings(defaults: defaults)
                settings.asr = ASRConfig(kind: .apple, appleLocale: "en-US")
                settings.llm.select(.groq)
                settings.useAppContext = false
                let history = try HistoryStore(directory: directory)
                let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
                    throw Keychain.AccessError.authorizationRequired
                })
                let pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory),
                    profiles: ProfileStore(directory: directory), history: history, factory: factory)
                pipeline.insertionEnabled = false
                pipeline.processSamples(try AudioFile.load(path: path))
                for _ in 0..<120 {
                    try await Task.sleep(for: .milliseconds(500))
                    if !pipeline.isBusy { break }
                }
                guard let outcome = pipeline.lastOutcome, !outcome.raw.isEmpty,
                      outcome.llmSkippedReason == "LLM failed, inserted raw transcript",
                      try history.recent(limit: 1).first?.finalText == outcome.final else {
                    log.error("isolated-pipeline: FAIL \(String(describing: pipeline.state), privacy: .public)")
                    pipeline.cancel()
                    await factory.unloadAll()
                    NSApp.terminate(nil)
                    return
                }
                log.notice("isolated-pipeline: PASS local speech, denied-key raw-transcript fallback, dictionary, history; raw=\(outcome.raw, privacy: .public)")
                await factory.unloadAll()
            } catch {
                log.error("isolated-pipeline: FAIL \(error.localizedDescription, privacy: .public)")
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
