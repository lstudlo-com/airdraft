import IOKit.hidsystem
import XCTest
@testable import AirdraftCore

final class HotkeyPressStateTests: XCTestCase {
    private let rightOption = Hotkey(keyCode: 61, isModifierOnly: true)
    private let rightOptionFlags = Hotkey.maskAlternate | UInt64(NX_DEVICERALTKEYMASK)

    func testModifierPressAndReleasePassThrough() {
        var state = HotkeyPressState()
        let down = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: rightOptionFlags)
        XCTAssertEqual(down.transition, .pressed)
        XCTAssertFalse(down.consumesEvent)
        let up = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: 0)
        XCTAssertEqual(up.transition, .released)
        XCTAssertFalse(up.consumesEvent)
    }

    func testReleaseWhileOppositeModifierIsHeldDoesNotLoseNextPress() {
        let pairs: [(UInt16, UInt16, UInt64, Int32, Int32)] = [
            (61, 58, Hotkey.maskAlternate, NX_DEVICERALTKEYMASK, NX_DEVICELALTKEYMASK),
            (54, 55, Hotkey.maskCommand, NX_DEVICERCMDKEYMASK, NX_DEVICELCMDKEYMASK),
            (62, 59, Hotkey.maskControl, NX_DEVICERCTLKEYMASK, NX_DEVICELCTLKEYMASK),
            (60, 56, Hotkey.maskShift, NX_DEVICERSHIFTKEYMASK, NX_DEVICELSHIFTKEYMASK),
        ]
        for (right, left, aggregate, rightBit, leftBit) in pairs {
            for (own, other, ownBit, otherBit) in [(right, left, rightBit, leftBit), (left, right, leftBit, rightBit)] {
                var state = HotkeyPressState()
                let hotkey = Hotkey(keyCode: own, isModifierOnly: true)
                XCTAssertEqual(state.handle(.flagsChanged, hotkey: hotkey, keyCode: own,
                                            flags: aggregate | UInt64(ownBit)).transition, .pressed)
                XCTAssertNil(state.handle(.flagsChanged, hotkey: hotkey, keyCode: other,
                                          flags: aggregate | UInt64(ownBit | otherBit)).transition)
                // The aggregate flag remains set after the configured key is released.
                XCTAssertEqual(state.handle(.flagsChanged, hotkey: hotkey, keyCode: own,
                                            flags: aggregate | UInt64(otherBit)).transition, .released)
                XCTAssertNil(state.handle(.flagsChanged, hotkey: hotkey, keyCode: other, flags: 0).transition)
                XCTAssertEqual(state.handle(.flagsChanged, hotkey: hotkey, keyCode: own,
                                            flags: aggregate | UInt64(ownBit)).transition, .pressed)
            }
        }
    }

    func testQueuedModifierEventUsesItsFlagsRatherThanLaterPhysicalState() {
        var state = HotkeyPressState()
        // The user has already released by the time the queued press is handled.
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: rightOptionFlags, modifierKeyIsDown: false).transition, .pressed)
        // A subsequent physical press must not turn the queued release into a press.
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: Hotkey.maskAlternate | UInt64(NX_DEVICELALTKEYMASK),
                                    modifierKeyIsDown: true).transition, .released)
    }

    func testRemappedModifierWithoutSideFlagsUsesExactKeyState() {
        var state = HotkeyPressState()
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: Hotkey.maskAlternate, modifierKeyIsDown: true).transition, .pressed)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: Hotkey.maskAlternate, modifierKeyIsDown: false).transition, .released)
    }

    func testMissedReleaseDuringInterruptionDoesNotSuppressNextPress() {
        var state = HotkeyPressState()
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: rightOptionFlags).transition, .pressed)
        // No release event was delivered while the tap was disabled.
        XCTAssertEqual(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                       modifierFlags: 0, keyIsDown: false), .released)
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                     modifierFlags: 0, keyIsDown: false))
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: rightOptionFlags).transition, .pressed)
    }

    func testRecoveryWhileStillHeldKeepsRecordingWithoutAnotherPress() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: rightOptionFlags)
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                     modifierFlags: rightOptionFlags, keyIsDown: true))
        XCTAssertTrue(state.isDown)
        XCTAssertNil(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                  flags: rightOptionFlags).transition)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: 0).transition, .released)
    }

    func testPollingNeverStartsAnUnrequestedRecording() {
        var state = HotkeyPressState()
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                     modifierFlags: rightOptionFlags, keyIsDown: true))
        XCTAssertFalse(state.isDown)
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                     modifierFlags: 0, keyIsDown: false))
    }

    func testHealthyTapPollCannotEndRecordingEvenWhenKeyStateReportsUp() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: rightOptionFlags)
        // Regression: the two-second health timer used to end a held recording
        // because keyState returned false for the modifier. No interruption
        // occurred, so neither a key snapshot nor a flags snapshot can stop it.
        for _ in 0..<10 {
            XCTAssertNil(state.reconcile(afterInterruption: false, hotkey: rightOption,
                                         modifierFlags: 0, keyIsDown: false))
            XCTAssertTrue(state.isDown)
        }
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: 0).transition, .released)
    }

    func testInterruptedModifierUsesFlagsWhenKeyStateIncorrectlyReportsUp() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: rightOptionFlags)
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                     modifierFlags: rightOptionFlags, keyIsDown: false))
        XCTAssertTrue(state.isDown)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: 0).transition, .released)
    }

    func testInterruptedModifierWithAmbiguousSideFlagsWaitsForRealRelease() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: rightOptionFlags)
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: rightOption,
                                     modifierFlags: Hotkey.maskAlternate, keyIsDown: false))
        XCTAssertTrue(state.isDown)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: 0).transition, .released)
    }

    func testStoppingOrSuspendingBalancesHeldPressAndAllowsNextPress() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61, flags: rightOptionFlags)
        XCTAssertEqual(state.reset(), .released)
        XCTAssertNil(state.reset())
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: rightOption, keyCode: 61,
                                    flags: rightOptionFlags).transition, .pressed)
    }

    func testFnModifierHasNoSideSpecificFlag() {
        var state = HotkeyPressState()
        let fn = Hotkey(keyCode: 63, isModifierOnly: true)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: fn, keyCode: 63,
                                    flags: Hotkey.maskSecondaryFn).transition, .pressed)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: fn, keyCode: 63, flags: 0).transition, .released)
    }

    func testCombinationSwallowsRepeatsAndReleasesAfterModifiersAreReleased() {
        var state = HotkeyPressState()
        let hotkey = Hotkey(keyCode: 49, modifiers: Hotkey.maskSecondaryFn)
        let down = state.handle(.keyDown, hotkey: hotkey, keyCode: 49, flags: Hotkey.maskSecondaryFn)
        XCTAssertEqual(down.transition, .pressed)
        XCTAssertTrue(down.consumesEvent)
        let repeated = state.handle(.keyDown, hotkey: hotkey, keyCode: 49,
                                    flags: Hotkey.maskSecondaryFn, isRepeat: true)
        XCTAssertNil(repeated.transition)
        XCTAssertTrue(repeated.consumesEvent)
        let up = state.handle(.keyUp, hotkey: hotkey, keyCode: 49, flags: 0)
        XCTAssertEqual(up.transition, .released)
        XCTAssertTrue(up.consumesEvent)
    }

    func testUnmatchedCombinationPassesThroughWithoutStartingRecording() {
        var state = HotkeyPressState()
        for (key, flags) in [(UInt16(49), UInt64(0)), (UInt16(36), Hotkey.maskAlternate)] {
            let result = state.handle(.keyDown, hotkey: .optionSpace, keyCode: key, flags: flags)
            XCTAssertNil(result.transition)
            XCTAssertFalse(result.consumesEvent)
        }
        XCTAssertFalse(state.isDown)
    }
}
