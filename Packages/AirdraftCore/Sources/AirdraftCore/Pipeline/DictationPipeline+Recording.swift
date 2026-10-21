import Foundation

/// Startup, capture and cancellation. Recording prerequisites are checked
/// before the microphone opens; every callback belongs to its session token.
extension DictationPipeline {
    // MARK: - Control

    public func toggle() {
        if recordingRequest != nil && !isRecording { cancel() }
        else if isRecording { stopAndProcess() } else { startRecording() }
    }

    public func startRecording() {
        // Recording, startup and processing are already visible in the HUD.
        guard !state.isBusy, recordingRequest == nil else { return }
        if let reason = exclusiveWorkReason {
            // Never drop a shortcut press silently while nothing else is shown.
            fail(reason)
            return
        }
        guard canKeepAnotherRecording else {
            // Never drop kept audio to make room; ask for a retry or discard instead.
            fail(String(localized: "Several recordings are waiting for retry. Open Airdraft to retry or discard one before recording again.", bundle: .module), openRecovery: true)
            return
        }
        let token = UUID()
        recordingRequestID = token
        generation = token
        recordingRequest = Task {
            await beginRecording(token: token)
            // Every early return or cancellation before capture ends the pin.
            if !(isCurrent(token) && isRecording) { releaseSpeechSessionPin(for: token) }
            if recordingRequestID == token { recordingRequest = nil }
        }
    }

    /// App Intents use the same startup task and only report success once capture begins.
    public func startFromAutomation() async throws {
        if isRecording { return }
        guard !isBusy else { throw RecordingPrerequisiteError(String(localized: "Airdraft is already starting or processing a recording.", bundle: .module)) }
        guard canKeepAnotherRecording else { throw RecordingPrerequisiteError(String(localized: "Retry or discard the saved recording in Airdraft first.", bundle: .module)) }
        try Task.checkCancellation()
        startRecording()
        let token = recordingRequestID
        guard let request = recordingRequest else {
            throw RecordingPrerequisiteError(lastIssue ?? String(localized: "Recording could not start.", bundle: .module))
        }
        do {
            try await OperationDeadline.run(seconds: 15) { await request.value }
            try Task.checkCancellation()
        } catch {
            if recordingRequestID == token, generation == token { cancel() }
            if case RefinerError.timeout = error {
                throw RecordingPrerequisiteError(String(localized: "Recording startup timed out. Open Airdraft to check the selected model and permissions.", bundle: .module))
            }
            throw error
        }
        guard generation == token else { throw CancellationError() }
        guard isRecording else { throw RecordingPrerequisiteError(lastIssue ?? String(localized: "Recording did not start.", bundle: .module)) }
    }

    public func stopFromAutomation() throws {
        guard isRecording || recordingRequest != nil || !isBusy else {
            throw RecordingPrerequisiteError(String(localized: "Airdraft is already processing a recording.", bundle: .module))
        }
        stopAndProcess()
    }

    public func cancelFromAutomation() throws {
        guard state != .inserting else {
            throw RecordingPrerequisiteError(String(localized: "Text delivery has started and cannot be cancelled safely.", bundle: .module))
        }
        cancel()
    }

    func selectedOutput() -> OutputSnapshot {
        OutputSnapshot(destination: settings.outputDestination, scriptPath: settings.outputScriptPath,
                       insertionMethod: settings.insertionMethod)
    }

    func recordingSnapshot(output: OutputSnapshot? = nil) -> RecordingSnapshot {
        let profile = settings.effectiveProfile(profiles.activeProfile)
        return RecordingSnapshot(asr: profile.speechConfig(default: settings.asr), profile: profile,
                                 llm: settings.llm, microphone: settings.microphone,
                                 output: output ?? selectedOutput(), baseRules: profiles.baseRules,
                                 dictionary: dictionary.entries, useAppContext: settings.useAppContext)
    }

    func beginRecording(token: UUID) async {
        guard isCurrent(token) else { return }
        let snapshot = recordingSnapshot()
        let asr = snapshot.asr
        let llm = snapshot.llm
        let profile = snapshot.profile
        let microphone = snapshot.microphone
        let output = snapshot.output
        let needsInsertion = insertionEnabled && output.destination == .cursor
        // Read earlier dictations while startup checks run, before the destination is known.
        let recentFinals = snapshot.useAppContext ? prefetchRecentFinals(appBundleId: nil) : nil
        do {
            try await accessCheck()
            guard isCurrent(token) else { return }
            if let reason = profile.speechModel?.unavailableReason {
                throw RecordingPrerequisiteError(reason)
            }
            if insertionEnabled, output.destination == .script, let reason = ScriptDelivery.unavailableReason(path: output.scriptPath) {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start.", bundle: .module) + " " + reason)
            }
            _ = try SpeechLanguagePolicy.resolve(asr)
            if let recordingPreflight {
                try await recordingPreflight(asr, llm, profile.usesLLM, microphone, needsInsertion)
            } else {
                try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: profile.usesLLM,
                                                 microphone: microphone, insertionEnabled: needsInsertion)
            }
            guard isCurrent(token) else { return }
            guard recordingSnapshot() == snapshot else {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            }
            if asr.kind.isLocal {
                // Pin before checking readiness so the idle watch cannot unload
                // the model between this check and the end of processing.
                let limit = SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: asr.kind)
                let pin = await factory.pinForSession(asr.engineID, recordingSeconds: TimeInterval(limit))
                guard isCurrent(token) else { await factory.releaseSessionPin(pin); return }
                releaseSpeechSessionPin()
                speechSessionPin = (token, pin)
                let engine = await factory.transcriber(for: asr)
                let ready = await engine.isReady()
                guard isCurrent(token) else { return }
                if !ready {
                    set(.preparingModel)
                    // Join any startup/UI load through the factory's load lease.
                    try await factory.prepare(asr)
                } else {
                    // Capture can begin while cancelled inference winds down.
                    // A ready model needs only its idle timestamp refreshed.
                    await factory.markUsed(engine.id)
                }
            }
            guard isCurrent(token) else { return }
            guard recordingSnapshot() == snapshot else {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            }
        } catch {
            guard isCurrent(token) else { return }
            fail(error.localizedDescription)
            onRecordingBlocked?()
            return
        }
        let granted = await requestMicrophoneAccess()
        guard isCurrent(token) else { return }
        guard granted else {
            fail(String(localized: "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        guard recordingSnapshot() == snapshot else {
            fail(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        // Practice's own editor is inside Airdraft, which is never a paste target.
        let practice = needsInsertion && settings.isOnboardingPractice && practiceTarget?.acceptsDictation == true
        let insertionTarget = needsInsertion && !practice ? await inserter.captureTarget() : nil
        guard isCurrent(token) else { return }
        var context = snapshot.useAppContext ? contextReader.read() : .empty
        if let recentFinals, context.recentDictations.isEmpty {
            context.recentDictations = await recentFinals.finals(for: context.bundleId)
            guard isCurrent(token) else { return }
        }
        guard recordingSnapshot() == snapshot else {
            fail(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        recordingAtStart = snapshot
        insertionTargetAtStart = insertionTarget
        practiceDeliveryAtStart = practice
        contextAtStart = context
        wireRecorder(for: token)
        startPreview(for: token)
        do {
            try recorder.start(microphone: microphone)
        } catch {
            stopPreview()
            fail(String(localized: "Could not start recording: \(error.localizedDescription)", bundle: .module))
            onRecordingBlocked?()
            return
        }
        recordingStartedAt = Date()
        stopRequestedAt = nil
        levelHistory = []
        set(.recording)
        startRefinementPreparation(context: contextAtStart, snapshot: snapshot, token: token)

        let limit = SpeechInputLimits.recordingSeconds(settings.maxRecordingSeconds, for: asr.kind)
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard let self, self.isCurrent(token) else { return }
            self.finishRecording()
        }
    }

    /// Keep capturing briefly after the key is released: people let go while
    /// the last syllable is still sounding.
    public static let releaseGraceSeconds: Double = 0.35

    public func stopAndProcess() {
        if recordingRequest != nil && !isRecording {
            cancel()
            return
        }
        guard state == .recording, !stopping else { return }
        stopRequestedAt = ProcessInfo.processInfo.systemUptime
        stopping = true
        let token = generation
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.releaseGraceSeconds))
            guard self.isCurrent(token) else { return }
            self.stopping = false
            self.finishRecording()
        }
    }

    func finishRecording() {
        guard state == .recording, let snapshot = recordingAtStart else { return }
        if stopRequestedAt == nil { stopRequestedAt = ProcessInfo.processInfo.systemUptime }
        autoStopTask?.cancel()
        releaseTask?.cancel()
        stopping = false
        stopPreview()
        let samples = recorder.stop()
        recordingAtStart = nil
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        recordingStartedAt = nil

        guard seconds >= 0.3 else {
            discardRefinementPreparation()
            releaseSpeechSessionPin()
            set(.idle)
            return
        }
        set(.transcribing)
        let ctx = contextAtStart
        let token = generation
        let target = insertionTargetAtStart
        let delivery: DeliveryPolicy = practiceDeliveryAtStart ? .practice : .normal
        processingTask = Task { await process(samples: samples, seconds: seconds, context: ctx, target: target, token: token, snapshot: snapshot, delivery: delivery) }
    }

    public func cancel() {
        // Once a write begins, finish recording its outcome before accepting a new session.
        guard state != .inserting else { return }
        stopPreview()
        generation = UUID()
        // Kept recordings survive cancellation; only an explicit discard removes them.
        retryingRecovery = nil
        releaseTask?.cancel()
        discardRefinementPreparation()
        releaseSpeechSessionPin()
        stopRequestedAt = nil
        recordingRequestID = UUID()
        recordingRequest?.cancel()
        recordingRequest = nil
        stopping = false
        autoStopTask?.cancel()
        processingTask?.cancel()
        if recorder.isRecording { recorder.cancel() }
        recordingStartedAt = nil
        recordingAtStart = nil
        set(.idle)
    }

    // MARK: - Recorder callbacks and live preview

    func wireRecorder(for token: UUID) {
        recorder.levelHandler = { [weak self] level in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording else { return }
                self.levelHistory.append(level)
                if self.levelHistory.count > Self.levelHistoryLength {
                    self.levelHistory.removeFirst(self.levelHistory.count - Self.levelHistoryLength)
                }
            }
        }
        recorder.interruptionHandler = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording else { return }
                let samples = self.recorder.stop()
                let context = self.contextAtStart
                let target = self.insertionTargetAtStart
                let output = self.recordingAtStart?.output
                self.cancel()
                let message = reason.localizedDescription + (samples.isEmpty ? "" : " " + String(localized: "Captured audio is kept for retry.", bundle: .module))
                if !samples.isEmpty { self.retain(samples, context: context, target: target, output: output, issue: message) }
                self.fail(message, openRecovery: !samples.isEmpty)
            }
        }
    }

    func startPreview(for token: UUID) {
        stopPreview()
        guard settings.livePreviewEnabled, settings.hudStyle != .none else { return }
        previewEnabledForRecording = true
        let session = previewBuilder(settings.livePreviewLocale, { [weak self] text in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording, self.previewEnabledForRecording else { return }
                self.previewText = String(text.suffix(500))
            }
        }, { [weak self] issue in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.isRecording, self.previewEnabledForRecording else { return }
                self.previewText = ""
                self.previewIssue = issue
            }
        })
        previewSession = session
        recorder.samplesHandler = { samples in session.append(samples) }
    }

    /// Apply an explicit Off choice immediately without interrupting final capture.
    public func disableLivePreview() { stopPreview() }

    func stopPreview() {
        recorder.samplesHandler = nil
        previewSession?.cancel()
        previewSession = nil
        previewText = ""
        previewIssue = nil
        previewEnabledForRecording = false
    }
}
