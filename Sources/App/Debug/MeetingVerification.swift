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
            return true
        } catch { print("MEETING_FIXTURE_ERROR \(error.localizedDescription)"); return false }
    }
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
