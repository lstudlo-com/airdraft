import IOKit.hidsystem
import XCTest
@testable import AirdraftCore

final class HotkeyRehearsalTests: XCTestCase {
    private let control = Hotkey.maskControl
    private let option = Hotkey.maskAlternate

    func testModifierChordsLightEachCapAndCountOnlyTheExactChord() {
        // A modifier combination lights each cap and counts only the full chord.
        do {
            var rehearsal = HotkeyRehearsal(hotkey: .controlOption)
            XCTAssertEqual(Hotkey.controlOption.keyCaps, ["⌃", "⌥"])
            rehearsal.handle(.flagsChanged, keyCode: 59, flags: control)
            XCTAssertEqual(rehearsal.litCaps, [0])
            XCTAssertEqual(rehearsal.completedPresses, 0, "One key of the chord is not a press")
            rehearsal.handle(.flagsChanged, keyCode: 58, flags: control | option)
            XCTAssertEqual(rehearsal.litCaps, [0, 1])
            XCTAssertTrue(rehearsal.isPressed)
            XCTAssertEqual(rehearsal.completedPresses, 1)
            rehearsal.handle(.flagsChanged, keyCode: 59, flags: option)
            XCTAssertEqual(rehearsal.litCaps, [1])
            XCTAssertFalse(rehearsal.isPressed)
            rehearsal.handle(.flagsChanged, keyCode: 58, flags: 0)
            XCTAssertTrue(rehearsal.litCaps.isEmpty)
            XCTAssertEqual(rehearsal.completedPresses, 1)
        }

        // An extra modifier does not start the chord.
        do {
            var rehearsal = HotkeyRehearsal(hotkey: .controlOption)
            rehearsal.handle(.flagsChanged, keyCode: 59, flags: control | Hotkey.maskCommand)
            rehearsal.handle(.flagsChanged, keyCode: 58, flags: control | option | Hotkey.maskCommand)
            XCTAssertEqual(rehearsal.litCaps, [0, 1], "Held keys still light so people can see what they pressed")
            XCTAssertEqual(rehearsal.completedPresses, 0, "Dictation would not start, so practice must not count it")
        }

        // A single-side modifier uses device flags.
        do {
            let rightOption = Hotkey(keyCode: 61, isModifierOnly: true)
            var rehearsal = HotkeyRehearsal(hotkey: rightOption)
            XCTAssertEqual(rightOption.keyCaps, ["Right ⌥"])
            rehearsal.handle(.flagsChanged, keyCode: 58, flags: option | UInt64(NX_DEVICELALTKEYMASK))
            XCTAssertTrue(rehearsal.litCaps.isEmpty, "Left Option is a different key")
            rehearsal.handle(.flagsChanged, keyCode: 58, flags: 0)
            rehearsal.handle(.flagsChanged, keyCode: 61, flags: option | UInt64(NX_DEVICERALTKEYMASK))
            XCTAssertEqual(rehearsal.litCaps, [0])
            XCTAssertEqual(rehearsal.completedPresses, 1)
            rehearsal.handle(.flagsChanged, keyCode: 61, flags: 0)
            XCTAssertTrue(rehearsal.litCaps.isEmpty)
        }
    }

    func testKeyChordsLightWhileHeldIgnoreRepeatAndResetAfterFocusLoss() {
        // A key with a modifier lights the key only while held.
        do {
            var rehearsal = HotkeyRehearsal(hotkey: .optionSpace)
            XCTAssertEqual(Hotkey.optionSpace.keyCaps, ["⌥", "Space"])
            rehearsal.handle(.flagsChanged, keyCode: 58, flags: option)
            XCTAssertEqual(rehearsal.litCaps, [0])
            rehearsal.handle(.keyDown, keyCode: 49, flags: option)
            XCTAssertEqual(rehearsal.litCaps, [0, 1])
            XCTAssertEqual(rehearsal.completedPresses, 1)
            rehearsal.handle(.keyDown, keyCode: 49, flags: option, isRepeat: true)
            XCTAssertEqual(rehearsal.completedPresses, 1, "Key repeat is not another press")
            rehearsal.handle(.keyUp, keyCode: 49, flags: option)
            XCTAssertEqual(rehearsal.litCaps, [0])
            XCTAssertFalse(rehearsal.isPressed)
        }

        // The fn cap, and reset after focus loss.
        do {
            let fnSpace = Hotkey(keyCode: 49, modifiers: Hotkey.maskSecondaryFn)
            var rehearsal = HotkeyRehearsal(hotkey: fnSpace)
            XCTAssertEqual(fnSpace.keyCaps, ["fn", "Space"])
            rehearsal.handle(.flagsChanged, keyCode: 63, flags: Hotkey.maskSecondaryFn)
            rehearsal.handle(.keyDown, keyCode: 49, flags: Hotkey.maskSecondaryFn)
            XCTAssertEqual(rehearsal.litCaps, [0, 1])
            rehearsal.reset()
            XCTAssertTrue(rehearsal.litCaps.isEmpty)
            XCTAssertFalse(rehearsal.isPressed)
            XCTAssertEqual(rehearsal.completedPresses, 1)
        }
    }
}
