#if DEBUG
import Foundation
import AirdraftCore

@MainActor
enum DataCleanupVerification {
    /// Exercises app coordination with disposable roots and nil credentials.
    /// No capture, playback, real preferences, Keychain or TCC operations.
    static func run() async -> Bool {
        guard LocalE2E.isActive else { return false }
        do {
            for scope in DataCleanupScope.allCases {
                let name = "airdraft.cleanup-verification.\(UUID())"
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                let defaults = UserDefaults(suiteName: name)!
                defer {
                    defaults.removePersistentDomain(forName: name)
                    try? FileManager.default.removeItem(at: directory)
                }
                let settings = AppSettings(defaults: defaults)
                settings.audioRetention = .forever
                let app = AppContainer(settings: settings, dataDirectory: directory)
                guard let history = app.history else { return false }
                _ = try history.save(DictationRecord(mode: "fixture", family: "document", rawTranscript: "Stored text",
                    refinedText: "Stored text", finalText: "Stored text", asrEngine: "fixture",
                    audioSeconds: 1, asrMs: 1, llmMs: 0, inserted: false), samples: [0.1, -0.1])
                _ = app.profiles.addNew()
                let preview = try await app.cleanupPreview()
                guard preview.historyCount == 1, preview.recordingCount == 1, preview.audioBytes > 0 else { return false }
                await app.performCleanup(scope)
                guard app.cleanup.finishedScope == scope, app.cleanup.error == nil else {
                    print("CLEANUP_FIXTURE_ERROR \(scope.rawValue): \(app.cleanup.error ?? "Incomplete")")
                    return false
                }
                if scope == .reset {
                    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                    guard files == [".airdraft-data.lock"], app.pipeline.isMaintainingData else { return false }
                } else {
                    guard try history.count() == (scope.removesHistory ? 0 : 1),
                          try history.recordings().entries.count == (scope.removesAudio ? 0 : 1),
                          FileManager.default.fileExists(atPath: directory.appendingPathComponent("profiles.json").path),
                          !app.pipeline.isMaintainingData else { return false }
                    try history.close()
                }
                print("CLEANUP_FIXTURE_PASS \(scope.rawValue)")
            }
            return true
        } catch { print("CLEANUP_FIXTURE_ERROR \(error.localizedDescription)"); return false }
    }
}
#endif
