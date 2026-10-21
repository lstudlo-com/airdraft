import Foundation

/// Transcription, best-effort refinement and post-processing for one session.
extension DictationPipeline {
    /// Runs 16 kHz mono samples through transcription, refinement, dictionary and
    /// history exactly like a recording would. Used by self-tests and the CLI.
    public func processSamples(_ samples: [Float], context: AppContext = .empty) {
        guard !isBusy else { return }
        generation = UUID()
        discardRefinementPreparation()
        stopRequestedAt = nil
        let snapshot = recordingSnapshot()
        let token = generation
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        levelHistory = []
        set(.transcribing)
        processingTask = Task {
            do {
                try await accessCheck()
                guard isCurrent(token) else { return }
                await process(samples: samples, seconds: seconds, context: context, target: nil, token: token, snapshot: snapshot)
            } catch {
                guard isCurrent(token) else { return }
                fail(error.localizedDescription)
                onRecordingBlocked?()
            }
        }
    }

    /// Build once, discover/load a managed model and start a supported CLI while
    /// recording/ASR is running. No transcript is sent until final recognition.
    func startRefinementPreparation(context: AppContext, snapshot: RecordingSnapshot, token: UUID) {
        guard refinementPreparation?.token != token else { return }
        discardRefinementPreparation()
        let config = snapshot.llm
        let profile = snapshot.profile
        guard profile.usesLLM, config.kind != .none else { return }
        let request = RefineRequest(
            transcript: "",
            profile: profile,
            baseRules: snapshot.baseRules,
            context: context,
            family: AppFamily.classify(context),
            dictionary: snapshot.dictionary,
            chineseScript: snapshot.asr.chineseScript
        )
        let preparation = RefinementPreparation(token: token)
        refinementPreparation = preparation
        let prepare = prepareRefinement
        preparation.task = Task { [factory] in
            // A cold native load may finish while a long recording continues.
            // Its speculative lifetime is independent of the final refinement
            // deadline, which still bounds the remaining wait plus the request.
            return try await OperationDeadline.run(seconds: 300) { @MainActor in
                try Task.checkCancellation()
                let setupStarted = ProcessInfo.processInfo.systemUptime
                preparation.setupStarted = setupStarted
                guard var refiner = await factory.refiner(for: config) else { throw RefinerError.invalidResponse }
                preparation.setupMs = Self.elapsed(since: setupStarted)
                preparation.setupStarted = nil
                try Task.checkCancellation()
                let modelStarted = ProcessInfo.processInfo.systemUptime
                preparation.modelStarted = modelStarted
                let backend: RefinementPreparationBackend
                do { backend = try await prepare?(config) ?? .unmanaged }
                catch {
                    preparation.modelMs = Self.elapsed(since: modelStarted)
                    preparation.modelStarted = nil
                    throw error
                }
                preparation.modelMs = Self.elapsed(since: modelStarted)
                preparation.modelStarted = nil
                try Task.checkCancellation()
                let warmStarted = ProcessInfo.processInfo.systemUptime
                if config.kind.isCLI { preparation.cliStarted = warmStarted }
                refiner = try await refiner.prepare(request, backend: backend, owner: token)
                if config.kind.isCLI {
                    preparation.cliMs = Self.elapsed(since: warmStarted)
                    preparation.cliStarted = nil
                }
                if backend == .lmStudio {
                    let preparedRefiner = refiner
                    preparation.prefixTask = Task { @MainActor in
                        guard !Task.isCancelled else { return }
                        let prefixStarted = ProcessInfo.processInfo.systemUptime
                        preparation.prefixStarted = prefixStarted
                        defer {
                            preparation.prefixMs = Self.elapsed(since: prefixStarted)
                            preparation.prefixStarted = nil
                        }
                        // Speculative work must never consume the final request's
                        // deadline. It is cancelled as soon as ASR is complete.
                        do {
                            try await OperationDeadline.run(seconds: config.timeoutSeconds) {
                                try await preparedRefiner.prewarmPrompt(request, backend: backend)
                            }
                        } catch {}
                    }
                }
                try Task.checkCancellation()
                return refiner
            }
        }
    }

    func discardRefinementPreparation(for token: UUID? = nil) {
        guard let preparation = refinementPreparation, token == nil || preparation.token == token else { return }
        preparation.task?.cancel()
        preparation.prefixTask?.cancel()
        refinementPreparation = nil
        Task { await CLIRefiner.discardPrewarm(owner: preparation.token) }
    }

    func releaseSpeechSessionPin(for token: UUID? = nil) {
        guard let current = speechSessionPin, token == nil || current.token == token else { return }
        speechSessionPin = nil
        Task { [factory] in await factory.releaseSessionPin(current.pin) }
    }


    // MARK: - Processing

    /// One session's refinement result. Any failure keeps the raw transcript.
    struct RefinementStage {
        var refined: String
        var llmMs = 0
        var llmEngine: String?
        var promptVersion: String?
        var skipReason: String?
        var llmError: String?
        var llmRejected = false
    }

    func process(samples: [Float], seconds: Double, context: AppContext, target: InsertionTarget?, token: UUID,
                 snapshot: RecordingSnapshot, reviewOnly: Bool = false, delivery: DeliveryPolicy = .normal) async {
        guard isCurrent(token) else { return }
        let processingStarted = ProcessInfo.processInfo.systemUptime
        let stopRequested = stopRequestedAt
        var timings = DictationTimings()
        timings.pressToCaptureMs = pressToCaptureMs(for: token)
        defer {
            discardRefinementPreparation(for: token)
            releaseSpeechSessionPin(for: token)
            // Silent, empty or cancelled sessions end without a notice; never leave
            // their budget stop behind.
            if keptBudgetStop?.token == token { keptBudgetStop = nil }
            Self.log.notice("processing timing totalMs=\(Self.elapsed(since: processingStarted)) preparationWaitMs=\(timings.preparationWaitMs) refinementRequestMs=\(timings.refinementRequestMs) postProcessingMs=\(timings.postProcessingMs) deliveryMs=\(timings.deliveryMs) historyMs=\(timings.historyMs) stopToDeliveryMs=\(timings.stopToDeliveryMs ?? -1) pressToCaptureMs=\(timings.pressToCaptureMs ?? -1)")
        }
        // Muted/digital-silence recordings contain no speech. Some recognizers
        // hallucinate on them; never let that text reach delivery or history.
        // Use exact silence, not a volume threshold that could reject quiet speech.
        guard samples.contains(where: { $0 != 0 }) else {
            resolveRecovery(for: token)
            lastIssue = nil
            set(.idle)
            return
        }
        var context = context
        if snapshot.useAppContext && context.recentDictations.isEmpty && stopRequested == nil {
            context.recentDictations = await prefetchRecentFinals(appBundleId: context.bundleId).finals(for: context.bundleId)
            guard isCurrent(token) else { return }
        }

        // 1. ASR
        guard let transcript = await transcribe(samples, context: context, target: target, token: token,
                                                snapshot: snapshot, reviewOnly: reviewOnly) else { return }
        guard isCurrent(token) else { return }
        refinementPreparation?.prefixTask?.cancel()
        lastIssue = nil
        guard !transcript.isEmpty else {
            resolveRecovery(for: token)
            set(.idle)
            return
        }

        // 2. LLM (best effort)
        let refinement = await refine(transcript, context: context, snapshot: snapshot, token: token, timings: &timings)
        guard isCurrent(token) else { return }

        // 3. Script normalisation, then the dictionary always has the last word.
        let postStarted = ProcessInfo.processInfo.systemUptime
        let normalised = ChineseScriptConverter.convert(refinement.refined, to: snapshot.asr.chineseScript)
        let final = DictionaryPostProcessor.apply(normalised, entries: snapshot.dictionary)
        timings.postProcessingMs = Self.elapsed(since: postStarted)

        if reviewOnly {
            timings.processingMs = Self.elapsed(since: processingStarted)
            reviewOutcome = DictationOutcome(raw: transcript.text, refined: refinement.refined, final: final,
                asrMs: transcript.latencyMs, llmMs: refinement.llmMs, llmSkippedReason: refinement.skipReason, timings: timings)
            resolveRecovery(for: token)
            lastIssue = refinement.llmError.map { String(localized: "Refinement failed; the original transcript is shown.", bundle: .module) + " " + $0 }
            set(.idle)
            return
        }

        // 4. Deliver once, then 5. hand persistence to the delivery tail.
        let report = await deliver(final, output: snapshot.output, target: target, token: token,
                                   delivery: delivery, stopRequested: stopRequested, timings: &timings)
        finishDelivery(report, transcript: transcript, refinement: refinement, final: final, samples: samples,
                       seconds: seconds, context: context, snapshot: snapshot, token: token,
                       processingStarted: processingStarted, timings: timings)
    }

    /// Recognises speech with the captured configuration. A failure keeps the
    /// audio for retry and returns nil, as does a session that is no longer current.
    func transcribe(_ samples: [Float], context: AppContext, target: InsertionTarget?, token: UUID,
                    snapshot: RecordingSnapshot, reviewOnly: Bool) async -> Transcript? {
        let asrConfig = snapshot.asr
        do {
            if let reason = snapshot.profile.speechModel?.unavailableReason {
                throw RecordingPrerequisiteError(reason)
            }
            let language = try SpeechLanguagePolicy.resolve(asrConfig)
            try SpeechInputLimits.validate(sampleCount: samples.count, for: asrConfig.kind)
            startRefinementPreparation(context: context, snapshot: snapshot, token: token)
            let hints = TranscriptionHints(
                language: language.language,
                vocabulary: DictionaryPostProcessor.vocabulary(snapshot.dictionary),
                chineseScript: asrConfig.chineseScript
            )
            return try await factory.transcribe(samples, hints: hints, config: asrConfig) { @MainActor [weak self] in
                guard let self, self.isCurrent(token) else { return }
                self.set(.preparingModel)
            }
        } catch {
            guard isCurrent(token) else { return nil }
            var message = String(localized: "Transcription failed: \(error.localizedDescription) Captured audio is kept for retry.", bundle: .module)
            if let budget = keptBudgetStop, budget.token == token {
                // AD-077: a recording shortened by kept audio says why with its failure too.
                keptBudgetStop = nil
                message += " " + keptBudgetStopNotice(seconds: budget.seconds)
            }
            let retried = retryingRecovery?.token == token ? retryingRecovery?.id : nil
            retryingRecovery = nil
            retain(samples, context: context, target: target, reviewOnly: reviewOnly, output: snapshot.output, issue: message, replacing: retried)
            fail(message, openRecovery: !reviewOnly)
            return nil
        }
    }

    /// Best-effort refinement. Errors, timeouts and fidelity rejections keep
    /// the raw transcript and are reported in the returned stage.
    func refine(_ transcript: Transcript, context: AppContext, snapshot: RecordingSnapshot, token: UUID,
                timings: inout DictationTimings) async -> RefinementStage {
        let llmConfig = snapshot.llm
        let profile = snapshot.profile
        var stage = RefinementStage(refined: transcript.text)
        let wordCount = Self.approximateWordCount(transcript.text)
        guard profile.usesLLM else {
            stage.skipReason = "\(profile.name): no LLM"
            return stage
        }
        guard wordCount >= llmConfig.minWordsForLLM || context.hasSelection else {
            stage.skipReason = "short utterance (\(wordCount) words)"
            return stage
        }
        guard llmConfig.kind != .none else {
            stage.skipReason = "LLM off"
            return stage
        }
        set(.refining)
        let request = RefineRequest(
            transcript: transcript.text,
            profile: profile,
            baseRules: snapshot.baseRules,
            context: context,
            family: AppFamily.classify(context),
            dictionary: snapshot.dictionary,
            chineseScript: snapshot.asr.chineseScript
        )
        let refinementStarted = ProcessInfo.processInfo.systemUptime
        let preparation = refinementPreparation
        let attempt = RefinementAttempt()
        do {
            let timeout = llmConfig.kind.isCLI ? max(60, llmConfig.timeoutSeconds) : llmConfig.timeoutSeconds
            let result = try await OperationDeadline.run(seconds: timeout) { @MainActor [self] in
                guard isCurrent(token) else { throw CancellationError() }
                guard let task = preparation?.task else { throw RefinerError.invalidResponse }
                let refiner = try await task.value
                preparation?.prefixTask?.cancel()
                try Task.checkCancellation()
                guard isCurrent(token) else { throw CancellationError() }
                attempt.preparationWaitMs = Self.elapsed(since: refinementStarted)
                let requestStarted = ProcessInfo.processInfo.systemUptime
                attempt.requestStarted = requestStarted
                defer {
                    attempt.requestMs = Self.elapsed(since: requestStarted)
                    attempt.requestFinished = true
                }
                return try await refiner.refine(request)
            }
            guard isCurrent(token) else { return stage }
            if let served = result.servedBy { onLLMUsed?(served, llmConfig) }
            let allowsLanguageChange = !profile.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || context.hasSelection
            if let violation = RefinementFidelity.violation(output: result.text, transcript: transcript.text,
                                                            recentDictations: context.recentDictations,
                                                            allowsLanguageChange: allowsLanguageChange) {
                Self.log.notice("refinement rejected: \(String(describing: violation), privacy: .public) engine=\(result.engine, privacy: .public)")
                stage.llmError = violation.message
                stage.llmRejected = true
                stage.skipReason = "LLM output rejected, using raw transcript"
            } else {
                stage.refined = result.text
                stage.llmEngine = result.engine
                stage.promptVersion = result.promptVersion
            }
        } catch {
            stage.llmError = error.localizedDescription
            stage.skipReason = "LLM failed, using raw transcript"
        }
        let llmMs = Int((ProcessInfo.processInfo.systemUptime - refinementStarted) * 1000)
        stage.llmMs = llmMs
        timings.preparationWaitMs = attempt.requestStarted == nil ? llmMs : attempt.preparationWaitMs
        timings.refinementRequestMs = attempt.requestFinished ? attempt.requestMs : attempt.requestStarted.map { Self.elapsed(since: $0) } ?? 0
        timings.refinerSetupMs = preparation?.setupDuration ?? 0
        timings.modelPreparationMs = preparation?.modelDuration ?? 0
        timings.cliWarmupMs = preparation?.cliDuration ?? 0
        timings.promptPrefixMs = preparation?.prefixDuration ?? 0
        let logged = timings
        Self.log.notice("refinement timing totalMs=\(llmMs) setupMs=\(logged.refinerSetupMs) modelPreparationMs=\(logged.modelPreparationMs) cliWarmupMs=\(logged.cliWarmupMs) promptPrefixMs=\(logged.promptPrefixMs) preparationWaitMs=\(logged.preparationWaitMs) requestMs=\(logged.refinementRequestMs) engine=\(llmConfig.engineLabel, privacy: .public)")
        return stage
    }

    /// Earlier dictations for `<recent_terms>` and the fidelity repeat check.
    /// Delivered dictations the delivery tail has not saved yet are snapshotted
    /// before saved rows are read off the main actor: a record saved in between
    /// is found in the database, and one saved earlier appears only once.
    func prefetchRecentFinals(appBundleId: String?) -> RecentFinalsPrefetch {
        let pending = unsavedHistory.map(\.record)
        let store = history
        let saved = Task.detached(priority: .userInitiated) { () -> [DictationRecord] in
            // Without a known destination, read every app's recent rows and filter later.
            (try? store?.recentRecords(appBundleId: appBundleId, limit: appBundleId == nil ? 200 : HistoryStore.recentFinalsLimit)) ?? []
        }
        return RecentFinalsPrefetch(pending: pending, saved: saved)
    }

    struct RecentFinalsPrefetch {
        let pending: [DictationRecord]
        let saved: Task<[DictationRecord], Never>

        func finals(for appBundleId: String?) async -> [String] {
            HistoryStore.recentFinals(saved: await saved.value, pending: pending, appBundleId: appBundleId)
        }
    }
}
