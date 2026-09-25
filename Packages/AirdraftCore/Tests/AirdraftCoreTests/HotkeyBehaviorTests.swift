import XCTest
@testable import AirdraftCore

final class HotkeyBehaviorTests: XCTestCase {
    func testInstructionVerbMatchesBehavior() {
        XCTAssertEqual(HotkeyBehavior.hold.instructionVerb, "Hold")
        XCTAssertEqual(HotkeyBehavior.toggle.instructionVerb, "Press")
    }
}
