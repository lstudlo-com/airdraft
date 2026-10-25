import XCTest
@testable import AirdraftCore

final class HotkeyBehaviorTests: XCTestCase {
    func testGestureMatchesBehaviorAndTriggerDelay() {
        XCTAssertEqual(HotkeyBehavior.hold.gesture(triggerDelayMilliseconds: 0), .hold)
        XCTAssertEqual(HotkeyBehavior.hold.gesture(triggerDelayMilliseconds: 300), .hold)
        XCTAssertEqual(HotkeyBehavior.toggle.gesture(triggerDelayMilliseconds: 0), .press)
        XCTAssertEqual(HotkeyBehavior.toggle.gesture(triggerDelayMilliseconds: 300), .holdThenPress)
        XCTAssertTrue(HotkeyGesture.holdThenPress.startsByHolding)
        XCTAssertFalse(HotkeyGesture.press.startsByHolding)
    }
}
