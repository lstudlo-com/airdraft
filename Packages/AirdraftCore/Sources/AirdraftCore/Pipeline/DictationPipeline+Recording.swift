import Foundation
import Synchronization

/// Startup, capture and cancellation. Recording prerequisites are checked
/// before the microphone opens; every callback belongs to its session token.
extension DictationPipeline {
    // MARK: - Control

    public func toggle(_ request: RecordingRequest = RecordingRequest()) {
        if recordingRequest != nil && !isRecording { cancel() }
        else if isRecording { stopAndProcess() } else { startRecording(request) }
    }

    public func startRecording(_ request: RecordingRequest = RecordingRequest()) {
        // Recording, startup and processing are already visible in the HUD.
        guard !state.isBusy, recordingRequest == nil else {
            noteIgnoredPressIfProcessing()
            return
        }
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
        activeRequest = request
        recordingBadge = nil
        noteAcceptedPress()
        // Shortcut acceptance (after any Trigger Delay) or an automation start.
        captureLatency = CaptureLatency(token: token, acceptedAt: ProcessInfo.processInfo.systemUptime)
        recordingRequest = Task {
            await beginRecording(token: token)
            // Every early return or cancellation before the recording state ends
            // the pin and any capture that had already started.
            if !(isCurrent(token) && isRecording) {
                if startingCapture == token, generation == token { abandonStartingCapture() }
                releaseSpeechSessionPin(for: token)
            }
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
        guard !deliveryCommitted else {
            throw RecordingPrerequisiteError(String(localized: "Text delivery has started and cannot be cancelled safely.", bundle: .module))
        }
        cancel()
    }

    /// `profile`'s own destination applies over the app's Output setting (AD-104).
    func selectedOutput(profile: RefinementProfile? = nil) -> OutputSnapshot {
        OutputSnapshot(destination: settings.outputDestination, scriptPath: settings.outputScriptPath,
                       insertionMethod: settings.insertionMethod, profileOutput: profile?.output)
    }

    /// `app` is the destination's bundle ID: its app rule chooses the profile,
    /// including the profile's speech model. Practice always uses the chosen profile.
    /// A profile shortcut's profile replaces the app rule's (AD-104).
    func recordingSnapshot(output: OutputSnapshot? = nil, app: String? = nil,
                           request: RecordingRequest = RecordingRequest()) -> RecordingSnapshot {
        var chosen = settings.isOnboardingPractice ? profiles.activeProfile : profiles.selection(forApp: app).profile
        if !settings.isOnboardingPractice, let id = request.profileID,
           let requested = profiles.profiles.first(where: { $0.id == id }) {
            chosen = requested
        }
        var profile = settings.effectiveProfile(chosen)
        if request.intent == .editSelection { profile = editProfile(from: profile) }
        return RecordingSnapshot(asr: profile.speechConfig(default: settings.asr), profile: profile,
                                 llm: settings.llm, microphone: settings.microphone,
                                 output: output ?? selectedOutput(profile: profile), baseRules: profiles.baseRules,
                                 dictionary: dictionary.entries, useAppContext: settings.useAppContext,
                                 profileApp: app,
                                 vocabularyBiasesOnDeviceSpeech: settings.vocabularyBiasesOnDeviceSpeech,
                                 request: request, speed: speedOptions())
    }

    func beginRecording(token: UUID) async {
        guard isCurrent(token) else { return }
        // The frontmost app chooses its rule's profile before any setup check;
        // `followCapturedApp` may adopt the captured destination below.
        var profileApp = frontmostBundleID()
        let request = activeRequest
        var snapshot = recordingSnapshot(app: profileApp, request: request)
        let asr = snapshot.asr
        let llm = snapshot.llm
        let profile = snapshot.profile
        let microphone = snapshot.microphone
        let output = snapshot.output
        let needsInsertion = insertionEnabled && output.target == .cursor
        // The recording limit of the provider that will transcribe (the
        // snapshot's, which an app rule may choose), shortened when kept
        // recordings use part of the memory bound. Fixed for this session: kept
        // audio cannot grow meanwhile.
        let limit = Double(recordingLimitSeconds(settings.maxRecordingSeconds, asr.kind))
        let allowedSeconds = availableRecordingSeconds(for: asr)
        let budgetLimited = allowedSeconds < limit
        // Read earlier dictations while startup checks run, before the destination is known.
        let recentFinals = snapshot.useAppContext ? prefetchRecentFinals(appBundleId: nil) : nil
        var speechLanguage: String?
        do {
            try await accessCheck()
            guard isCurrent(token) else { return }
            if let reason = profile.speechModel?.unavailableReason {
                throw RecordingPrerequisiteError(reason, kind: .modelMissing)
            }
            if let id = request.profileID, !profiles.profiles.contains(where: { $0.id == id }) {
                throw RecordingPrerequisiteError(String(localized: "This shortcut's profile was deleted. Choose another profile in Settings > Keyboard shortcuts.", bundle: .module), kind: .setup)
            }
            if insertionEnabled, output.target == .script, let reason = ScriptDelivery.unavailableReason(path: output.scriptPath) {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start.", bundle: .module) + " " + reason)
            }
            if insertionEnabled, case .file(let path) = output.target,
               let reason = FileAppendDelivery.unavailableReason(template: path) {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start.", bundle: .module) + " " + reason, kind: .setup)
            }
            if request.intent == .editSelection, llm.kind == .none {
                throw RecordingPrerequisiteError(String(localized: "The Edit shortcut needs refinement. Choose a refinement provider in Models.", bundle: .module), kind: .setup)
            }
            let language = try SpeechLanguagePolicy.resolve(asr)
            speechLanguage = language.language
            if let recordingPreflight {
                try await recordingPreflight(asr, llm, profile.usesLLM, microphone, needsInsertion)
            } else {
                try RecordingPrerequisites.check(asr: asr, llm: llm, refinementEnabled: profile.usesLLM,
                                                 microphone: microphone, insertionEnabled: needsInsertion)
            }
            guard isCurrent(token) else { return }
            guard recordingSnapshot(app: profileApp, request: request) == snapshot else {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module), kind: .setupChanged)
            }
            if asr.kind.isLocal {
                // AD-081: a prewarm builds the decoder these captured hints need.
                SherpaTranscriber.anticipate(speechHints(for: snapshot, language: language.language))
                // Pin before checking readiness so the idle watch cannot unload
                // the model between this check and the end of processing.
                let pin = await factory.pinForSession(asr.engineID, recordingSeconds: allowedSeconds)
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
            guard recordingSnapshot(app: profileApp, request: request) == snapshot else {
                throw RecordingPrerequisiteError(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module), kind: .setupChanged)
            }
        } catch {
            guard isCurrent(token) else { return }
            reportFailure(Self.failureCategory(for: error))
            fail(error.localizedDescription)
            onRecordingBlocked?()
            return
        }
        // The Edit shortcut reads the selection once, before the microphone
        // opens: with nothing selected there is nothing to edit.
        var editContext: AppContext?
        if request.intent == .editSelection {
            let selected = contextReader.readSelection()
            guard selected.hasSelection, let text = selected.selectedText else {
                fail(String(localized: "Select the text to edit, then hold the Edit shortcut and say what to change.", bundle: .module))
                return
            }
            editContext = selected
            recordingBadge = Self.editBadge(characters: text.count)
        }
        let granted = await requestMicrophoneAccess()
        guard isCurrent(token) else { return }
        guard granted else {
            reportFailure(.permission)
            fail(String(localized: "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        guard recordingSnapshot(app: profileApp, request: request) == snapshot else {
            fail(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        // Every prerequisite has passed, so capture starts now and buffers the
        // speech that follows the press. The destination and app context are
        // captured while audio is recorded; any exit before the recording state
        // stops the microphone again and discards that audio.
        wireRecorder(for: token)
        startPreview(for: token, request: ModelPreviewRequest(asr: asr, hints: speechHints(for: snapshot, language: speechLanguage)),
                     profile: profile.id)
        do {
            try recorder.start(microphone: microphone)
        } catch {
            stopPreview()
            reportFailure(.recordingFailed)
            fail(String(localized: "Could not start recording: \(error.localizedDescription)", bundle: .module))
            onRecordingBlocked?()
            return
        }
        let captureStarted = ProcessInfo.processInfo.systemUptime
        let captureStartedAt = Date()
        startingCapture = token
        startingCaptureStartedAt = captureStarted
        captureLatency?.engineID = asr.engineID
        // Practice's own editor is inside Airdraft, which is never a paste target.
        let practice = needsInsertion && settings.isOnboardingPractice && practiceTarget?.acceptsDictation == true
        let insertionTarget = needsInsertion && !practice ? await inserter.captureTarget() : nil
        // A cancelled or replaced session already stopped this capture.
        guard isCurrent(token) else { return }
        var context = snapshot.useAppContext ? contextReader.read() : (editContext ?? .empty)
        if let editContext, !context.hasSelection { context.selectedText = editContext.selectedText }
        if let recentFinals, context.recentDictations.isEmpty {
            context.recentDictations = await recentFinals.finals(for: context.bundleId)
            guard isCurrent(token) else { return }
        }
        if request.profileID == nil, request.intent == .dictate,
           let followed = followCapturedApp(insertionTarget?.bundleID, from: profileApp, snapshot: snapshot) {
            profileApp = followed.profileApp
            snapshot = followed
        }
        guard recordingSnapshot(app: profileApp, request: request) == snapshot else {
            abandonStartingCapture()
            fail(String(localized: "Recording did not start because setup changed. Try your shortcut again.", bundle: .module))
            onRecordingBlocked?()
            return
        }
        startingCapture = nil
        recordingAtStart = snapshot
        insertionTargetAtStart = insertionTarget
        practiceDeliveryAtStart = practice
        contextAtStart = context
        // The timer and the limit count from the start of capture, so buffered
        // audio never takes a recording past its effective limit.
        recordingStartedAt = captureStartedAt
        stopRequestedAt = nil
        levelHistory = []
        set(.recording)
        startShiftMonitor(token: token, snapshot: snapshot)
        startRefinementPreparation(context: contextAtStart, snapshot: snapshot, token: token)

        let remaining = max(0, allowedSeconds - (ProcessInfo.processInfo.systemUptime - captureStarted))
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard let self, self.isCurrent(token) else { return }
            if budgetLimited { self.keptBudgetStop = (token, allowedSeconds) }
            self.finishRecording()
        }
        if let pending = pendingStartupStop, pending.token == token {
            pendingStartupStop = nil
            finishReleasedStartup(releasedAt: pending.releasedAt, captureStarted: captureStarted, token: token)
        }
    }

    /// The hold was released while the destination was still being captured.
    /// Keep the release grace, then process only the audio up to it.
    private func finishReleasedStartup(releasedAt: TimeInterval, captureStarted: TimeInterval, token: UUID) {
        stopRequestedAt = releasedAt
        stopping = true
        let end = releasedAt + Self.releaseGraceSeconds
        releaseTask = Task { @MainActor in
            let wait = end - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard self.isCurrent(token) else { return }
            self.stopping = false
            self.finishRecording(keepingSeconds: end - captureStarted)
        }
    }

    /// An app switch in flight at the press can leave the captured destination
    /// different from the app that chose the profile. Follow the destination's
    /// rule when it needs no setup that was not checked: the same speech model and
    /// no newly required refinement. Otherwise the checked profile stays.
    func followCapturedApp(_ captured: String?, from app: String?, snapshot: RecordingSnapshot) -> RecordingSnapshot? {
        guard let captured, captured != app, recordingSnapshot(app: app, request: snapshot.request) == snapshot else { return nil }
        let followed = recordingSnapshot(app: captured, request: snapshot.request)
        guard followed.asr == snapshot.asr, followed.profile.speechModel?.unavailableReason == nil,
              !followed.profile.usesLLM || snapshot.profile.usesLLM else { return nil }
        return followed
    }

    /// Stops capture that began before the recording state, discarding its audio.
    func abandonStartingCapture() {
        guard startingCapture != nil else { return }
        startingCapture = nil
        startingCaptureStartedAt = nil
        pendingStartupStop = nil
        stopPreview()
        if recorder.isRecording { recorder.cancel() }
    }

    /// Keep capturing briefly after the key is released: people let go while
    /// the last syllable is still sounding.
    public static let releaseGraceSeconds: Double = 0.35
    /// Shorter recordings are discarded as accidental presses.
    public static let minimumRecordingSeconds: Double = 0.3

    public func stopAndProcess() {
        if recordingRequest != nil && !isRecording {
            // Released while the microphone was already open but the destination
            // was still being captured (an Electron editor can take 1.5 s). Speech
            // already held is processed once the destination resolves; a release
            // before capture began, or a tap, cancels as before.
            if startingCapture == generation, pendingStartupStop?.token != generation, let started = startingCaptureStartedAt,
               ProcessInfo.processInfo.systemUptime - started >= Self.minimumRecordingSeconds {
                pendingStartupStop = (generation, ProcessInfo.processInfo.systemUptime)
                return
            }
            cancel()
            return
        }
        guard state == .recording, !stopping else { return }
        stopRequestedAt = ProcessInfo.processInfo.systemUptime
        stopping = true
        quiesceEnginePreview()
        let token = generation
        releaseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.releaseGraceSeconds))
            guard self.isCurrent(token) else { return }
            self.stopping = false
            self.finishRecording()
        }
    }

    /// `keepingSeconds` drops audio captured after a release that arrived
    /// before the recording state began.
    func finishRecording(keepingSeconds: Double? = nil) {
        guard state == .recording, let snapshot = recordingAtStart else { return }
        if stopRequestedAt == nil { stopRequestedAt = ProcessInfo.processInfo.systemUptime }
        autoStopTask?.cancel()
        releaseTask?.cancel()
        stopping = false
        let live = takeLiveTranscript()
        stopPreview()
        stopShiftMonitor()
        sessionSendLock = (generation, sendLocked)
        recordingBadge = nil
        var samples = recorder.stop()
        if let keepingSeconds {
            let kept = max(0, Int(keepingSeconds * AudioRecorder.sampleRate))
            if samples.count > kept { samples.removeLast(samples.count - kept) }
        }
        recordingAtStart = nil
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        lastRecordingDuration = seconds
        recordingStartedAt = nil

        guard seconds >= Self.minimumRecordingSeconds else {
            live?.cancel()
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
        processingTask = Task { await process(samples: samples, seconds: seconds, context: ctx, target: target, token: token, snapshot: snapshot, delivery: delivery, live: live) }
    }

    public func cancel() {
        // Once a write begins, finish recording its outcome before accepting a new session.
        guard !deliveryCommitted else { return }
        deliveryAwaitingClipboard = false
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
        startingCapture = nil
        startingCaptureStartedAt = nil
        pendingStartupStop = nil
        if recorder.isRecording { recorder.cancel() }
        recordingStartedAt = nil
        recordingAtStart = nil
        stopShiftMonitor()
        sendLocked = false
        sessionSendLock = nil
        recordingBadge = nil
        sendCancelled = true
        holdsRecordingWindow = false
        set(.idle)
    }

    // MARK: - Recorder callbacks and live preview

    func wireRecorder(for token: UUID) {
        let firstBuffer = FirstBufferClock()
        recorder.levelHandler = { [weak self] level in
            // Stamped on the audio thread, before the hop to the main actor.
            let first = firstBuffer.markFirst()
            Task { @MainActor in
                guard let self, self.isCurrent(token) else { return }
                if let first { self.noteFirstBuffer(at: first, token: token) }
                guard self.isRecording else { return }
                self.levelHistory.append(level)
                if self.levelHistory.count > Self.levelHistoryLength {
                    self.levelHistory.removeFirst(self.levelHistory.count - Self.levelHistoryLength)
                }
            }
        }
        recorder.interruptionHandler = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.isCurrent(token) else { return }
                if self.startingCapture == token {
                    // The input failed while the destination was being captured.
                    // Less than the capture deadline was recorded; nothing is kept.
                    self.cancel()
                    self.reportFailure(.recordingFailed)
                    self.fail(String(localized: "Could not start recording: \(reason.localizedDescription)", bundle: .module))
                    self.onRecordingBlocked?()
                    return
                }
                guard self.isRecording else { return }
                let samples = self.recorder.stop()
                let context = self.contextAtStart
                let target = self.insertionTargetAtStart
                let output = self.recordingAtStart?.output
                let profileApp = self.recordingAtStart?.profileApp
                let request = self.recordingAtStart?.request ?? RecordingRequest()
                self.cancel()
                let message = reason.localizedDescription + (samples.isEmpty ? "" : " " + String(localized: "Captured audio is kept for retry.", bundle: .module))
                if !samples.isEmpty { self.retain(samples, context: context, target: target, output: output, profileApp: profileApp, request: request, issue: message) }
                self.reportFailure(.recordingFailed)
                self.fail(message, openRecovery: !samples.isEmpty)
            }
        }
    }

    /// `request` carries the speech config and hints final transcription uses,
    /// so model preview decodes with the same loaded recognizer (AD-084).
    func startPreview(for token: UUID, request: ModelPreviewRequest, profile: UUID? = nil) {
        stopPreview()
        guard settings.livePreviewEnabled, settings.hudStyle != .none else { return }
        previewEnabledForRecording = true
        let previewID = UUID()
        previewGeneration = previewID
        // Each callback belongs to this session: a stale, quiesced or cancelled
        // session's late text or issue is rejected here, after its own gate.
        let onText: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.previewGeneration == previewID,
                      self.isRecording, self.previewEnabledForRecording else { return }
                self.previewText = String(text.suffix(500))
            }
        }
        let onIssue: @Sendable (String) -> Void = { [weak self] issue in
            Task { @MainActor in
                guard let self, self.isCurrent(token), self.previewGeneration == previewID,
                      self.isRecording, self.previewEnabledForRecording else { return }
                self.previewText = ""
                self.previewIssue = issue
            }
        }
        let session: any SpeechPreviewSession
        switch settings.livePreviewSource {
        case .appleSpeech:
            session = previewBuilder(settings.livePreviewLocale, onText, onIssue)
        case .speechModel:
            if let locale = ModelSpeechPreview.appleSpeechLocale(for: request.asr) {
                // Apple Speech previews through its own analyzer, outside the factory lease.
                previewNoticeShownFor = nil
                session = previewBuilder(locale, onText, onIssue)
                break
            }
            // An unsupported model opens no live-text window: the HUD shows the
            // reason as a brief notice while recording continues.
            if let reason = modelPreviewAvailability(request.asr) {
                previewEnabledForRecording = false
                // Said once: later recordings with the same model and profile stay quiet.
                let key = "\(profile?.uuidString ?? "")|\(request.asr.engineID)"
                if previewNoticeShownFor != key {
                    previewNoticeShownFor = key
                    previewIssue = reason
                }
                return
            }
            previewNoticeShownFor = nil
            session = modelPreviewBuilder(request, onText, onIssue)
            previewUsesSpeechEngine = true
        }
        previewSession = session
        previewBecomesTranscript = (session as? any LiveTranscriptSession)?.reusesForTranscript == true
        recorder.samplesHandler = { samples in session.append(samples) }
    }

    /// AD-123: detaches the session whose live text becomes the transcript, so
    /// stopping preview does not cancel it; processing finishes or cancels it.
    func takeLiveTranscript() -> (any LiveTranscriptSession)? {
        guard previewBecomesTranscript, let live = previewSession as? any LiveTranscriptSession else { return nil }
        recorder.samplesHandler = nil
        previewSession = nil
        previewBecomesTranscript = false
        return live
    }

    /// Apply an explicit Off choice immediately without interrupting final capture.
    public func disableLivePreview() { stopPreview() }

    /// At release, stop model preview decodes so one already in flight finishes
    /// during the release grace instead of delaying final inference. The last
    /// text stays visible until the recording state ends.
    func quiesceEnginePreview() {
        // Live text that becomes the transcript keeps decoding through the grace (AD-123).
        guard previewUsesSpeechEngine, !previewBecomesTranscript else { return }
        previewGeneration = UUID()
        previewSession?.cancel()
        previewSession = nil
    }

    func stopPreview() {
        recorder.samplesHandler = nil
        previewGeneration = UUID()
        previewSession?.cancel()
        previewSession = nil
        previewUsesSpeechEngine = false
        previewBecomesTranscript = false
        previewText = ""
        previewIssue = nil
        previewEnabledForRecording = false
    }

    // MARK: - Press-to-capture timing

    /// Records how long the session took from shortcut acceptance to its first
    /// captured audio buffer. Durations and engine identifiers only.
    func noteFirstBuffer(at uptime: TimeInterval, token: UUID) {
        guard var latency = captureLatency, latency.token == token, latency.pressToCaptureMs == nil else { return }
        latency.pressToCaptureMs = Int(max(0, uptime - latency.acceptedAt) * 1000)
        captureLatency = latency
        if let ms = latency.pressToCaptureMs { noteCaptureMetric(ms: ms, microphone: settings.microphone) }
        let engine = latency.engineID ?? "unknown"
        Self.log.notice("recording timing pressToCaptureMs=\(latency.pressToCaptureMs ?? -1) asrEngine=\(engine, privacy: .public)")
    }

    /// The session's press-to-capture duration, once its first buffer arrived.
    func pressToCaptureMs(for token: UUID) -> Int? {
        captureLatency?.token == token ? captureLatency?.pressToCaptureMs : nil
    }
}

/// The first audio buffer's arrival time, stamped once on the audio thread.
final class FirstBufferClock: Sendable {
    private let stamped = Mutex(false)

    /// The current uptime for the first call only; nil afterwards.
    func markFirst() -> TimeInterval? {
        let now = ProcessInfo.processInfo.systemUptime
        return stamped.withLock { stamped in
            guard !stamped else { return nil }
            stamped = true
            return now
        }
    }
}
