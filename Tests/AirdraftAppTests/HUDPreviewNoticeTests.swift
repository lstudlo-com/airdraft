import XCTest

/// A model without live text shows its notice briefly instead of the live-text
/// window. HUD content is rebuilt on every state change, so repeating the same
/// notice must keep its first deadline. A manual clock drives the phases, so
/// the tests never depend on how fast the machine runs.
@MainActor
final class HUDPreviewNoticeTests: XCTestCase {
    func testNoticeFadesAndClearsAfterItsDeadline() async throws {
        let clock = ManualSleep()
        let notice = HUDPreviewNotice(visibleFor: 2, fadeFor: 0.3, sleep: clock.sleep)
        // Clearing cancels any phase still waiting, so no task outlives the test.
        defer { notice.present(nil) }
        notice.present("Model doesn’t support live text")
        XCTAssertEqual(notice.message, "Model doesn’t support live text")
        XCTAssertFalse(notice.isFading)
        try await waitUntil { clock.waiting == [2] }
        clock.elapse()
        try await waitUntil { notice.isFading }
        XCTAssertNotNil(notice.message, "The notice stays laid out while it fades")
        try await waitUntil { clock.waiting == [0.3] }
        clock.elapse()
        try await waitUntil { notice.message == nil }
    }

    func testRepeatingTheSameNoticeKeepsItsDeadline() async throws {
        let clock = ManualSleep()
        let notice = HUDPreviewNotice(visibleFor: 2, fadeFor: 0.3, sleep: clock.sleep)
        // Clearing cancels any phase still waiting, so no task outlives the test.
        defer { notice.present(nil) }
        notice.present("Same")
        try await waitUntil { clock.waiting == [2] }
        notice.present("Same")
        await Task.yield()
        XCTAssertEqual(clock.waiting, [2], "Repeating the notice must not start a new deadline")
        clock.elapse()
        try await waitUntil { clock.waiting == [0.3] }
        clock.elapse()
        try await waitUntil { notice.message == nil }
        // Once expired, the same recording's notice does not reopen.
        notice.present("Same")
        XCTAssertNil(notice.message)
        XCTAssertEqual(clock.waiting, [])
    }

    func testClearingLetsTheNextRecordingShowItAgain() async throws {
        let clock = ManualSleep()
        let notice = HUDPreviewNotice(visibleFor: 2, fadeFor: 0.3, sleep: clock.sleep)
        // Clearing cancels any phase still waiting, so no task outlives the test.
        defer { notice.present(nil) }
        notice.present("Same")
        try await waitUntil { clock.waiting == [2] }
        notice.present(nil)
        XCTAssertNil(notice.message)
        try await waitUntil { clock.waiting.isEmpty }
        notice.present("Same")
        XCTAssertEqual(notice.message, "Same")
        XCTAssertFalse(notice.isFading)
    }

    /// Polls for a state the manual clock has already made inevitable; the
    /// deadline only bounds a broken test, it is never part of the timing.
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Condition not met") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Sleeps that end only when the test calls `elapse()`; cancelling the
/// sleeping task ends them with CancellationError, as Task.sleep does.
@MainActor
private final class ManualSleep {
    private(set) var waiting: [TimeInterval] = []
    private var ids: [Int] = []
    private var released: Set<Int> = []
    private var nextID = 0

    var sleep: HUDPreviewNotice.Sleep {
        { duration in try await self.wait(duration) }
    }

    private func wait(_ duration: TimeInterval) async throws {
        let id = nextID
        nextID += 1
        ids.append(id)
        waiting.append(duration)
        defer {
            if let index = ids.firstIndex(of: id) {
                ids.remove(at: index)
                waiting.remove(at: index)
            }
            released.remove(id)
        }
        while !released.contains(id) {
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Ends the earliest sleep still waiting.
    func elapse() {
        if let first = ids.first { released.insert(first) }
    }
}
