import XCTest
@testable import AirdraftCore

@MainActor
final class RecordingPlaybackTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/unused-silent-fixture.wav")

    func testPauseResumeSeekAndReplacementNeverOverlap() throws {
        let first = SilentTransport()
        let second = SilentTransport()
        var creations = 0
        let playback = RecordingPlayback(automaticUpdates: false) { _ in
            creations += 1
            if creations == 2 { XCTAssertFalse(first.isPlaying); XCTAssertEqual(first.stops, 1) }
            return creations == 1 ? first : second
        }
        try playback.toggle(id: "first", url: url)
        XCTAssertTrue(playback.isPlaying)
        first.currentTime = 12
        playback.refresh()
        XCTAssertEqual(playback.currentTime, 12)
        try playback.toggle(id: "first", url: url)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.recordingID, "first")
        playback.seek(to: 32)
        XCTAssertEqual(first.currentTime, 32)
        try playback.toggle(id: "first", url: url)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(creations, 1, "Resume must reuse the paused transport")
        try playback.toggle(id: "second", url: url)
        XCTAssertEqual(playback.recordingID, "second")
        XCTAssertEqual(playback.currentTime, 0)
        playback.stop()
        XCTAssertEqual(second.stops, 1)
        XCTAssertNil(playback.recordingID)
        XCTAssertFalse(playback.isPlaying)
    }

    func testBoundsCompletionAndFailedStartClearState() throws {
        let transport = SilentTransport()
        let playback = RecordingPlayback(automaticUpdates: false) { _ in transport }
        try playback.toggle(id: "one", url: url)
        playback.seek(to: -12)
        XCTAssertEqual(playback.currentTime, 0)
        playback.seek(to: 0.8)
        XCTAssertEqual(playback.currentTime, 0.8, accuracy: 0.001)
        playback.seek(to: .infinity)
        XCTAssertEqual(playback.currentTime, 0.8, accuracy: 0.001)
        playback.seek(to: 1000)
        XCTAssertEqual(playback.currentTime, transport.duration)
        transport.isPlaying = false
        playback.refresh()
        XCTAssertNil(playback.recordingID)
        transport.canStart = false
        XCTAssertThrowsError(try playback.toggle(id: "broken", url: url))
        XCTAssertNil(playback.recordingID)
        XCTAssertFalse(playback.isPlaying)
    }

    func testOpenFailureStopsPreviousRecording() throws {
        let transport = SilentTransport()
        var fail = false
        let playback = RecordingPlayback(automaticUpdates: false) { _ in
            if fail { throw CocoaError(.fileNoSuchFile) }
            return transport
        }
        try playback.toggle(id: "old", url: url)
        fail = true
        XCTAssertThrowsError(try playback.toggle(id: "missing", url: url))
        XCTAssertFalse(transport.isPlaying)
        XCTAssertNil(playback.recordingID)
    }
}

/// No AVFoundation dependency and no audio output under any test path.
@MainActor
private final class SilentTransport: RecordingPlaybackTransport {
    let duration: TimeInterval = 120
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var canStart = true
    var stops = 0
    func play() -> Bool { isPlaying = canStart; return canStart }
    func pause() { isPlaying = false }
    func stop() { stops += 1; isPlaying = false }
}
