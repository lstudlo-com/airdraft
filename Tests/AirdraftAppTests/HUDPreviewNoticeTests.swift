import XCTest

/// A model without live text shows its notice briefly instead of the live-text
/// window. HUD content is rebuilt on every state change, so repeating the same
/// notice must keep its first deadline.
@MainActor
final class HUDPreviewNoticeTests: XCTestCase {
    func testNoticeFadesAndClearsAfterItsDeadline() async throws {
        let notice = HUDPreviewNotice(visibleFor: 0.05, fadeFor: 0.05)
        notice.present("Model doesn’t support live text")
        XCTAssertEqual(notice.message, "Model doesn’t support live text")
        XCTAssertFalse(notice.isFading)
        try await waitUntil { notice.isFading }
        XCTAssertNotNil(notice.message, "The notice stays laid out while it fades")
        try await waitUntil { notice.message == nil }
    }

    func testRepeatingTheSameNoticeKeepsItsDeadline() async throws {
        let notice = HUDPreviewNotice(visibleFor: 0.3, fadeFor: 0.01)
        notice.present("Same")
        try await Task.sleep(for: .milliseconds(200))
        notice.present("Same")
        // Restarting would keep it visible until about 0.51 s after the start.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(notice.message)
        // Once expired, the same recording's notice does not reopen.
        notice.present("Same")
        XCTAssertNil(notice.message)
    }

    func testClearingLetsTheNextRecordingShowItAgain() {
        let notice = HUDPreviewNotice(visibleFor: 10, fadeFor: 0.01)
        notice.present("Same")
        notice.present(nil)
        XCTAssertNil(notice.message)
        notice.present("Same")
        XCTAssertEqual(notice.message, "Same")
        XCTAssertFalse(notice.isFading)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Condition not met") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
