#if DEBUG
import Foundation
import AirdraftCore

@MainActor
enum MeetingVerification {
    static func installSilentCapture(in app: AppContainer) {
        guard LocalE2E.isActive else { return }
        app.meeting?.captureFactory = { directory, microphone, _, _ in try SyntheticMeetingCapture(directory: directory, microphone: microphone) }
        let count = LocalE2E.argument("--e2e-meeting-apps").flatMap(Int.init)
        let delay = min(30_000, max(0, LocalE2E.argument("--e2e-meeting-app-delay-ms").flatMap(Int.init) ?? 600))
        app.meeting?.sourceProvider = {
            if let count {
                try await Task.sleep(for: .milliseconds(delay))
                return (0..<min(100, max(0, count))).map { .init(id: Int32(101 + $0), name: String(format: "Fixture App %02d", $0 + 1)) }
            }
            return [.init(id: 101, name: "Fixture Call"), .init(id: 102, name: "Fixture Browser")]
        }
    }
    /// Exercises the actual app coordinator without capture permissions, microphones or playback.
    static func run() async -> Bool {
        guard LocalE2E.isActive else { return false }
        let name = "airdraft.meeting-verification.\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        do {
            let app = AppContainer(settings: AppSettings(defaults: defaults), dataDirectory: directory)
            guard let meeting = app.meeting, let history = app.history else { return false }
            meeting.captureFactory = { directory, microphone, _, _ in try SyntheticMeetingCapture(directory: directory, microphone: microphone) }
            meeting.start(applicationID: nil, microphoneID: nil, microphone: true)
            guard app.pipeline.isBusy else { return false }
            let deadline = Date().addingTimeInterval(5)
            while meeting.state == .starting && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            guard meeting.state == .recording, app.pipeline.isCapturingMeeting else { return false }
            await meeting.stop()
            guard !app.pipeline.isBusy, let saved = meeting.saved, saved.duration == 2,
                  history.audioURL(for: saved) != nil, try history.stats().dictations == 0 else { return false }
            let selectedOlder = MediaImportRequest.recording(saved)
            print("MEETING_FIXTURE_PASS capture-stop-save-no-insertion")
            meeting.start(applicationID: nil, microphoneID: nil, microphone: true)
            meeting.cancelStart()
            while meeting.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            guard !app.pipeline.isBusy, try MeetingAudioStore.drafts(in: directory).isEmpty else { return false }
            print("MEETING_FIXTURE_PASS cancel-start-no-orphan")
            meeting.start(applicationID: nil, microphoneID: nil, microphone: true)
            while meeting.state == .starting && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            await meeting.prepareForQuit()
            guard !app.pipeline.isBusy, meeting.saved?.captureIssue?.contains("quit") == true else { return false }
            print("MEETING_FIXTURE_PASS quit-flush-save")
            // Recreate the coordinator while durable records and an interrupted session coexist.
            do {
                let writer = try MeetingAudioWriter(directory: directory, microphone: true)
                try writer.append([Float](repeating: 0, count: 16_000), track: .system, at: 0)
            }
            let restored = MeetingController(directory: directory, history: history, canStart: { true }, accessCheck: {})
            guard restored.saved == nil, restored.drafts.count == 1, try history.meetings().count == 2,
                  case .recording(let chosen) = selectedOlder.source, chosen.id == saved.id else { return false }
            restored.recover(restored.drafts[0])
            let recoveryDeadline = Date().addingTimeInterval(5)
            while restored.isBusy && Date() < recoveryDeadline { try await Task.sleep(for: .milliseconds(10)) }
            guard try history.meetings().count == 3, restored.drafts.isEmpty else { return false }
            for entry in try history.meetings() {
                guard let asset = entry.asset else { return false }
                let request = MediaImportRequest.recording(asset)
                guard case .recording(let payload) = request.source, payload.id == asset.id else { return false }
            }
            print("MEETING_FIXTURE_PASS restart-library-three-recordings-immutable-payload-recovery")
            let selection = MeetingSourceSelection()
            let available = MeetingAudioSource(id: 123, name: "Fixture Call")
            selection.provider = { [available] }
            await selection.load()
            selection.select(available)
            guard selection.selectedID == 123, !selection.unavailable, !selection.loading else { return false }
            selection.provider = { [] }
            await selection.load()
            guard selection.unavailable, selection.selectedID == 123, selection.selectedName == "Fixture Call" else { return false }
            selection.provider = { throw MeetingError.permission }
            await selection.load()
            guard selection.issue != nil, !selection.loading else { return false }
            selection.select(nil)
            guard !selection.unavailable, selection.selectedName == "All Apps" else { return false }
            selection.provider = { [available] }
            await selection.load()
            guard selection.issue == nil, selection.sources.count == 1 else { return false }
            print("MEETING_FIXTURE_PASS source-choice-empty-denied-exited-refresh")
            // A separate crashed writer remains audio during text-only cleanup, then is removed by audio cleanup.
            do {
                let writer = try MeetingAudioWriter(directory: directory, microphone: true)
                try writer.append([Float](repeating: 0, count: 16_000), track: .system, at: 0)
            }
            await app.performCleanup(.history)
            guard try MeetingAudioStore.drafts(in: directory).count == 1, try history.recordings().entries.count == 3 else { return false }
            await app.performCleanup(.audio)
            guard try MeetingAudioStore.drafts(in: directory).isEmpty, try history.recordings().entries.isEmpty else { return false }
            print("MEETING_FIXTURE_PASS cleanup-scopes")
            guard try await verifyLiveTranscript(meeting: meeting, app: app) else { return false }
            print("MEETING_FIXTURE_PASS live-transcript-display-only")
            return true
        } catch { print("MEETING_FIXTURE_ERROR \(error.localizedDescription)"); return false }
    }

    /// AD-084: injected two-track PCM reaches the live transcript through the
    /// production controller and mixer; the text is never saved and stops with capture.
    private static func verifyLiveTranscript(meeting: MeetingController, app: AppContainer) async throws -> Bool {
        let holder = LiveFeedHolder()
        meeting.captureFactory = { directory, microphone, _, _ in
            let capture = try LiveFeedMeetingCapture(directory: directory, microphone: microphone)
            holder.capture = capture
            return capture
        }
        meeting.livePreviewStarter = { onText, onIssue in
            ModelSpeechPreview.start(policy: ModelPreviewPolicy(minimumInterval: 0.2, minimumNewAudioSeconds: 0.2),
                decode: { samples in holder.decoded(samples.count); return "Fixture live text \(samples.count)" },
                onText: onText, onIssue: onIssue)
        }
        defer {
            meeting.livePreviewStarter = nil
            meeting.captureFactory = { directory, microphone, _, _ in try SyntheticMeetingCapture(directory: directory, microphone: microphone) }
        }
        let before = try app.history?.stats().dictations ?? 0
        meeting.start(applicationID: nil, microphoneID: nil, microphone: true)
        let deadline = Date().addingTimeInterval(10)
        while (meeting.state != .recording || holder.capture?.hasPreviewHandler != true) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard meeting.liveTranscriptActive, let capture = holder.capture, capture.hasPreviewHandler else { return false }
        await capture.feed(seconds: 2)
        while !meeting.liveText.hasPrefix("Fixture live text") && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        guard meeting.liveText.hasPrefix("Fixture live text"), meeting.liveIssue == nil,
              holder.maximumWindow > 0, holder.maximumWindow <= 160_000 else { return false }
        await meeting.stop()
        guard !meeting.liveTranscriptActive, meeting.liveText.isEmpty, !capture.hasPreviewHandler,
              let saved = meeting.saved, saved.duration == 2,
              try app.history?.stats().dictations ?? 0 == before else { return false }
        // Audio after stop never reaches the stopped session.
        let decodes = holder.decodes
        await capture.feed(seconds: 1)
        try await Task.sleep(for: .milliseconds(400))
        print("MEETING_LIVE_TRANSCRIPT decodes=\(decodes) maxWindowSamples=\(holder.maximumWindow)")
        return holder.decodes == decodes
    }
}

private final class LiveFeedHolder: @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private var stored: LiveFeedMeetingCapture?
    private var windows: [Int] = []
    var capture: LiveFeedMeetingCapture? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    func decoded(_ count: Int) { lock.withLock { windows.append(count) } }
    var decodes: Int { lock.withLock { windows.count } }
    var maximumWindow: Int { lock.withLock { windows.max() ?? 0 } }
}

/// Like SyntheticMeetingCapture, plus explicit PCM for the live-transcript hook.
/// Unchecked: `handler` is guarded by `lock`; the writer is used only by sequential start/stop.
private final class LiveFeedMeetingCapture: MeetingCapturing, @unchecked Sendable {
    let id: String
    private let writer: MeetingAudioWriter
    private let lock = NSLock()
    private var handler: (@Sendable (MeetingTrack, [Float], Double) -> Void)?
    private var fed = 0.0
    init(directory: URL, microphone: Bool) throws {
        writer = try MeetingAudioWriter(directory: directory, microphone: microphone); id = writer.id
    }
    var previewAudioHandler: (@Sendable (MeetingTrack, [Float], Double) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }
    var hasPreviewHandler: Bool { previewAudioHandler != nil }
    func start(applicationID: Int32?, microphoneID: String?, includeMicrophone: Bool, microphoneChannel: Int?) async throws {
        try Task.checkCancellation()
        try writer.append([Float](repeating: 0.2, count: 32_000), track: .system, at: 0)
        if includeMicrophone { try writer.append([Float](repeating: 0.1, count: 32_000), track: .microphone, at: 0) }
    }
    /// Interleaved 20 ms chunks for both tracks, as the capture queue delivers them.
    func feed(seconds: Double) async {
        for _ in 0..<Int(seconds * 50) {
            let offset = fed
            previewAudioHandler?(.microphone, [Float](repeating: 0.1, count: 320), offset)
            previewAudioHandler?(.system, [Float](repeating: 0.2, count: 320), offset)
            fed += 0.02
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
    func stop(reason: String?) async throws -> MeetingDraft { try writer.finish(reason: reason) }
}

private actor SyntheticMeetingCapture: MeetingCapturing {
    nonisolated let id: String
    private let writer: MeetingAudioWriter
    init(directory: URL, microphone: Bool) throws {
        writer = try MeetingAudioWriter(directory: directory, microphone: microphone); id = writer.id
    }
    func start(applicationID: Int32?, microphoneID: String?, includeMicrophone: Bool, microphoneChannel: Int?) async throws {
        try Task.checkCancellation()
        try writer.append([Float](repeating: 0.2, count: 32_000), track: .system, at: 0)
        if includeMicrophone { try writer.append([Float](repeating: 0.1, count: 32_000), track: .microphone, at: 0) }
    }
    func stop(reason: String?) async throws -> MeetingDraft { try writer.finish(reason: reason) }
}
#endif
