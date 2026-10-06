import AppKit
import AirdraftCore

extension AppContainer {
    var cleanupRecoveryKeyReferences: [String] {
        guard cleanup.pendingScope != nil, cleanup.error != nil, !cleanup.isRunning,
              history != nil else { return [] }
        return media?.cleanupKeyReferences ?? []
    }

    func cleanupPreview(allowUnavailable: Bool = false) async throws -> CleanupPreview {
        guard let history else {
            guard allowUnavailable else { throw CleanupError.storageUnavailable }
            let directory = dataDirectory
            return try await Task.detached {
                CleanupPreview(historyCount: 0, recordingCount: 0,
                               audioBytes: try ManagedDataFiles.bytes(in: directory.appendingPathComponent("Recordings")),
                               managedBytes: try ManagedDataFiles.bytes(in: directory), countsAvailable: false)
            }.value
        }
        return try await Task.detached { try history.cleanupPreview() }.value
    }

    /// The coordinator holds the UI/pipeline fence until cleanup succeeds.
    /// The app retains its exclusive data lease for its entire lifetime.
    func performCleanup(_ scope: DataCleanupScope) async {
        let directory = dataDirectory
        var steps: [DataCleanupCoordinator.Step] = [
            .init("pending", title: "Clearing recovery data") { try await self.pipeline.prepareDataRemoval(scope) },
            .init("history", title: scope.title) {
                guard let history = self.history else {
                    if scope == .reset { return } // Reset can remove an unreadable database after closing.
                    throw CleanupError.storageUnavailable
                }
                try await Task.detached {
                    switch scope {
                    case .history: try history.deleteHistoryKeepingAudio()
                    case .audio: try history.deleteAllAudio()
                    case .historyAndAudio, .reset: try history.deleteAll()
                    }
                }.value
            }
        ]
        if scope != .history {
            steps.append(.init("meetingDrafts", title: "Removing meeting recovery audio") {
                try await Task.detached { try MeetingAudioStore.removeDrafts(in: directory) }.value
                self.meeting?.refreshDrafts()
            })
        }
        if scope == .reset {
            steps += [
                .init("models", title: "Unloading models") {
                    try await self.models.prepareForDataReset()
                },
                .init("files", title: "Removing app files") {
                    try await self.pipeline.closeHistoryForReset()
                    try await Task.detached { try ManagedDataFiles.resetContents(in: directory) }.value
                },
                .init("caches", title: "Removing app caches") {
                    guard !self.isolatedData else { return }
                    try await Task.detached { try AppResetAdapters.removeAppCaches() }.value
                },
                .init("keys", title: "Removing provider keys") {
                    guard !self.isolatedData else { return }
                    try await Task.detached { try AppResetAdapters.removeProviderCredentials() }.value
                },
                .init("settings", title: "Resetting preferences") {
                    guard !self.isolatedData else { return }
                    AppResetAdapters.resetPreferences(in: .standard, domains: AppResetAdapters.preferenceDomains)
                },
                .init("permissions", title: "Resetting app permissions") {
                    guard !self.isolatedData else { return }
                    try await AppResetAdapters.resetPermissions(bundleID: Bundle.main.bundleIdentifier ?? "")
                }
            ]
        }
        await cleanup.execute(scope, prepare: {
            guard !self.downloads.isBusy, (!self.pipeline.isBusy || self.pipeline.isMaintainingData), !self.pipeline.isSavingHistory else { throw CleanupError.busy }
            if !self.isolatedData {
                let siblings = NSWorkspace.shared.runningApplications.filter {
                    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                    AppResetAdapters.preferenceDomains.contains($0.bundleIdentifier ?? "")
                }
                guard siblings.isEmpty else { throw CleanupError.otherInstance }
            }
            guard self.dataLease?.holdsLease == true else { throw CleanupError.otherInstance }
            // Repeat this idempotent preparation on resume: older journals did
            // not prepare remote resources. Retained IDs must be cleaned before
            // any remaining deletion. A closed reset store has no IDs to read.
            if self.history != nil { try await self.media?.prepareCleanup() }
            try self.pipeline.beginDataMaintenance()
            self.hotkeys.suspended = true
        }, steps: steps, finish: { succeeded in
            NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
            if !self.cleanup.blocksWork && self.cleanup.finishedScope != .reset {
                if self.dataLease?.holdsLease == true {
                    self.pipeline.endDataMaintenance()
                    self.hotkeys.suspended = false
                    self.models.setDictationBusy(self.pipeline.isBusy)
                    self.models.start()
                }
            }
        })
    }
}
