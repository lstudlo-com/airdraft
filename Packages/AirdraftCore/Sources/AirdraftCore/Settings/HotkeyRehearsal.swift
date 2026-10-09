/// Follows a shortcut while someone practices it, without recording anything.
/// Each key cap lights while its key is held; a full press uses the same
/// recognizer as dictation, so what counts here also starts a real dictation.
public struct HotkeyRehearsal: Sendable {
    public let hotkey: Hotkey
    /// Indices into `hotkey.keyCaps` whose keys are currently held.
    public private(set) var litCaps: Set<Int> = []
    public private(set) var completedPresses = 0
    public var isPressed: Bool { press.isDown }

    private var press = HotkeyPressState()
    private var keyIsDown = false
    /// The modifier flag shown by each cap, or nil for the main key or a single modifier key.
    private let capMasks: [UInt64?]

    public init(hotkey: Hotkey) {
        self.hotkey = hotkey
        if hotkey.isModifierOnly && hotkey.modifiers == 0 {
            capMasks = [nil]
        } else {
            let order = [Hotkey.maskSecondaryFn, Hotkey.maskControl, Hotkey.maskAlternate,
                         Hotkey.maskShift, Hotkey.maskCommand]
            capMasks = order.filter { hotkey.modifiers & $0 != 0 } + (hotkey.isModifierOnly ? [] : [nil])
        }
    }

    public mutating func handle(_ event: HotkeyPressState.Event, keyCode: UInt16, flags: UInt64,
                                isRepeat: Bool = false, modifierKeyIsDown: Bool = false) {
        let transition = press.handle(event, hotkey: hotkey, keyCode: keyCode, flags: flags,
                                      isRepeat: isRepeat, modifierKeyIsDown: modifierKeyIsDown).transition
        if transition == .pressed { completedPresses += 1 }
        if !hotkey.isModifierOnly, keyCode == hotkey.keyCode {
            switch event {
            case .keyDown: keyIsDown = true
            case .keyUp: keyIsDown = false
            case .flagsChanged: break
            }
        }
        var lit = Set<Int>()
        for (index, mask) in capMasks.enumerated() {
            if let mask {
                if flags & mask != 0 { lit.insert(index) }
            } else if hotkey.isModifierOnly ? press.isDown : keyIsDown {
                lit.insert(index)
            }
        }
        litCaps = lit
    }

    /// Clears held keys when the window loses focus or monitoring stops.
    public mutating func reset() {
        _ = press.reset()
        keyIsDown = false
        litCaps = []
    }
}
