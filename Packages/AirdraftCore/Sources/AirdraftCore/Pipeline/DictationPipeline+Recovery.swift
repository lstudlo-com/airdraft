import Foundation

/// Kept recordings: failed audio waits in memory for an explicit retry or
/// discard, and History's review sheet retranscribes without delivery.
extension DictationPipeline {
    /// New dictation stays available while failed recordings wait. Bound their
    /// memory: at most three kept dictations and 15 minutes of 16 kHz audio
    /// (~58 MB) including the recording in progress. Kept audio is never dropped
    /// to make room. Instead a new recording may capture only the budget that
    /// remains, `availableRecordingSeconds`, so its own failure can always be
    /// kept; it stops there with a notice saying why. Recording is refused (ask
    /// for a retry or discard) only when the count is full or less than
    /// `minimumBudgetedRecordingSeconds` remain.
    public static let maximumPendingRecordings = 3
    public static let maximumPendingRecordingSeconds: Double = 900
    /// The shortest recording worth starting: Settings' lowest recording limit.
    public static let minimumBudgetedRecordingSeconds = Double(SpeechInputLimits.recordingSecondsRange.lowerBound)

    /// Seconds of kept dictation audio waiting for retry or discard.
    var keptDictationSeconds: Double {
        recoveries.filter { !$0.info.isReview }.reduce(0) { $0 + $1.info.seconds }
    }

    /// How long the next recording may capture: its effective limit, shortened
    /// so kept audio plus this recording stays within the memory bound.
    public var availableRecordingSeconds: Double {
        let limit = Double(SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: speechConfig.kind))
        return min(limit, max(0, keptAudioBudgetSeconds - keptDictationSeconds))
    }

    /// True when kept audio, not the recording limit, will end the next recording.
    public var keptAudioShortensNextRecording: Bool {
        availableRecordingSeconds < Double(SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: speechConfig.kind))
    }

    public var canKeepAnotherRecording: Bool {
        recoveries.filter { !$0.info.isReview }.count < Self.maximumPendingRecordings
            && availableRecordingSeconds >= minimumRecordingWithinBudget
    }

    /// Shown when a recording stopped at the kept-audio budget instead of its limit.
    func keptBudgetStopNotice(seconds: Double) -> String {
        let duration = Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
        return String(localized: "Recording stopped at \(duration) because recordings waiting for retry use the rest of the memory limit. Retry or discard them in Airdraft for longer recordings.", bundle: .module)
    }

    /// Review old audio without insertion, clipboard changes, or duplicate history.
    /// This delivery policy survives speech failures and explicit retries.
    public func retranscribe(_ record: DictationRecord) {
        guard let history else { return }
        retranscribe { try history.audioSamples(for: record) }
    }

    public func retranscribe(_ asset: RecordingAsset) {
        guard let history else { return }
        retranscribe { try history.audioSamples(for: asset) }
    }

    func retranscribe(loadSamples: @escaping @Sendable () throws -> [Float]) {
        guard !isBusy else { return }
        // One review at a time: its recovery belongs to the sheet that started it.
        recoveries.removeAll { $0.info.isReview }
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        let token = generation
        reviewGeneration = token
        reviewOutcome = nil
        lastIssue = nil
        let snapshot = recordingSnapshot()
        set(.transcribing)
        processingTask = Task {
            do {
                try await accessCheck()
                guard isCurrent(token) else { return }
                let samples = try await Task.detached(operation: loadSamples).value
                guard isCurrent(token) else { return }
                await process(samples: samples, seconds: Double(samples.count) / AudioRecorder.sampleRate,
                              context: .empty, target: nil, token: token, snapshot: snapshot, reviewOnly: true)
            } catch {
                guard isCurrent(token) else { return }
                fail(String(localized: "Recording could not be opened.", bundle: .module) + " " + error.localizedDescription)
                if error is LicenseError { onRecordingBlocked?() }
            }
        }
    }

    public func dismissReview() {
        // The reviewed audio stays in History; closing the sheet ends its recovery.
        recoveries.removeAll { $0.info.isReview }
        if reviewGeneration == generation {
            cancel()
            reviewOutcome = nil
            reviewGeneration = nil
            lastIssue = nil
        }
    }

    /// Discards `id`, or the newest kept recording when `id` is nil.
    public func discardRecording(_ id: UUID? = nil) {
        guard !isBusy, let index = recoveryIndex(id) else { return }
        let removed = recoveries.remove(at: index)
        if lastIssue == removed.info.issue || recoveries.isEmpty { lastIssue = nil }
        set(.idle)
    }

    /// Retries `id`, or the newest kept recording when `id` is nil. Current
    /// processing settings apply; the original delivery target and policy stay.
    /// A caretless target is copied instead of pasted, and a retry during
    /// onboarding practice only copies: practice never runs a saved script.
    public func retryRecording(_ id: UUID? = nil) {
        guard !isBusy, let index = recoveryIndex(id) else { return }
        let recovery = recoveries[index]
        let snapshot = recordingSnapshot(output: recovery.output, app: recovery.profileApp)
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        let token = generation
        retryingRecovery = (token, recovery.info.id)
        if recovery.reviewOnly { reviewGeneration = token }
        set(.transcribing)
        let delivery: DeliveryPolicy = settings.isOnboardingPractice ? .copyOnly : .retry
        processingTask = Task {
            await process(samples: recovery.samples, seconds: recovery.info.seconds,
                          context: recovery.context, target: recovery.target, token: token, snapshot: snapshot,
                          reviewOnly: recovery.reviewOnly, delivery: delivery)
        }
    }

    func recoveryIndex(_ id: UUID?) -> Int? {
        guard let id else { return recoveries.indices.last }
        return recoveries.firstIndex { $0.info.id == id }
    }

    /// Keeps failed audio. A failed retry replaces its own entry and becomes the newest.
    func retain(_ samples: [Float], context: AppContext, target: InsertionTarget?, reviewOnly: Bool = false,
                        output: OutputSnapshot? = nil, profileApp: String? = nil, issue: String, replacing id: UUID? = nil) {
        var isReview = reviewOnly && reviewGeneration == generation
        var profileApp = profileApp
        if let id, let index = recoveries.firstIndex(where: { $0.info.id == id }) {
            isReview = recoveries[index].info.isReview
            profileApp = profileApp ?? recoveries[index].profileApp
            recoveries.remove(at: index)
        }
        if isReview { recoveries.removeAll { $0.info.isReview } }
        let info = PendingRecording(id: id ?? UUID(), createdAt: Date(), seconds: Double(samples.count) / AudioRecorder.sampleRate,
                                    issue: issue, isReview: isReview)
        recoveries.append(Recovery(info: info, samples: samples, context: context, target: target, reviewOnly: reviewOnly,
                                   output: output ?? recordingAtStart?.output ?? selectedOutput(),
                                   profileApp: profileApp))
    }

    /// Successful or silent processing resolves the recovery a retry was
    /// processing, once its result is held by History's pending saves or the
    /// review outcome. Cancellation before that point keeps the audio.
    func resolveRecovery(for token: UUID) {
        guard let retrying = retryingRecovery, retrying.token == token else { return }
        retryingRecovery = nil
        recoveries.removeAll { $0.info.id == retrying.id }
    }
}
