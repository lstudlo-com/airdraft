import AppKit
import XCTest

/// The app automatic-profile labels name: never Airdraft itself, and fixed by
/// the Debug override. Activation is simulated by posting to the in-process
/// workspace notification center; no other app is launched or activated.
@MainActor
final class FrontmostApplicationTests: XCTestCase {
    private func activate(_ app: NSRunningApplication) {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification,
                                                   object: NSWorkspace.shared,
                                                   userInfo: [NSWorkspace.applicationUserInfoKey: app])
        // Observers use the main queue; let any queued delivery run.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testOwnProcessIsNeverTheDestination() {
        let frontmost = FrontmostApplication()
        frontmost.override(.init(bundleID: "com.apple.TextEdit", name: "TextEdit"))
        let fresh = FrontmostApplication()
        // Activating this process (the test runner) reads as no destination.
        activate(.current)
        XCTAssertNil(fresh.current)
        XCTAssertEqual(frontmost.current, .init(bundleID: "com.apple.TextEdit", name: "TextEdit"))
    }

    func testOverrideIgnoresLaterActivation() {
        let frontmost = FrontmostApplication()
        let notes = FrontmostApplication.App(bundleID: "com.apple.Notes", name: "Notes")
        frontmost.override(notes)
        activate(.current)
        XCTAssertEqual(frontmost.current, notes)
        frontmost.override(nil)
        XCTAssertNil(frontmost.current)
        activate(.current)
        XCTAssertNil(frontmost.current)
    }
}
