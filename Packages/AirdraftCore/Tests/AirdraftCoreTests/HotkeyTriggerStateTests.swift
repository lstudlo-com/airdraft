import XCTest
@testable import AirdraftCore

final class HotkeyTriggerStateTests: XCTestCase {
    private let space = Hotkey(keyCode: 49)

    private func send(_ event: HotkeyPressState.Event, to state: inout HotkeyTriggerState,
                      hotkey: Hotkey = Hotkey(keyCode: 49), code: UInt16 = 49,
                      flags: UInt64 = 0, repeatKey: Bool = false, now: Double = 10,
                      delay: Int = 300) -> HotkeyTriggerState.Result {
        state.handle(event, hotkey: hotkey, keyCode: code, flags: flags,
                     isRepeat: repeatKey, now: now, delayMilliseconds: delay)
    }

    func testZeroDelayAndToggleStopBypassThreshold() {
        var state = HotkeyTriggerState()
        let down = send(.keyDown, to: &state, delay: 0)
        XCTAssertEqual(down.transition, .pressed)
        XCTAssertEqual(down.disposition, .consume)
        XCTAssertNil(state.deadline)
        XCTAssertEqual(send(.keyUp, to: &state, delay: 0).transition, .released)
        _ = send(.keyDown, to: &state)
        _ = state.fire(now: 11)
        _ = send(.keyUp, to: &state)
        XCTAssertEqual(send(.keyDown, to: &state, delay: 0).transition, .pressed)
        XCTAssertNil(state.deadline)
    }

    func testPlainKeyShortPressReplaysLongHoldStartsOnceAndLateTimerCannotStart() {
        // A short press returns down before up without starting or stopping.
        do {
            var state = HotkeyTriggerState()
            let down = send(.keyDown, to: &state)
            XCTAssertEqual(down.disposition, .buffer)
            XCTAssertNil(down.transition)
            XCTAssertEqual(state.deadline, 10.3)
            let up = send(.keyUp, to: &state, now: 10.1)
            XCTAssertTrue(up.replayBuffered)
            XCTAssertEqual(up.disposition, .pass)
            XCTAssertNil(up.transition)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertNil(state.deadline)
        }

        // A long hold starts exactly once and consumes until release.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state)
            XCTAssertNil(state.fire(now: 10.299).transition)
            let threshold = state.fire(now: 10.3)
            XCTAssertEqual(threshold.transition, .pressed)
            XCTAssertTrue(threshold.discardBuffered)
            XCTAssertNil(state.fire(now: 12).transition)
            let repeated = send(.keyDown, to: &state, repeatKey: true, now: 12)
            XCTAssertEqual(repeated.disposition, .consume)
            XCTAssertNil(repeated.transition)
            let up = send(.keyUp, to: &state, now: 13)
            XCTAssertEqual(up.transition, .released)
            XCTAssertEqual(up.disposition, .consume)
            XCTAssertNil(send(.keyUp, to: &state).transition)
        }

        // Repeat does not restart the threshold and is replayed on a short press.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state, delay: 1000)
            let repeatEvent = send(.keyDown, to: &state, repeatKey: true, now: 10.5, delay: 1000)
            XCTAssertEqual(repeatEvent.disposition, .buffer)
            XCTAssertEqual(state.deadline, 11)
            XCTAssertTrue(send(.keyUp, to: &state, now: 10.6).replayBuffered)
        }

        // A late timer after release cannot start; a repeat without a down passes.
        do {
            var state = HotkeyTriggerState()
            XCTAssertEqual(send(.keyDown, to: &state, repeatKey: true).disposition, .pass)
            _ = send(.keyDown, to: &state)
            XCTAssertTrue(send(.keyUp, to: &state, now: 11).replayBuffered)
            XCTAssertNil(state.fire(now: 11).transition)
        }
    }

    func testTypingFocusResetAndInterruptionCancelPendingHold() {
        // Typing another key flushes the first key in order and cancels the hold.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state)
            let next = send(.keyDown, to: &state, code: 0, now: 10.1)
            XCTAssertTrue(next.replayBuffered)
            XCTAssertEqual(next.disposition, .pass)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertEqual(send(.keyDown, to: &state, repeatKey: true).disposition, .pass)
            XCTAssertEqual(send(.keyUp, to: &state).disposition, .pass)
            XCTAssertEqual(send(.keyDown, to: &state, now: 12).disposition, .buffer)
        }

        // A focus change cancels once and requires a fresh press.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state)
            XCTAssertTrue(state.cancelPending().replayBuffered)
            XCTAssertFalse(state.cancelPending().replayBuffered)
            XCTAssertNil(state.fire(now: 11).transition)
            _ = send(.keyUp, to: &state)
            _ = send(.keyDown, to: &state, now: 12)
            XCTAssertEqual(state.fire(now: 12.3).transition, .pressed)
        }

        // Reset cancels pending and balances only an activated press.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state)
            let cancelled = state.reset()
            XCTAssertTrue(cancelled.replayBuffered)
            XCTAssertNil(cancelled.transition)
            XCTAssertNil(state.fire(now: 11).transition)
            _ = send(.keyDown, to: &state, now: 12)
            XCTAssertNil(state.fire(now: 12.1).transition)
            XCTAssertEqual(state.fire(now: 12.3).transition, .pressed)
            XCTAssertEqual(state.reset().transition, .released)
            XCTAssertNil(state.reset().transition)
        }

        // An interruption cancels pending even when the key is still held.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state)
            XCTAssertTrue(state.reconcile(hotkey: space, modifierFlags: 0, keyIsDown: true).replayBuffered)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertNil(send(.keyUp, to: &state).transition)
        }
    }

    func testChordModifierReleaseCancelsPendingButActiveChordStaysConsumed() {
        // Releasing the chord modifier cancels pending and does not rearm while held.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state, hotkey: .optionSpace, flags: Hotkey.maskAlternate)
            XCTAssertTrue(send(.flagsChanged, to: &state, hotkey: .optionSpace, code: 58).replayBuffered)
            _ = send(.flagsChanged, to: &state, hotkey: .optionSpace, code: 58, flags: Hotkey.maskAlternate)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertEqual(send(.keyUp, to: &state, hotkey: .optionSpace).disposition, .pass)
        }

        // An active chord keeps repeat and release consumed after the modifier lifts.
        do {
            var state = HotkeyTriggerState()
            _ = send(.keyDown, to: &state, hotkey: .optionSpace, flags: Hotkey.maskAlternate)
            _ = state.fire(now: 11)
            _ = send(.flagsChanged, to: &state, hotkey: .optionSpace, code: 58)
            XCTAssertEqual(send(.keyDown, to: &state, hotkey: .optionSpace, repeatKey: true).disposition, .consume)
            XCTAssertEqual(send(.keyUp, to: &state, hotkey: .optionSpace).transition, .released)
        }
    }

    func testModifierOnlyShortcutsHoldThroughThresholdOrCancelOnOtherKeys() {
        // A modifier tap passes through and a normal chord cancels pending dictation.
        do {
            let option = Hotkey(keyCode: 61, isModifierOnly: true)
            var state = HotkeyTriggerState()
            let down = send(.flagsChanged, to: &state, hotkey: option, code: 61, flags: Hotkey.maskAlternate | 0x40)
            XCTAssertEqual(down.disposition, .pass)
            XCTAssertNil(down.transition)
            let typed = send(.keyDown, to: &state, hotkey: option, code: 0, flags: Hotkey.maskAlternate)
            XCTAssertEqual(typed.disposition, .pass)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertNil(send(.flagsChanged, to: &state, hotkey: option, code: 61).transition)
        }

        // Control-Option and Fn can hold through the threshold.
        do {
            for hotkey in [Hotkey.controlOption, Hotkey(keyCode: 63, isModifierOnly: true)] {
                var state = HotkeyTriggerState()
                let code: UInt16 = hotkey == .controlOption ? 58 : 63
                let flags = hotkey == .controlOption ? hotkey.modifiers : Hotkey.maskSecondaryFn
                XCTAssertNil(send(.flagsChanged, to: &state, hotkey: hotkey, code: code, flags: flags).transition)
                XCTAssertEqual(state.fire(now: 11).transition, .pressed)
                let released = send(.flagsChanged, to: &state, hotkey: hotkey, code: code)
                XCTAssertEqual(released.transition, .released)
                XCTAssertEqual(released.disposition, .pass)
            }
        }

        // Adding a modifier cancels a pending modifier chord.
        do {
            var state = HotkeyTriggerState()
            _ = send(.flagsChanged, to: &state, hotkey: .controlOption, code: 58,
                     flags: Hotkey.controlOption.modifiers)
            _ = send(.flagsChanged, to: &state, hotkey: .controlOption, code: 56,
                     flags: Hotkey.controlOption.modifiers | Hotkey.maskShift)
            XCTAssertNil(state.deadline)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertNil(send(.flagsChanged, to: &state, hotkey: .controlOption, code: 58).transition)
        }

        // A single modifier does not arm when pressed inside another chord.
        do {
            var state = HotkeyTriggerState()
            let option = Hotkey(keyCode: 61, isModifierOnly: true)
            let down = send(.flagsChanged, to: &state, hotkey: option, code: 61,
                            flags: Hotkey.maskAlternate | Hotkey.maskShift | 0x40)
            XCTAssertEqual(down.disposition, .pass)
            XCTAssertNil(state.deadline)
            XCTAssertNil(state.fire(now: 11).transition)
            XCTAssertNil(send(.flagsChanged, to: &state, hotkey: option, code: 61).transition)
        }

        // An interrupted active modifier uses flags rather than key state.
        do {
            var state = HotkeyTriggerState()
            _ = send(.flagsChanged, to: &state, hotkey: .controlOption, code: 58,
                     flags: Hotkey.controlOption.modifiers)
            _ = state.fire(now: 11)
            XCTAssertNil(state.reconcile(hotkey: .controlOption, modifierFlags: Hotkey.controlOption.modifiers,
                                         keyIsDown: false).transition)
            XCTAssertEqual(state.reconcile(hotkey: .controlOption, modifierFlags: 0, keyIsDown: false).transition, .released)
        }
    }
}
