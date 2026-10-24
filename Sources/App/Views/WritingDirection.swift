import AppKit
import SwiftUI

/// Writing direction of user content, independent of the interface's layout direction.
/// A transcript, name or URL typed in English stays left aligned in an Arabic interface,
/// and Arabic text stays right aligned in an English one; text without letters follows
/// the interface.
enum WritingDirection {
    /// The direction of the first strong (letter) character, as Unicode's paragraph
    /// rules decide it, or nil when the text has none.
    nonisolated static func of(_ text: String) -> LayoutDirection? {
        for scalar in text.unicodeScalars {
            if isRightToLeft(scalar) { return .rightToLeft }
            if scalar.properties.isAlphabetic { return .leftToRight }
        }
        return nil
    }

    /// Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic and their presentation
    /// forms, plus the historic right-to-left blocks of the supplementary planes.
    nonisolated static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF:
            // Letters only: marks and digits in these blocks do not set the direction.
            return scalar.properties.isAlphabetic
        default:
            return false
        }
    }

    /// AppKit's paragraph direction for the text, natural when it has no letters.
    nonisolated static func paragraphDirection(of text: String) -> NSWritingDirection {
        switch of(text) {
        case .rightToLeft: .rightToLeft
        case .leftToRight: .leftToRight
        case nil: .natural
        @unknown default: .natural
        }
    }

    /// Wraps text in a first-strong isolate so neighbouring separators and arrows keep
    /// their order around it in either direction (U+2068 … U+2069).
    nonisolated static func isolated(_ text: String) -> String { "\u{2068}\(text)\u{2069}" }

    /// Wraps text in a left-to-right isolate (U+2066 … U+2069): a media clock such as
    /// "0:12 / 1:05" has no letters, so a right-to-left paragraph would swap its two times.
    nonisolated static func leftToRight(_ text: String) -> String { "\u{2066}\(text)\u{2069}" }
}

extension View {
    /// Aligns read-only user content by its own writing direction ("natural" alignment):
    /// leading and trailing inside follow the text, not the interface; text without
    /// letters keeps the interface direction. Not for text fields: AppKit aligns a field
    /// to the interface whatever this environment says, and changing a field's alignment
    /// while it is edited disturbs its field editor (Settings search lost its arrow keys).
    func naturalAlignment(for text: String) -> some View {
        modifier(NaturalAlignment(direction: WritingDirection.of(text)))
    }
}

private struct NaturalAlignment: ViewModifier {
    let direction: LayoutDirection?
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content.environment(\.layoutDirection, direction ?? layoutDirection)
    }
}
