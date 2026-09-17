import Foundation

/// A global hotkey: either a key plus modifiers (⌥ Space) or a single modifier
/// key on its own (Right ⌥, fn), which is the most comfortable hold-to-talk key.
public struct Hotkey: Codable, Sendable, Equatable, Hashable {
    /// Virtual key code (kVK_*). For modifier-only hotkeys this is the modifier key itself.
    public var keyCode: UInt16
    /// CGEventFlags raw value masked to ⌘ ⌥ ⌃ ⇧ fn. Zero for modifier-only hotkeys.
    public var modifiers: UInt64
    public var isModifierOnly: Bool

    public init(keyCode: UInt16, modifiers: UInt64 = 0, isModifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Hotkey.relevantModifierMask
        self.isModifierOnly = isModifierOnly
    }

    /// ⌥ Space, the default. Works through Carbon without any permission.
    public static let optionSpace = Hotkey(keyCode: 49, modifiers: Hotkey.maskAlternate)
    public static let escape = Hotkey(keyCode: 53)

    // Device-independent CGEventFlags bits (identical to NSEvent.ModifierFlags).
    public static let maskShift: UInt64 = 1 << 17
    public static let maskControl: UInt64 = 1 << 18
    public static let maskAlternate: UInt64 = 1 << 19
    public static let maskCommand: UInt64 = 1 << 20
    public static let maskSecondaryFn: UInt64 = 1 << 23
    public static let relevantModifierMask: UInt64 = maskShift | maskControl | maskAlternate | maskCommand | maskSecondaryFn

    /// The flag bit toggled by a modifier key code, or nil for non-modifier keys.
    public static func modifierFlag(for keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case 54, 55: return maskCommand
        case 58, 61: return maskAlternate
        case 59, 62: return maskControl
        case 56, 60: return maskShift
        case 63: return maskSecondaryFn
        default: return nil
        }
    }

    /// One label per key cap, modifiers first: ["⌥", "Space"] or ["Right ⌥"].
    public var keyCaps: [String] {
        if isModifierOnly { return [Hotkey.modifierKeyName(keyCode)] }
        var caps: [String] = []
        if modifiers & Hotkey.maskSecondaryFn != 0 { caps.append("fn") }
        if modifiers & Hotkey.maskControl != 0 { caps.append("⌃") }
        if modifiers & Hotkey.maskAlternate != 0 { caps.append("⌥") }
        if modifiers & Hotkey.maskShift != 0 { caps.append("⇧") }
        if modifiers & Hotkey.maskCommand != 0 { caps.append("⌘") }
        caps.append(Hotkey.keyName(keyCode))
        return caps
    }

    public var displayString: String { keyCaps.joined(separator: " ") }

    public static func modifierKeyName(_ code: UInt16) -> String {
        switch code {
        case 54: return "Right ⌘"
        case 55: return "Left ⌘"
        case 58: return "Left ⌥"
        case 61: return "Right ⌥"
        case 59: return "Left ⌃"
        case 62: return "Right ⌃"
        case 56: return "Left ⇧"
        case 60: return "Right ⇧"
        case 63: return "fn"
        default: return "Key \(code)"
        }
    }

    public static func keyName(_ code: UInt16) -> String {
        if let n = keyNames[code] { return n }
        return "Key \(code)"
    }

    private static let keyNames: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]
}
