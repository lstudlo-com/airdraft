import AppKit
import AirdraftCore

extension AppContainer {
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

    /// The coordinator holds both the UI/pipeline fence and the process lease
    /// until every step succeeds. A failed reset can only retry its fixed scope.
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
            guard let lease = self.dataLease else { throw CleanupError.otherInstance }
            // Resolve provider cleanup before writing the local cleanup journal/fence.
            // A missing key must leave Configuration available for recovery.
            if !self.cleanup.blocksWork { try await self.media?.prepareCleanup() }
            try self.pipeline.beginDataMaintenance()
            do { try lease.acquireExclusive() }
            catch { throw error }
            self.hotkeys.suspended = true
        }, steps: steps, finish: { succeeded in
            NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
            if !self.cleanup.blocksWork && self.cleanup.finishedScope != .reset {
                self.dataLease?.releaseExclusive()
                if self.dataLease?.holdsLease == true {
                    self.pipeline.endDataMaintenance()
                    self.hotkeys.suspended = false
                    self.models.start()
                }
            }
        })
    }
}
