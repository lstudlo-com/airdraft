import XCTest
@testable import AirdraftCore

final class ControlOptionHotkeyTests: XCTestCase {
    private let combination = Hotkey.maskControl | Hotkey.maskAlternate

    @MainActor func testDefaultAndSavedShortcuts() {
        let suite = "airdraft.hotkey-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotkey, .controlOption)
        XCTAssertEqual(settings.hotkeyBehavior, .hold)
        XCTAssertEqual(settings.hotkey.keyCaps, ["⌃", "⌥"])

        for shortcut in [Hotkey.optionSpace, Hotkey(keyCode: 61, isModifierOnly: true), .controlOption] {
            settings.hotkey = shortcut
            XCTAssertEqual(AppSettings(defaults: defaults).hotkey, shortcut)
        }
    }

    func testEitherPressAndReleaseOrderOnEitherSide() {
        for control: UInt16 in [59, 62] {
            for option: UInt16 in [58, 61] {
                for order in [[control, option], [option, control]] {
                    for released in [control, option] {
                        var state = HotkeyPressState()
                        let firstFlags = Hotkey.modifierFlag(for: order[0])!
                        XCTAssertNil(state.handle(.flagsChanged, hotkey: .controlOption,
                                                  keyCode: order[0], flags: firstFlags).transition)
                        let press = state.handle(.flagsChanged, hotkey: .controlOption,
                                                 keyCode: order[1], flags: combination)
                        XCTAssertEqual(press.transition, .pressed)
                        XCTAssertFalse(press.consumesEvent)
                        XCTAssertNil(state.handle(.flagsChanged, hotkey: .controlOption,
                                                  keyCode: order[1], flags: combination).transition)

                        let remaining = combination & ~Hotkey.modifierFlag(for: released)!
                        let release = state.handle(.flagsChanged, hotkey: .controlOption,
                                                   keyCode: released, flags: remaining)
                        XCTAssertEqual(release.transition, .released)
                        XCTAssertFalse(release.consumesEvent)
                        XCTAssertFalse(state.isDown)
                        // Re-holding the released modifier starts the next dictation.
                        XCTAssertEqual(state.handle(.flagsChanged, hotkey: .controlOption,
                                                    keyCode: released, flags: combination).transition, .pressed)
                    }
                }
            }
        }
    }

    func testUnrelatedKeysAndExtraModifiersDoNotStartRecording() {
        var state = HotkeyPressState()
        for event in [HotkeyPressState.Event.keyDown, .keyUp] {
            let result = state.handle(event, hotkey: .controlOption, keyCode: 0, flags: combination)
            XCTAssertNil(result.transition)
            XCTAssertFalse(result.consumesEvent)
        }
        XCTAssertNil(state.handle(.flagsChanged, hotkey: .controlOption, keyCode: 58,
                                  flags: combination | Hotkey.maskCommand).transition)
        XCTAssertFalse(state.isDown)
    }

    func testOtherModifiersDoNotInterruptAnActiveHold() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: .controlOption, keyCode: 58, flags: combination)
        XCTAssertNil(state.handle(.flagsChanged, hotkey: .controlOption, keyCode: 55,
                                  flags: combination | Hotkey.maskCommand).transition)
        XCTAssertNil(state.handle(.flagsChanged, hotkey: .controlOption, keyCode: 55,
                                  flags: combination).transition)
        XCTAssertEqual(state.handle(.flagsChanged, hotkey: .controlOption, keyCode: 59,
                                    flags: Hotkey.maskAlternate).transition, .released)
    }

    func testInterruptionRecoveryUsesBothModifierFlagsAndHealthyPollsDoNotRelease() {
        var state = HotkeyPressState()
        _ = state.handle(.flagsChanged, hotkey: .controlOption, keyCode: 58, flags: combination)
        XCTAssertNil(state.reconcile(afterInterruption: false, hotkey: .controlOption,
                                     modifierFlags: 0, keyIsDown: false))
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: .controlOption,
                                     modifierFlags: combination, keyIsDown: false))
        XCTAssertTrue(state.isDown)
        XCTAssertEqual(state.reconcile(afterInterruption: true, hotkey: .controlOption,
                                       modifierFlags: Hotkey.maskControl, keyIsDown: true), .released)
        XCTAssertNil(state.reconcile(afterInterruption: true, hotkey: .controlOption,
                                     modifierFlags: combination, keyIsDown: true))
        XCTAssertFalse(state.isDown)
    }
}
