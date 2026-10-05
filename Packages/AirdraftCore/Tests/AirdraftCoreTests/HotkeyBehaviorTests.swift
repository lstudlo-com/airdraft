import XCTest
@testable import AirdraftCore

final class HotkeyBehaviorTests: XCTestCase {
    func testInstructionVerbMatchesBehavior() {
        XCTAssertEqual(HotkeyBehavior.hold.instructionVerb, "Hold")
        XCTAssertEqual(HotkeyBehavior.toggle.instructionVerb, "Press")
        XCTAssertEqual(HotkeyBehavior.toggle.instructionVerb(triggerDelayMilliseconds: 300), "Hold")
        XCTAssertEqual(HotkeyBehavior.toggle.instructionVerb(triggerDelayMilliseconds: 0), "Press")
        XCTAssertEqual(HotkeyBehavior.hold.instructionVerb(triggerDelayMilliseconds: 300), "Hold")
    }
}
