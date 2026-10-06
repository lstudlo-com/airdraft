#if DEBUG
import Foundation
import AirdraftCore

/// Actual AppContainer wiring with disposable stores and injected resource cleanup.
/// No app startup, capture, playback, model inference or credential operations.
@MainActor
enum ArchitectureVerification {
    private enum Failure: LocalizedError {
        case assertion(String), injected
        var errorDescription: String? {
            switch self {
            case .assertion(let message): message
            case .injected: "Injected resource-cleanup refusal"
            }
        }
    }

    static func run() async -> Bool {
        guard LocalE2E.isActive else { return false }
        do {
            for scope in DataCleanupScope.allCases { try await verifyCleanup(scope) }
            try await verifyPreparationFailure()
            for scope in DataCleanupScope.allCases { try await verifyLegacyJournal(scope) }
            try await verifyLegacyJournalPreparationFailure()
            try await verifyLegacyAudioAfterHistory()
            try await verifyJournalRetry()
            try await verifyMaintenanceStateCallbacks()
            try await verifyBlockedCopy()
            try verifyPracticeWiring()
            print("ARCHITECTURE_FIXTURE_PASS all")
            return true
        } catch {
            print("ARCHITECTURE_FIXTURE_ERROR \(error.localizedDescription)")
            return false
        }
    }

    /// Lets the native UI fixture inspect the real fenced recovery route. Its
    /// provider refusal is injected before any credential or network operation.
    static func withFailedLegacyCleanup(_ verify: @MainActor (AppContainer) async throws -> Void) async throws {
        guard LocalE2E.isActive && RenderMode.excludesCredentials else { throw Failure.assertion("Recovery fixture requires credential isolation") }
        let fixture = try Fixture(legacyScope: .historyAndAudio)
        defer { fixture.close() }
        fixture.probe.refuse = true
        await fixture.app.performCleanup(.historyAndAudio)
        try require(!fixture.app.cleanupRecoveryKeyReferences.isEmpty, "Missing explicit provider-access recovery route")
        try await verify(fixture.app)
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure.assertion(message) }
    }

    @MainActor private final class Fixture {
        let name = "airdraft.architecture.\(UUID())"
        let directory: URL
        let defaults: UserDefaults
        let settings: AppSettings
        let app: AppContainer
        let probe: CleanupProbe
        let seededDocument: TranscriptDocument?
        init(legacyScope: DataCleanupScope? = nil, legacyHistoryCompleted: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: name)!
            settings = AppSettings(defaults: defaults)
            // A cleanup completion starts ModelLifecycle. These choices make its
            // startup a no-op without any local model or server discovery.
            settings.asr = ASRConfig(kind: .openAI, language: "en")
            settings.llm = LLMConfig(kind: .none)
            settings.audioRetention = .forever
            probe = CleanupProbe()
            if let legacyScope {
                let history = try HistoryStore(directory: directory)
                let document = try Self.createMedia(history: history, directory: directory)
                if legacyHistoryCompleted {
                    guard legacyScope == .audio else { throw Failure.assertion("Only audio cleanup retains old remote documents") }
                    try history.deleteAllAudio()
                    seededDocument = try history.document(id: document.id)
                    // A fixture-only sentinel proves that the completed audio
                    // deletion phase is not repeated during journal recovery.
                    _ = try history.saveRecording(samples: [0.1], source: .imported)
                    probe.expectedCompletedSteps = ["pending", "history"]
                    probe.expectsSourceAudio = false
                } else { seededDocument = document }
                try history.close()
                // This is the pre-fix version-1 journal format, paused after
                // recovery preparation but before its destructive history step.
                let journal = try JSONSerialization.data(withJSONObject: ["version": 1,
                    "scope": legacyScope.rawValue, "completed": probe.expectedCompletedSteps], options: [.sortedKeys])
                try journal.write(to: directory.appendingPathComponent("cleanup.json"))
                probe.existingJournal = journal
            } else { seededDocument = nil }
            let probe = probe
            app = AppContainer(settings: settings, dataDirectory: directory,
                mediaRemoteCleanup: { saved in try await probe.clean(saved) })
            probe.app = app
        }
        func close() {
            try? app.history?.close()
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        func createMedia() throws -> TranscriptDocument {
            guard let history = app.history else { throw Failure.assertion("Fixture History is unavailable") }
            return try Self.createMedia(history: history, directory: directory)
        }
        private static func createMedia(history: HistoryStore, directory: URL) throws -> TranscriptDocument {
            let asset = try history.saveRecording(samples: [0.1, -0.1], source: .imported)
            var document = try history.createDocument(asset: asset, title: "Cleanup fixture", configuration: .init(engine: .soniox))
            document.remoteFileID = "fixture-resource"
            document.remoteJobID = "fixture-job"
            document = try history.updateDocument(document)
            let staging = directory.appendingPathComponent("MediaStaging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: staging.appendingPathComponent("pending.wav"))
            return document
        }
    }

    @MainActor private final class CleanupProbe {
        weak var app: AppContainer?
        var calls = 0
        var refuse = false
        var existingJournal: Data?
        var expectedCompletedSteps = ["pending"]
        var expectsSourceAudio = true
        func clean(_ saved: TranscriptDocument) throws {
            guard let app, let history = app.history else { throw Failure.assertion("Missing cleanup owner") }
            calls += 1
            try require(app.cleanup.isRunning, "Provider preparation must belong to the cleanup operation")
            if let existingJournal {
                try require(app.cleanup.pendingScope != nil && app.pipeline.isMaintainingData,
                            "Legacy preparation dropped the existing cleanup fence")
                try require(app.cleanup.completedSteps == expectedCompletedSteps, "Legacy preparation changed completed phases")
                try require(try Data(contentsOf: app.dataDirectory.appendingPathComponent("cleanup.json")) == existingJournal,
                            "Legacy preparation rewrote the journal before provider cleanup")
            } else {
                try require(app.cleanup.pendingScope == nil && !app.pipeline.isMaintainingData,
                            "Fresh provider preparation must precede the journal and maintenance fence")
                try require(!FileManager.default.fileExists(atPath: app.dataDirectory.appendingPathComponent("cleanup.json").path),
                            "Cleanup journal was written before provider preparation")
            }
            try require(app.cleanupRecoveryKeyReferences.isEmpty, "Running cleanup exposed access-repair controls")
            let stored = try history.document(id: saved.id)
            try require(stored?.remoteFileID == saved.remoteFileID && stored?.remoteJobID == saved.remoteJobID,
                        "Provider cleanup lost its durable resource IDs")
            if expectsSourceAudio {
                guard let id = saved.recordingID, let asset = try history.recording(id: id) else {
                    throw Failure.assertion("Provider cleanup lost its recording")
                }
                try require(history.audioURL(for: asset) != nil, "Provider cleanup ran after local audio deletion")
            } else {
                try require(saved.recordingID == nil, "Legacy audio fixture did not represent completed local audio deletion")
            }
            if refuse { throw Failure.injected }
        }
    }

    private static func assertStillOwned(_ fixture: Fixture) throws {
        do {
            _ = try DataDirectoryLease(directory: fixture.directory)
            throw Failure.assertion("Cleanup released the lifetime data lease")
        } catch CleanupError.otherInstance {}
    }

    private static func verifyCleanup(_ scope: DataCleanupScope) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = try fixture.createMedia()
        await fixture.app.performCleanup(scope)
        try require(fixture.probe.calls == 1, "Fresh \(scope) cleanup skipped or repeated provider preparation")
        try assertCleanupFinished(fixture, original: original, scope: scope)
        print("ARCHITECTURE_FIXTURE_PASS cleanup-\(scope.rawValue)")
    }

    private static func assertCleanupFinished(_ fixture: Fixture, original: TranscriptDocument, scope: DataCleanupScope) throws {
        try require(fixture.app.cleanup.finishedScope == scope && fixture.app.cleanup.error == nil, "Cleanup did not finish")
        try require(fixture.app.cleanupRecoveryKeyReferences.isEmpty, "Completed cleanup retained access-repair controls")
        try require(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("MediaStaging").path),
                    "Cleanup left media staging files")
        try assertStillOwned(fixture)
        if scope == .reset {
            try require(fixture.app.history == nil && fixture.app.pipeline.isMaintainingData, "Reset reopened local work")
        } else {
            guard let history = fixture.app.history else { throw Failure.assertion("History unexpectedly closed") }
            if scope.removesHistory {
                try require(try history.document(id: original.id) == nil, "History cleanup retained the document")
            } else {
                let saved = try history.document(id: original.id)
                try require(saved != nil && saved?.remoteFileID == nil && saved?.remoteJobID == nil && saved?.recordingID == nil,
                            "Audio cleanup did not retain text while removing resource references")
            }
            try require(try history.recordings().entries.count == (scope.removesAudio ? 0 : 1), "Cleanup removed the wrong audio scope")
            try require(!fixture.app.pipeline.isMaintainingData, "Successful cleanup left Configuration fenced")
        }
    }

    private static func verifyPreparationFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = try fixture.createMedia()
        fixture.probe.refuse = true
        await fixture.app.performCleanup(.historyAndAudio)
        try require(fixture.app.cleanup.error != nil && !fixture.app.cleanup.blocksWork,
                    "Pre-journal refusal must leave Configuration available")
        try require(!fixture.app.pipeline.isBusy && !fixture.app.pipeline.isMaintainingData, "Refused preparation left work fenced")
        try require(fixture.app.cleanupRecoveryKeyReferences.isEmpty, "Fresh refusal must use ordinary Configuration recovery")
        try require(try fixture.app.history?.document(id: original.id) == original, "Refused cleanup changed the document or resource IDs")
        try require(try fixture.app.history?.recordings().entries.count == 1, "Refused cleanup removed source audio")
        try assertStillOwned(fixture)
        fixture.probe.refuse = false
        await fixture.app.performCleanup(.historyAndAudio)
        try require(fixture.probe.calls == 2 && fixture.app.cleanup.finishedScope == .historyAndAudio, "Preparation refusal could not be retried")
        try assertStillOwned(fixture)
        print("ARCHITECTURE_FIXTURE_PASS cleanup-refusal-retry")
    }

    private static func verifyLegacyJournal(_ scope: DataCleanupScope) async throws {
        let fixture = try Fixture(legacyScope: scope)
        defer { fixture.close() }
        guard let original = fixture.seededDocument else { throw Failure.assertion("Missing legacy document") }
        try require(fixture.app.cleanup.pendingScope == scope && fixture.app.cleanup.completedSteps == ["pending"],
                    "AppContainer did not load the baseline-compatible journal")
        try require(fixture.app.pipeline.isMaintainingData, "Legacy journal did not fence startup")
        await fixture.app.performCleanup(scope)
        try require(fixture.probe.calls == 1, "Legacy \(scope) journal skipped retained remote resources")
        try assertCleanupFinished(fixture, original: original, scope: scope)
        print("ARCHITECTURE_FIXTURE_PASS cleanup-legacy-\(scope.rawValue)")
    }

    private static func verifyLegacyJournalPreparationFailure() async throws {
        let fixture = try Fixture(legacyScope: .historyAndAudio)
        defer { fixture.close() }
        guard let original = fixture.seededDocument else { throw Failure.assertion("Missing legacy document") }
        fixture.probe.refuse = true
        await fixture.app.performCleanup(.historyAndAudio)
        try require(fixture.app.cleanup.error != nil && fixture.app.cleanup.blocksWork && fixture.app.pipeline.isMaintainingData,
                    "Legacy preparation refusal dropped its durable fence")
        try require(fixture.app.cleanup.completedSteps == ["pending"], "Refused legacy preparation changed completed phases")
        try require(try fixture.app.history?.document(id: original.id) == original, "Refused legacy cleanup lost resource IDs")
        try require(try fixture.app.history?.recordings().entries.count == 1, "Refused legacy cleanup lost audio")
        try require(fixture.app.cleanupRecoveryKeyReferences == [original.configuration.asr.keyRef],
                    "Fenced cleanup did not expose the retained resource's access-repair reference")
        try require(try Data(contentsOf: fixture.directory.appendingPathComponent("cleanup.json")) == fixture.probe.existingJournal,
                    "Refused legacy preparation rewrote its existing journal")
        try assertStillOwned(fixture)
        fixture.probe.refuse = false
        await fixture.app.performCleanup(.historyAndAudio)
        try require(fixture.probe.calls == 2, "Legacy preparation refusal could not retry")
        try assertCleanupFinished(fixture, original: original, scope: .historyAndAudio)
        print("ARCHITECTURE_FIXTURE_PASS cleanup-legacy-refusal-retry")
    }

    private static func verifyLegacyAudioAfterHistory() async throws {
        let fixture = try Fixture(legacyScope: .audio, legacyHistoryCompleted: true)
        defer { fixture.close() }
        guard let original = fixture.seededDocument, let history = fixture.app.history else {
            throw Failure.assertion("Missing completed-audio legacy document")
        }
        fixture.probe.refuse = true
        await fixture.app.performCleanup(.audio)
        try require(fixture.app.cleanup.pendingScope == .audio && fixture.app.pipeline.isMaintainingData,
                    "Completed-audio legacy refusal lost its fence")
        try require(fixture.app.cleanup.completedSteps == ["pending", "history"], "Completed-audio phases changed after refusal")
        try require(try history.document(id: original.id) == original, "Completed-audio refusal lost remote references")
        try require(fixture.app.cleanupRecoveryKeyReferences == [original.configuration.asr.keyRef],
                    "Completed-audio legacy journal trapped access repair")
        fixture.probe.refuse = false
        await fixture.app.performCleanup(.audio)
        try require(fixture.probe.calls == 2 && fixture.app.cleanup.finishedScope == .audio,
                    "Completed-audio legacy cleanup did not recover")
        let saved = try history.document(id: original.id)
        try require(saved != nil && saved?.remoteFileID == nil && saved?.remoteJobID == nil && saved?.recordingID == nil,
                    "Completed-audio recovery lost text or retained remote IDs")
        let recordings = try history.recordings().entries
        try require(recordings.count == 1 && history.audioURL(for: recordings[0].asset) != nil,
                    "Completed audio deletion repeated and removed the sentinel")
        try require(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("MediaStaging").path),
                    "Completed-audio recovery left staging files")
        try require(!fixture.app.pipeline.isMaintainingData && fixture.app.cleanupRecoveryKeyReferences.isEmpty,
                    "Completed-audio cleanup did not release its recovery state")
        try assertStillOwned(fixture)
        print("ARCHITECTURE_FIXTURE_PASS cleanup-legacy-audio-after-history")
    }

    private static func verifyJournalRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        _ = try fixture.createMedia()
        // The first destructive phase completes, then meeting-draft removal
        // fails against a disposable non-directory. The journal must resume.
        let obstruction = fixture.directory.appendingPathComponent("MeetingStaging")
        try Data([0]).write(to: obstruction)
        await fixture.app.performCleanup(.historyAndAudio)
        try require(fixture.app.cleanup.pendingScope == .historyAndAudio && fixture.app.pipeline.isMaintainingData,
                    "Interrupted destructive cleanup lost its fence")
        try require(fixture.app.cleanup.completedSteps == ["pending", "history"], "Completed cleanup phases were not recorded")
        try assertStillOwned(fixture)
        try FileManager.default.removeItem(at: obstruction)
        // A sentinel inserted only by this fixture detects repetition of the
        // already-checkpointed history phase. Production entrypoints stay fenced.
        _ = try fixture.app.history?.saveRecording(samples: [0.1], source: .imported)
        await fixture.app.performCleanup(.historyAndAudio)
        try require(fixture.probe.calls == 1, "Journal retry repeated provider preparation")
        try require(fixture.app.cleanup.finishedScope == .historyAndAudio, "Journal retry did not finish")
        try require(try fixture.app.history?.recordings().entries.count == 1, "Journal retry repeated a completed destructive phase")
        try assertStillOwned(fixture)
        print("ARCHITECTURE_FIXTURE_PASS cleanup-journal-retry")
    }

    private static func verifyMaintenanceStateCallbacks() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let app = fixture.app
        app.wirePipelineStateChanges()
        // Synchronous synthetic processing reaches no capture/provider work;
        // cancel before its task can resume. Completion callbacks must preserve
        // the processing owner's aggregate busy state.
        app.pipeline.processSamples([0])
        try require(app.pipeline.isBusy, "Synthetic processing did not claim pipeline ownership")
        app.media?.onBusyChanged?(false)
        try require(app.models.dictationBusy, "Media completion released a processing owner's models")
        app.meeting?.onBusyChanged?(false)
        try require(app.models.dictationBusy, "Meeting completion released a processing owner's models")
        app.pipeline.cancel()
        app.models.start() // Remote selection plus refinement off: no engine/provider work.
        await app.cleanup.execute(.reset, prepare: { try app.pipeline.beginDataMaintenance() }, steps: [
            .init("models", title: "Unloading models") { try await app.models.prepareForDataReset() },
            .init("fixtureStop", title: "Injected interruption") { throw Failure.injected }
        ])
        try require(app.cleanup.pendingScope == .reset && app.cleanup.completedSteps == ["models"],
                    "Fixture did not pause reset after model preparation")
        try require(app.models.dictationBusy && app.pipeline.isMaintainingData, "Reset did not retain model ownership")
        try app.pipeline.cancelFromAutomation()
        try require(app.pipeline.state == .idle && app.pipeline.isMaintainingData && app.models.dictationBusy,
                    "Cancellation idle callback released model ownership during pending reset")

        let preparing = try Fixture()
        defer { preparing.close() }
        preparing.app.wirePipelineStateChanges()
        var preparationChecked = false
        await preparing.app.cleanup.execute(.history, prepare: {
            try preparing.app.pipeline.cancelFromAutomation()
            try require(preparing.app.cleanup.isRunning && !preparing.app.pipeline.isMaintainingData && preparing.app.models.dictationBusy,
                        "Cancellation idle callback released model ownership during pre-journal preparation")
            preparationChecked = true
            throw Failure.injected
        }, steps: [])
        try require(preparationChecked, "Pre-journal callback assertion did not finish")
        print("ARCHITECTURE_FIXTURE_PASS cleanup-state-callbacks")
    }

    private static func verifyBlockedCopy() async throws {
        let name = "airdraft.owner.\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(defaults: defaults)
        settings.asr = ASRConfig(kind: .openAI); settings.llm = LLMConfig(kind: .none)
        var owner: AppContainer? = AppContainer(settings: settings, dataDirectory: directory)
        try require(owner?.dataLease != nil, "First data owner was rejected")
        let names = ["dictionary.json", "profiles.json", "cleanup.json"]
        for name in names { try Data("unreadable fixture".utf8).write(to: directory.appendingPathComponent(name)) }
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        var accessChecks = 0
        let blocked = AppContainer(settings: settings, dataDirectory: directory, recordingAccessCheck: { accessChecks += 1 })
        blocked.pipeline.startRecording()
        await blocked.pipeline.retryHistorySave()
        for _ in 0..<5 { await Task.yield() }
        try require(blocked.dataLease == nil && blocked.history == nil && blocked.media == nil && blocked.meeting == nil,
                    "Second container opened shared stores")
        try require(blocked.pipeline.isMaintainingData && accessChecks == 0, "Blocked container started work")
        try require(blocked.dictionary.persistenceError == nil && blocked.profiles.persistenceError == nil && blocked.cleanup.error == nil,
                    "Blocked container inspected shared JSON")
        try require(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == before,
                    "Blocked container repaired or rewrote the owner's files")
        for name in names {
            try require(try Data(contentsOf: directory.appendingPathComponent(name)) == Data("unreadable fixture".utf8), "Blocked copy changed \(name)")
            try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        try owner?.history?.close()
        owner = nil
        let replacement = AppContainer(settings: settings, dataDirectory: directory)
        try require(replacement.dataLease != nil && replacement.history != nil, "Released owner prevented a fresh copy from opening")
        try replacement.history?.close()
        print("ARCHITECTURE_FIXTURE_PASS lifetime-single-writer")
    }

    private static func verifyPracticeWiring() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for (selected, bound) in [(ASRProviderKind.senseVoice, ASRProviderKind.openAI), (.openAI, .senseVoice), (.senseVoice, .groq)] {
            fixture.settings.asr = ASRConfig(kind: selected, language: "en")
            var boundConfig = ASRConfig(kind: bound)
            if bound == .groq { boundConfig.model = "retired-model" }
            var profile = fixture.app.profiles.activeProfile
            profile.speechModel = ProfileSpeechModel(config: boundConfig)
            fixture.app.profiles.update(profile)
            let stored = try Data(contentsOf: fixture.directory.appendingPathComponent("profiles.json"))
            fixture.settings.beginOnboardingPractice()
            try require(fixture.app.speechConfig.kind == selected && fixture.app.pipeline.speechConfig.kind == selected && fixture.app.models.speechConfig.kind == selected,
                        "App, pipeline and model loader disagree on the practice engine")
            try require(fixture.app.effectiveProfile.speechModel == nil && !fixture.app.effectiveProfile.usesLLM,
                        "Practice retained the stored profile binding or refinement")
            fixture.settings.endOnboardingPractice()
            try require(fixture.app.speechConfig.kind == bound && fixture.app.pipeline.speechConfig.kind == bound && fixture.app.models.speechConfig.kind == bound,
                        "Practice exit did not restore profile precedence")
            try require(try Data(contentsOf: fixture.directory.appendingPathComponent("profiles.json")) == stored,
                        "Practice rewrote the saved profile")
        }
        print("ARCHITECTURE_FIXTURE_PASS practice-wiring")
    }
}
#endif
