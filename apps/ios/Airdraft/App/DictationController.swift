import AirdraftCore
import Foundation
import Observation
import os
import UIKit

/// Runs dictation for the app and for the Airdraft keyboard.
///
/// A keyboard has no microphone, so the keyboard asks the app over
/// `KeyboardBridge`. iOS lets a background app record only from an input that
/// is already running, so the keyboard works during a *session*: the app keeps
/// its input in standby for a few minutes, shows a Live Activity, and starts
/// recording at once when the keyboard asks. The finished text goes back to
/// the keyboard that asked; if it does not confirm within a few seconds, the
/// text is copied instead, and History records which happened.
@MainActor
@Observable
final class DictationController {
    enum Origin: Equatable {
        case app
        case keyboard(request: UUID)
    }

    private(set) var sessionEndsAt: Date?
    private(set) var origin: Origin?
    /// A short confirmation or problem for the Home screen.
    private(set) var notice: String?
    private(set) var lastResult: MobileDictationResult?

    var isSessionActive: Bool { sessionEndsAt != nil }
    /// Set by the container: a long Transcribe recording holds the microphone.
    @ObservationIgnored var otherCaptureActive: () -> Bool = { false }

    @ObservationIgnored private let dictation: MobileDictation
    @ObservationIgnored private let recorder: AudioRecorder
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let mobile: MobileSettings
    @ObservationIgnored private let factory: EngineFactory
    @ObservationIgnored private let store = KeyboardBridge.Store()
    @ObservationIgnored private let listener = DarwinSignalListener()
    @ObservationIgnored private let activity = LiveActivityController()
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var receiptWaiter: (id: UUID, continuation: CheckedContinuation<KeyboardBridge.Receipt?, Never>)?

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "dictation-controller")
    /// How long the keyboard has to confirm an insertion before the text is copied instead.
    static let receiptTimeout: Duration = .seconds(6)

    init(dictation: MobileDictation, recorder: AudioRecorder, settings: AppSettings,
         mobile: MobileSettings, factory: EngineFactory) {
        self.dictation = dictation
        self.recorder = recorder
        self.settings = settings
        self.mobile = mobile
        self.factory = factory
        dictation.onAutomaticStop = { [weak self] in
            Task { await self?.stop() }
        }
        recorder.interruptionHandler = { [weak self] _ in
            Task { @MainActor in self?.interrupted() }
        }
        listener.observe(.start) { [weak self] in self?.keyboardAskedToStart() }
        listener.observe(.stop) { [weak self] in Task { await self?.stop() } }
        listener.observe(.cancel) { [weak self] in self?.cancel() }
        listener.observe(.consumed) { [weak self] in self?.keyboardConsumed() }
        // A new process has no input open: any session from before is over.
        store?.delivery = nil
        publish()
    }

    // MARK: - Recording

    var isRecording: Bool { dictation.phase == .recording }

    func toggleRecording() {
        if isRecording {
            Task { await stop() }
        } else if dictation.phase == .idle {
            start(origin: .app)
        }
    }

    func start(origin: Origin) {
        notice = nil
        guard !otherCaptureActive() else {
            notice = String(localized: "Finish the Transcribe recording first.")
            publish(message: notice)
            return
        }
        do {
            try dictation.start()
            self.origin = origin
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if isSessionActive { extendSession() }
            publish()
        } catch {
            notice = error.localizedDescription
            publish(message: error.localizedDescription)
        }
    }

    func stop() async {
        guard dictation.phase == .recording, let origin else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        publishSoon()
        let result = await dictation.stop()
        self.origin = nil
        guard let result else {
            notice = dictation.lastError
            publish(message: dictation.lastError)
            return
        }
        lastResult = result
        await deliver(result, origin: origin)
        if isSessionActive { extendSession() }
    }

    func cancel() {
        dictation.cancel()
        origin = nil
        publish()
    }

    private func interrupted() {
        guard dictation.phase == .recording else {
            if isSessionActive { endSession() }
            return
        }
        // A call or Siri took the input; process what was captured.
        Task { await stop() }
        sessionEndsAt = nil
        sessionTask?.cancel()
    }

    // MARK: - Keyboard session

    /// Opens the input in standby so the Airdraft keyboard can record from any app.
    func startSession() {
        notice = nil
        guard !otherCaptureActive() else {
            notice = String(localized: "Finish the Transcribe recording first.")
            return
        }
        if let issue = dictation.readinessIssue() {
            notice = issue
            publish(message: issue)
            return
        }
        do {
            try recorder.startStandby()
        } catch {
            notice = error.localizedDescription
            publish(message: error.localizedDescription)
            return
        }
        extendSession()
        let speech = dictation.currentSnapshot().asr
        if speech.kind.isLocal {
            // Load the model while the user switches apps, not after they speak.
            let factory = self.factory
            Task.detached(priority: .utility) { try? await factory.prepare(speech) }
        }
        Self.log.notice("keyboard session started minutes=\(self.mobile.sessionMinutes)")
    }

    func endSession() {
        sessionTask?.cancel()
        sessionTask = nil
        sessionEndsAt = nil
        if dictation.phase == .recording { dictation.cancel(); origin = nil }
        recorder.endStandby()
        publish()
        Self.log.notice("keyboard session ended")
    }

    private func extendSession() {
        let ends = Date().addingTimeInterval(TimeInterval(mobile.sessionMinutes * 60))
        sessionEndsAt = ends
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            try? await Task.sleep(until: .now + .seconds(ends.timeIntervalSinceNow), clock: .continuous)
            guard !Task.isCancelled, let self, self.sessionEndsAt == ends else { return }
            if self.dictation.phase == .idle { self.endSession() } else { self.extendSession() }
        }
        publish()
    }

    private func keyboardAskedToStart() {
        guard let request = store?.request else { return }
        guard isSessionActive, recorder.isInputRunning else {
            publish(message: String(localized: "Start a keyboard session in Airdraft first."))
            return
        }
        guard dictation.phase == .idle else { return }
        start(origin: .keyboard(request: request.id))
    }

    // MARK: - Delivery

    private func deliver(_ result: MobileDictationResult, origin: Origin) async {
        let refinementNotice = result.refinementError.map { _ in
            result.refinementRejected
                ? String(localized: "Refinement didn't match your speech; the original text was used.")
                : String(localized: "Refinement unavailable; the original text was used.")
        }
        switch origin {
        case .app:
            if mobile.copiesResult {
                UIPasteboard.general.string = result.final
                dictation.record(result, delivery: .copied)
                notice = refinementNotice ?? String(localized: "Copied")
            } else {
                dictation.record(result, delivery: .shown)
                notice = refinementNotice
            }
            publish()
        case .keyboard(let request):
            guard let store else {
                UIPasteboard.general.string = result.final
                dictation.record(result, delivery: .copied)
                return
            }
            let delivery = KeyboardBridge.Delivery(id: result.id, requestID: request, text: result.final, createdAt: Date())
            store.receipt = nil
            store.delivery = delivery
            publish(message: refinementNotice)
            let receipt = await waitForReceipt(delivery.id)
            store.delivery = nil
            if let receipt {
                dictation.record(result, delivery: .keyboard(confirmed: receipt.confirmed))
                publish(message: refinementNotice)
            } else {
                UIPasteboard.general.string = result.final
                dictation.record(result, delivery: .copied)
                publish(message: String(localized: "Dictation copied"))
            }
        }
    }

    private func waitForReceipt(_ id: UUID) async -> KeyboardBridge.Receipt? {
        if let receipt = store?.receipt, receipt.id == id { return receipt }
        return await withCheckedContinuation { continuation in
            receiptWaiter = (id, continuation)
            Task { [weak self] in
                try? await Task.sleep(for: Self.receiptTimeout)
                self?.resolveReceipt(id: id, receipt: nil)
            }
        }
    }

    private func keyboardConsumed() {
        guard let receipt = store?.receipt else { return }
        resolveReceipt(id: receipt.id, receipt: receipt)
    }

    private func resolveReceipt(id: UUID, receipt: KeyboardBridge.Receipt?) {
        guard let waiter = receiptWaiter, waiter.id == id else { return }
        receiptWaiter = nil
        waiter.continuation.resume(returning: receipt)
    }

    // MARK: - State

    /// Shares the state with the keyboard and the Live Activity.
    private func publish(message: String? = nil) {
        let phase: KeyboardBridge.State.Phase
        switch dictation.phase {
        case .recording: phase = .recording
        case .transcribing, .refining: phase = .processing
        case .idle: phase = isSessionActive && recorder.isInputRunning ? .ready : .off
        }
        let state = KeyboardBridge.State(phase: phase, endsAt: sessionEndsAt,
                                         recordingStartedAt: dictation.recordingStartedAt,
                                         message: message, updatedAt: Date())
        store?.state = state
        KeyboardBridge.post(.state)
        activity.show(state)
    }

    /// Processing starts inside `stop()`; publish once the phase has moved.
    private func publishSoon() {
        Task { [weak self] in
            await Task.yield()
            self?.publish()
        }
    }

    #if DEBUG
    /// Sample result for simulator screenshots (`DebugLaunch`).
    func debugShow(_ result: MobileDictationResult) {
        lastResult = result
    }
    #endif

    /// Called when the app returns to the foreground.
    func refresh() {
        if let ends = sessionEndsAt, ends <= Date(), dictation.phase == .idle { endSession() } else { publish() }
    }
}
