import Foundation

/// History persistence, saved-audio cleanup and data maintenance fences.
extension DictationPipeline {
    /// Applies audio retention and reconciles missing or orphaned files. The
    /// pass examines every asset, so the app runs it at launch, hourly and after
    /// a retention change; saving a dictation never does. Audio views refresh
    /// only when it changed something or recovered from an earlier failure.
    public func pruneSavedAudio() async {
        guard !isMaintainingData, let history else { return }
        let cutoff = settings.audioRetention.cutoff()
        do {
            let changed = try await Task.detached { try history.pruneAudio(olderThan: cutoff) }.value
            if changed > 0 || audioStorageError != nil { audioRevision += 1 }
            audioStorageError = nil
        } catch { audioStorageError = String(localized: "Saved audio could not be removed.", bundle: .module) + " " + error.localizedDescription }
    }

    /// Saves pending dictations. Calls are serialized: a caller that arrives
    /// during another save waits for it, then saves anything it left behind.
    public func retryHistorySave() async {
        while let running = historySaveTask {
            await running.value
            if unsavedHistory.isEmpty && historyStorageError == nil { return }
            // Another waiter may already have started the follow-up save.
            if historySaveTask == nil { break }
        }
        guard !isMaintainingData else { return }
        isSavingHistory = true
        let task = Task { @MainActor in await self.saveUnsavedHistory() }
        historySaveTask = task
        await task.value
    }

    func saveUnsavedHistory() async {
        defer {
            isSavingHistory = false
            historySaveTask = nil
        }
        do {
            if historyStore == nil, let historyDirectory { historyStore = try HistoryStore(directory: historyDirectory) }
            guard let historyStore else { return }
            while let pending = unsavedHistory.first {
                let audio = settings.audioRetention == .off ? nil : pending.samples
                _ = try await Task.detached { try historyStore.save(pending.record, samples: audio) }.value
                unsavedHistory.removeFirst()
            }
            historyStorageError = nil
        } catch {
            historyStorageError = String(localized: "History could not be saved. Your unsaved dictations remain in memory.", bundle: .module) + " " + error.localizedDescription
        }
    }

    /// Freeze every entry point before deletion. Existing writes must finish
    /// first; setting the flag is synchronous on the same actor as those starts.
    /// `reason` replaces the generic cleanup message shown for a rejected
    /// shortcut, e.g. when another running copy holds the data lease.
    public func beginDataMaintenance(reason: String? = nil) throws {
        guard !isCapturingMeeting, !isProcessingMedia, !state.isBusy, recordingRequest == nil, !isSavingHistory,
              !isFinishingDelivery else { throw CleanupError.busy }
        isMaintainingData = true
        maintenanceReason = reason
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        resetTask?.cancel()
        audioRevision += 1
    }

    public func endDataMaintenance() {
        isMaintainingData = false
        maintenanceReason = nil
    }

    /// Delivered dictations still saving history or restoring the clipboard.
    public var hasPendingDelivery: Bool { isFinishingDelivery || isSavingHistory || inserter.hasPendingClipboardRestoration }

    /// Waits for delivered dictations to reach history. Quit passes
    /// `flushClipboard` to restore the displaced clipboard without the delay;
    /// delivery is already confirmed, so the receiver has read the transcript.
    public func finishPendingDelivery(flushClipboard: Bool = false) async {
        await inserter.finishClipboardRestoration(immediately: flushClipboard)
        while let tail = deliveryTail { await tail.value }
        if let historySaveTask { await historySaveTask.value }
    }

    public func prepareDataRemoval(_ scope: DataCleanupScope) async throws {
        guard isMaintainingData else { throw CleanupError.busy }
        if scope == .history {
            // Pending text must not reappear on Save Retry. Retain its audio as
            // a detached asset before discarding the pending transcript.
            while let pending = unsavedHistory.first {
                if let samples = pending.samples, !samples.isEmpty {
                    guard let history else { throw CleanupError.storageUnavailable }
                    _ = try await Task.detached {
                        try history.saveRecording(samples: samples, createdAt: pending.record.createdAt)
                    }.value
                }
                unsavedHistory.removeFirst()
            }
            recoveries = recoveries.map { saved in
                var saved = saved
                saved.context = .empty; saved.target = nil; saved.reviewOnly = true
                return saved
            }
        } else if scope.removesHistory {
            unsavedHistory = []
        } else {
            unsavedHistory = unsavedHistory.map { ($0.record, nil) }
        }
        if scope.removesAudio { recoveries = []; retryingRecovery = nil }
        if scope.removesHistory {
            lastOutcome = nil; reviewOutcome = nil; lastIssue = nil; historyStorageError = nil
        }
        audioStorageError = nil
        stopPreview()
        levelHistory = []
    }

    public func closeHistoryForReset() async throws {
        guard isMaintainingData else { throw CleanupError.busy }
        if let history { try await Task.detached { try history.close() }.value }
        historyStore = nil
    }
}
