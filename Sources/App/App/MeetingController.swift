import AppKit
import AirdraftCore
import Observation

@MainActor @Observable
final class MeetingController {
    enum State { case idle, starting, recording, finishing }
    private(set) var state = State.idle
    var isBusy: Bool { state != .idle }
    var isPresented = false
    private(set) var elapsed: Double = 0
    private(set) var microphoneLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var microphoneReceived = false
    private(set) var systemReceived = false
    private(set) var microphoneEnabled = true
    private(set) var sourceName = "All Apps"
    @ObservationIgnored private var lastStatusAt = Date()
    @ObservationIgnored private var lastAudioAt = Date()
    private(set) var saved: RecordingAsset?
    private(set) var drafts: [MeetingDraft] = []
    var issue: String?
    private(set) var recoveryIssue: String?
    var onBusyChanged: ((Bool) -> Void)?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private let canStart: () -> Bool
    @ObservationIgnored private let accessCheck: () async throws -> Void
    @ObservationIgnored private var session: (any MeetingCapturing)?
    typealias CaptureFactory = (URL, Bool, @escaping @Sendable (MeetingCaptureStatus) -> Void, @escaping @Sendable (String) -> Void) throws -> any MeetingCapturing
    @ObservationIgnored var captureFactory: CaptureFactory = { try MeetingCaptureSession(directory: $0, microphone: $1, onStatus: $2, onFailure: $3) }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var sleepObserver: NSObjectProtocol?
    init(directory: URL, history: HistoryStore, canStart: @escaping () -> Bool, accessCheck: @escaping () async throws -> Void) {
        self.directory = directory; self.history = history; self.canStart = canStart; self.accessCheck = accessCheck
        refreshDrafts()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.interrupt(reason: "Recording stopped when the Mac went to sleep.") }
        }
    }
    func refreshDrafts() {
        do {
            let scan = try MeetingAudioStore.scanDrafts(in: directory)
            drafts = scan.drafts
            recoveryIssue = scan.unreadable > 0 ? "\(scan.unreadable) unfinished recording(s) could not be read. Check folder access. Other recordings can still be recovered; Remove Audio Files in Configuration clears unreadable drafts too." : nil
        } catch { recoveryIssue = error.localizedDescription }
    }
    func start(applicationID: Int32?, microphoneID: String?, microphone: Bool, microphoneChannel: Int? = nil, sourceName: String = "All Apps") {
        guard !isBusy, canStart() else { return }
        state = .starting; onBusyChanged?(true); saved = nil; issue = nil; elapsed = 0
        microphoneReceived = false; systemReceived = false; microphoneLevel = 0; systemLevel = 0
        microphoneEnabled = microphone; self.sourceName = sourceName; lastStatusAt = Date(); lastAudioAt = Date()
        generation = UUID(); let token = generation
        task = Task {
            do {
                try await accessCheck()
                let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
                // Two raw tracks, final stereo WAV and its adopted copy can coexist during finalization.
                if let free, free < 2_000_000_000 { throw MeetingError.diskSpace }
                let capture = try captureFactory(directory, microphone, { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.generation == token, self.state == .recording else { return }
                        self.lastStatusAt = Date()
                        if status.microphoneReceived || status.systemReceived { self.lastAudioAt = Date() }
                        self.microphoneLevel = status.microphoneLevel; self.systemLevel = status.systemLevel
                        self.microphoneReceived = status.microphoneReceived; self.systemReceived = status.systemReceived
                    }
                }, { [weak self] message in
                    Task { @MainActor in guard self?.generation == token else { return }; await self?.interrupt(reason: message) }
                })
                session = capture
                try Task.checkCancellation()
                try await capture.start(applicationID: applicationID, microphoneID: microphoneID, includeMicrophone: microphone, microphoneChannel: microphoneChannel)
                try Task.checkCancellation()
                state = .recording; lastAudioAt = Date(); lastStatusAt = Date()
                activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Recording meeting audio")
                let started = Date()
                timer = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        guard let self, self.state == .recording else { return }
                        self.elapsed = Date().timeIntervalSince(started)
                        if Date().timeIntervalSince(self.lastStatusAt) > 3 {
                            self.microphoneReceived = false; self.systemReceived = false
                            self.microphoneLevel = 0; self.systemLevel = 0
                        }
                        if Date().timeIntervalSince(self.lastAudioAt) >= 15 {
                            await self.stop(reason: "No audio was received for 15 seconds. Check app audio and microphone permissions."); return
                        }
                        if self.elapsed >= MediaConfiguration.maximumDuration { await self.stop(reason: "Recording stopped at the two-hour limit."); return }
                    }
                }
            } catch {
                issue = error is CancellationError ? issue ?? "Meeting start cancelled." : error.localizedDescription
                if let capture = session {
                    _ = try? await capture.stop(reason: issue)
                    try? MeetingAudioStore.discardEmpty(id: capture.id, directory: directory)
                }
                session = nil; finish(); refreshDrafts()
            }
        }
    }
    func cancelStart() { task?.cancel() }
    private func interrupt(reason: String) async {
        if state == .starting { issue = reason; task?.cancel() }
        else { await stop(reason: reason) }
    }
    func stop(reason: String? = nil) async {
        guard state == .recording, let capture = session else { return }
        state = .finishing; timer?.cancel(); timer = nil
        do {
            let draft = try await capture.stop(reason: reason)
            let directory = directory; let history = history
            saved = try await Task.detached { try MeetingAudioStore.recover(draft, directory: directory, history: history, interrupted: reason != nil) }.value
            issue = reason ?? saved?.captureIssue
        } catch {
            issue = error.localizedDescription + " Any captured audio remains available for recovery in History."
            try? MeetingAudioStore.discardEmpty(id: capture.id, directory: directory)
        }
        session = nil; finish(); refreshDrafts()
        NotificationCenter.default.post(name: .historyEntriesChanged, object: nil)
    }
    func recover(_ draft: MeetingDraft) {
        guard !isBusy, canStart() else { return }
        state = .finishing; onBusyChanged?(true); saved = nil; issue = nil
        task = Task {
            defer { finish(); refreshDrafts(); NotificationCenter.default.post(name: .historyEntriesChanged, object: nil) }
            do {
                let history = history; let directory = directory
                saved = try await Task.detached { try MeetingAudioStore.recover(draft, directory: directory, history: history, interrupted: true) }.value
                issue = saved?.captureIssue
            } catch { issue = error.localizedDescription }
        }
    }
    private func finish() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        state = .idle; onBusyChanged?(false)
    }
    func prepareForQuit() async {
        if state == .starting { task?.cancel(); await task?.value }
        if state == .recording { await stop(reason: "Recording stopped when Airdraft quit.") }
        // A save already in progress must finish before models and process teardown.
        while state == .finishing { try? await Task.sleep(for: .milliseconds(25)) }
    }
    #if DEBUG
    func previewRecording() { state = .recording; elapsed = 742; microphoneReceived = true; systemReceived = true; microphoneLevel = 0.16; systemLevel = 0.28 }
    #endif
}
