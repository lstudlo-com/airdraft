import AirdraftCore
import Foundation
import Observation

@MainActor @Observable
final class MeetingSourceSelection {
    var selectedID: Int32?
    private(set) var selectedName = "All Apps"
    private(set) var sources: [MeetingAudioSource] = []
    private(set) var loading = false
    private(set) var issue: String?
    private(set) var loaded = false
    @ObservationIgnored var provider: @Sendable () async throws -> [MeetingAudioSource] = { try await MeetingCaptureSession.sources() }
    @ObservationIgnored private var generation = UUID()
    var unavailable: Bool { loaded && selectedID != nil && !sources.contains { $0.id == selectedID } }

    func select(_ source: MeetingAudioSource?) {
        selectedID = source?.id
        selectedName = source?.name ?? "All Apps"
    }
    func load() async {
        let token = UUID(); generation = token
        loading = true; issue = nil
        defer { if generation == token { loading = false } }
        do {
            let found = try await provider()
            try Task.checkCancellation()
            guard generation == token else { return }
            sources = found; loaded = true
        } catch {
            guard generation == token, !(error is CancellationError) else { return }
            issue = error.localizedDescription
        }
    }
}
