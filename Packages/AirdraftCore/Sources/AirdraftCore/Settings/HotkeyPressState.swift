import IOKit.hidsystem

/// Tracks one shortcut independently of the event tap's lifetime.
public struct HotkeyPressState: Sendable {
    public enum Event: Sendable { case keyDown, keyUp, flagsChanged }
    public enum Transition: Equatable, Sendable { case pressed, released }

    public private(set) var isDown = false

    public init() {}

    public mutating func handle(
        _ event: Event,
        hotkey: Hotkey,
        keyCode: UInt16,
        flags: UInt64,
        isRepeat: Bool = false,
        modifierKeyIsDown: @autoclosure () -> Bool = false
    ) -> (transition: Transition?, consumesEvent: Bool) {
        if hotkey.isModifierOnly, hotkey.modifiers != 0 {
            guard case .flagsChanged = event,
                  Hotkey.modifierFlag(for: keyCode) != nil else { return (nil, false) }
            let held = flags & Hotkey.relevantModifierMask
            // Start only on the configured combination. Once held, additional
            // modifiers must not end recording before either required key lifts.
            let down = isDown ? held & hotkey.modifiers == hotkey.modifiers : held == hotkey.modifiers
            return (update(down), false)
        }
        guard keyCode == hotkey.keyCode else { return (nil, false) }
        if hotkey.isModifierOnly {
            guard case .flagsChanged = event else { return (nil, false) }
            let down = Self.modifierIsDown(keyCode: keyCode, flags: flags, fallback: modifierKeyIsDown())
            return (update(down), false)
        }

        switch event {
        case .keyDown:
            guard flags & Hotkey.relevantModifierMask == hotkey.modifiers else { return (nil, false) }
            return (isRepeat ? nil : update(true), true)
        case .keyUp:
            guard isDown else { return (nil, false) }
            return (update(false), true)
        case .flagsChanged:
            return (nil, false)
        }
    }

    /// Repair a missed release only after monitoring was interrupted. A normal
    /// health poll must never synthesize a release from a key-state snapshot.
    public mutating func reconcile(
        afterInterruption: Bool,
        hotkey: Hotkey,
        modifierFlags: UInt64,
        keyIsDown: @autoclosure () -> Bool
    ) -> Transition? {
        guard afterInterruption, isDown else { return nil }
        if hotkey.isModifierOnly, hotkey.modifiers != 0 {
            return update(modifierFlags & hotkey.modifiers == hotkey.modifiers)
        }
        // Modifier presses arrive as flagsChanged. Their key-state table can
        // report false while they are still held; use modifier flags instead.
        // If side-specific flags are unavailable, retain the hold until a real
        // release arrives rather than stop somebody's recording speculatively.
        let down = hotkey.isModifierOnly
            ? Self.modifierIsDown(keyCode: hotkey.keyCode, flags: modifierFlags, fallback: true)
            : keyIsDown()
        guard !down else { return nil }
        return update(false)
    }

    /// Balance an outstanding press when monitoring stops or is suspended.
    public mutating func reset() -> Transition? { update(false) }

    private mutating func update(_ down: Bool) -> Transition? {
        guard down != isDown else { return nil }
        isDown = down
        return down ? .pressed : .released
    }

    /// The aggregate Option/Shift/Control/Command bit stays set while either
    /// side is held. Use the event's device-specific bits before consulting
    /// current key state, which may already be ahead of a queued event.
    private static func modifierIsDown(keyCode: UInt16, flags: UInt64, fallback: @autoclosure () -> Bool) -> Bool {
        guard let aggregate = Hotkey.modifierFlag(for: keyCode), flags & aggregate != 0 else { return false }
        let own: Int32
        let pair: Int32
        switch keyCode {
        case 54, 55:
            own = keyCode == 54 ? NX_DEVICERCMDKEYMASK : NX_DEVICELCMDKEYMASK
            pair = NX_DEVICERCMDKEYMASK | NX_DEVICELCMDKEYMASK
        case 58, 61:
            own = keyCode == 61 ? NX_DEVICERALTKEYMASK : NX_DEVICELALTKEYMASK
            pair = NX_DEVICERALTKEYMASK | NX_DEVICELALTKEYMASK
        case 59, 62:
            own = keyCode == 62 ? NX_DEVICERCTLKEYMASK : NX_DEVICELCTLKEYMASK
            pair = NX_DEVICERCTLKEYMASK | NX_DEVICELCTLKEYMASK
        case 56, 60:
            own = keyCode == 60 ? NX_DEVICERSHIFTKEYMASK : NX_DEVICELSHIFTKEYMASK
            pair = NX_DEVICERSHIFTKEYMASK | NX_DEVICELSHIFTKEYMASK
        case 63:
            return true // fn has no left/right pair.
        default:
            return false
        }
        // Some remappers omit device-specific flags. Query that exact key,
        // never infer its state from the aggregate modifier bit.
        guard flags & UInt64(pair) != 0 else { return fallback() }
        return flags & UInt64(own) != 0
    }
}
