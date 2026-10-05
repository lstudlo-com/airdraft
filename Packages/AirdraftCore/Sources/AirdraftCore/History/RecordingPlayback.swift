import Foundation
import Observation

/// Inject a silent transport for verification. This controller never opens an
/// audio output device itself.
@MainActor
public protocol RecordingPlaybackTransport: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    func play() -> Bool
    func pause()
    func stop()
}

@MainActor @Observable
public final class RecordingPlayback {
    public private(set) var recordingID: String?
    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    @ObservationIgnored private var player: (any RecordingPlaybackTransport)?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private let makePlayer: (URL) throws -> any RecordingPlaybackTransport
    @ObservationIgnored private let automaticUpdates: Bool

    public init(automaticUpdates: Bool = true, makePlayer: @escaping (URL) throws -> any RecordingPlaybackTransport) {
        self.automaticUpdates = automaticUpdates
        self.makePlayer = makePlayer
    }

    public func toggle(id: String, url: URL) throws {
        if recordingID == id, let player {
            if isPlaying { player.pause(); isPlaying = false; clock?.cancel(); refresh() }
            else {
                guard player.play() else { stop(); throw CocoaError(.fileReadCorruptFile) }
                isPlaying = true
                startClock()
            }
            return
        }
        stop()
        let candidate = try makePlayer(url)
        guard candidate.duration.isFinite, candidate.duration > 0, candidate.play() else {
            candidate.stop()
            throw CocoaError(.fileReadCorruptFile)
        }
        player = candidate
        recordingID = id
        duration = candidate.duration
        isPlaying = true
        startClock()
    }

    public func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, let player else { return }
        let target = min(duration, max(0, seconds))
        player.currentTime = target
        currentTime = target
    }

    public func stop() {
        clock?.cancel()
        clock = nil
        player?.stop()
        player = nil
        recordingID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// Also callable by a deterministic fixture without a timer or sound output.
    public func refresh() {
        guard let player else { return }
        if isPlaying && !player.isPlaying { stop(); return }
        currentTime = min(duration, max(0, player.currentTime.isFinite ? player.currentTime : 0))
    }

    private func startClock() {
        clock?.cancel()
        guard automaticUpdates else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                self?.refresh()
                if self?.isPlaying != true { return }
            }
        }
    }
}
