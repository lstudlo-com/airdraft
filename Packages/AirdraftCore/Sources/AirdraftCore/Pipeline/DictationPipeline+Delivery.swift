import Foundation

/// Delivers final text exactly once, then releases the pipeline while the
/// delivery tail saves history and publishes the outcome in order.
extension DictationPipeline {
    /// What one delivery attempt achieved.
    struct DeliveryReport {
        var notice: String?
        var noticeRequiresAttention = true
        var deliveryError: String?
        /// The destination confirmed the text.
        var inserted = false
        /// Output reached its destination, confirmed or sent unverified.
        var outputSucceeded = false
        var sentUnverified = false
        /// Cancelled while an earlier unverified paste still owned the clipboard:
        /// nothing was written, the session no longer owns the pipeline, and the
        /// text goes to History as not delivered.
        var cancelledBeforeWriting = false
    }

    /// A script can have external side effects, so it is never retried and never
    /// falls back to pasting when its completion is uncertain.
    ///
    /// Cancel is accepted while an earlier unverified paste still owns the
    /// clipboard, and then nothing of this dictation is written. A fresh
    /// dictation's text and audio still reach History, marked not delivered
    /// (`cancelledBeforeWriting`). A retry returns nil: its kept recording stays
    /// for another retry or discard, so nothing is lost or duplicated.
    func deliver(_ final: String, output: OutputSnapshot, target: InsertionTarget?, token: UUID,
                 delivery: DeliveryPolicy, stopRequested: TimeInterval?,
                 timings: inout DictationTimings) async -> DeliveryReport? {
        set(.inserting)
        let deliveryStarted = ProcessInfo.processInfo.systemUptime
        if insertionEnabled, delivery == .copyOnly || output.destination == .cursor {
            // An earlier unverified paste's receiver may still read the clipboard,
            // so nothing is written until its window ends (at most
            // `unverifiedRestoreDelay`). Cancel stays available during this wait.
            deliveryAwaitingClipboard = true
            await inserter.waitForPendingReceiver()
            deliveryAwaitingClipboard = false
            guard isCurrent(token), !Task.isCancelled else {
                guard delivery == .normal || delivery == .practice else { return nil }
                timings.deliveryMs = Self.elapsed(since: deliveryStarted)
                let cancelled = String(localized: "Cancelled before delivery. The text was not pasted.", bundle: .module)
                return DeliveryReport(notice: cancelled, deliveryError: cancelled, cancelledBeforeWriting: true)
            }
        }
        var report = DeliveryReport()
        var reportedDelivery = false
        var stopToDeliveryMs: Int?
        let reportDelivery: () -> Void = { [weak self] in
            guard let self, self.isCurrent(token), !reportedDelivery else { return }
            reportedDelivery = true
            if let stopRequested { stopToDeliveryMs = Self.elapsed(since: stopRequested) }
            self.onOutputDelivered?()
        }
        if insertionEnabled, delivery == .copyOnly {
            // Neither a paste nor the recording's saved script: copy for the user.
            let result = inserter.copyOnly(final, notice: String(localized: "Retried text copied. Paste it where you want it.", bundle: .module),
                                           requiresAttention: false)
            report.notice = result.notice
            report.noticeRequiresAttention = result.noticeRequiresAttention
            if result.noticeRequiresAttention { report.deliveryError = result.notice }
        } else if insertionEnabled {
            switch output.destination {
            case .cursor:
                let result: InsertionResult
                if delivery == .practice {
                    result = practiceTarget?.insertDictation(final) == true
                        ? InsertionResult(method: .practiceEditor, notice: nil)
                        : inserter.copyOnly(final, notice: String(localized: "Copied to clipboard", bundle: .module), requiresAttention: false)
                } else if let insertText { result = await insertText(final, output.insertionMethod, target) }
                else {
                    result = await inserter.insert(final, method: output.insertionMethod, target: target,
                                                   allowsUnconfirmedPaste: delivery != .retry,
                                                   onDelivered: reportDelivery)
                }
                report.sentUnverified = result.delivery == .sentUnverified
                // `inserted` records only confirmed text. A paste sent to a
                // validated caretless editor succeeded without confirmation.
                report.inserted = result.didInsert
                report.outputSucceeded = result.wasSent
                report.notice = result.notice
                report.noticeRequiresAttention = result.noticeRequiresAttention
                if !result.wasSent, result.noticeRequiresAttention { report.deliveryError = result.notice }
            case .script:
                do {
                    try await sendScript(final, output.scriptPath)
                    report.outputSucceeded = true
                } catch {
                    report.deliveryError = String(localized: "Script delivery failed or was interrupted. It may already have acted; it was not retried. Your text is kept in History.", bundle: .module) + " " + error.localizedDescription
                    report.notice = report.deliveryError
                }
            }
        }
        if report.outputSucceeded { reportDelivery() }
        if let stopToDeliveryMs { timings.stopToDeliveryMs = stopToDeliveryMs }
        timings.deliveryMs = Self.elapsed(since: deliveryStarted)
        return report
    }

    /// Delivery has finished, so this session releases the pipeline before
    /// persistence: the next shortcut press can record at once. Saving and the
    /// outcome continue in a tail that keeps their order and that quit and data
    /// maintenance wait for.
    func finishDelivery(_ report: DeliveryReport, transcript: Transcript, refinement: RefinementStage, final: String,
                        samples: [Float], seconds: Double, context: AppContext, snapshot: RecordingSnapshot,
                        token: UUID, processingStarted: TimeInterval, timings: DictationTimings) {
        let output = snapshot.output
        var notice = report.notice
        var noticeRequiresAttention = report.noticeRequiresAttention
        defer { if keptBudgetStop?.token == token { keptBudgetStop = nil } }
        if refinement.llmError != nil, notice == nil {
            let reason = refinement.llmRejected ? String(localized: "Refinement didn't match your speech", bundle: .module) : String(localized: "Refinement unavailable", bundle: .module)
            notice = report.outputSucceeded
                ? (output.destination == .script ? String(localized: "\(reason); raw text sent to script.", bundle: .module)
                    : report.sentUnverified ? String(localized: "\(reason); raw text pasted.", bundle: .module)
                    : String(localized: "\(reason); raw text inserted.", bundle: .module))
                : String(localized: "\(reason); raw text is available in History.", bundle: .module)
        }

        let record = DictationRecord(
            appBundleId: context.bundleId,
            appName: context.appName,
            windowTitle: context.windowTitle,
            url: context.url,
            mode: snapshot.profile.name,
            family: AppFamily.classify(context).rawValue,
            rawTranscript: transcript.text,
            refinedText: refinement.refined,
            finalText: final,
            language: transcript.language,
            asrEngine: transcript.engine,
            llmEngine: refinement.llmEngine,
            promptVersion: refinement.promptVersion,
            audioSeconds: seconds,
            asrMs: transcript.latencyMs,
            llmMs: refinement.llmMs,
            inserted: report.inserted,
            error: (refinement.llmError != nil || report.deliveryError != nil)
                ? [refinement.llmError, report.deliveryError].compactMap { $0 }.joined(separator: "\n") : nil,
            outputDestination: insertionEnabled ? output.destination.rawValue : nil,
            outputSucceeded: insertionEnabled ? report.outputSucceeded : nil
        )
        // Delivered text always reaches history, whatever happens next.
        let savesHistory = history != nil || historyDirectory != nil
        if savesHistory {
            // Held in memory first: a failed save stays visible and retryable.
            unsavedHistory.append((record, settings.audioRetention == .off ? nil : samples))
        }
        // The result is delivered and held for History: only now may a retry
        // release the kept audio it was processing.
        resolveRecovery(for: token)
        discardRefinementPreparation(for: token)
        // A cancelled session no longer owns the state, the HUD or the last
        // issue, which a newer session may already use.
        let ownsState = !report.cancelledBeforeWriting
        let historyStarted = ProcessInfo.processInfo.systemUptime
        let previousTail = deliveryTail
        let tailID = UUID()
        deliveryTailID = tailID
        isFinishingDelivery = true
        let refined = refinement.refined
        let llmMs = refinement.llmMs
        let skipReason = refinement.skipReason
        deliveryTail = Task { @MainActor [timings] in
            var timings = timings
            await previousTail?.value
            if savesHistory { await self.retryHistorySave() }
            timings.historyMs = Self.elapsed(since: historyStarted)
            timings.processingMs = Self.elapsed(since: processingStarted)
            let outcome = DictationOutcome(
                raw: transcript.text, refined: refined, final: final,
                asrMs: transcript.latencyMs, llmMs: llmMs, llmSkippedReason: skipReason, timings: timings
            )
            Self.log.notice("delivery tail historyMs=\(timings.historyMs) processingMs=\(timings.processingMs)")
            self.lastOutcome = outcome
            self.onOutcome?(outcome)
            if self.deliveryTailID == tailID {
                self.deliveryTail = nil
                self.isFinishingDelivery = false
            }
        }
        guard ownsState else { return }
        if let budget = keptBudgetStop, budget.token == token {
            // The recording ended early: say so before any delivery notice.
            notice = [keptBudgetStopNotice(seconds: budget.seconds), notice].compactMap { $0 }.joined(separator: " ")
            noticeRequiresAttention = true
        }
        if let notice {
            lastIssue = notice
            set(.notice(notice, requiresAttention: noticeRequiresAttention))
            resetLater(after: 3)
        } else {
            lastIssue = nil
            set(.idle)
        }
    }
}
