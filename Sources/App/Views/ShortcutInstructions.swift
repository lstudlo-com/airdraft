import AirdraftCore
import SwiftUI

/// A translated sentence with the shortcut's key caps inside it. The catalog holds the
/// whole sentence with one `%@` where the caps go, so translators choose the word
/// order (Japanese and Hindi put the verb after the keys); the view splits it there.
struct KeyCapsSentence: Equatable {
    /// Stands in for the key caps until the resolved sentence is split around it.
    static let marker = "\u{FFFC}"

    let before: String
    let after: String

    init(_ resolved: String) {
        if let range = resolved.range(of: Self.marker) {
            before = resolved[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            after = resolved[range.upperBound...].trimmingCharacters(in: .whitespaces)
        } else {
            before = resolved
            after = ""
        }
    }

    /// The sentence as plain text, with the keys named in words for VoiceOver.
    func spelled(_ keys: String) -> String {
        [before, keys, after].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// One instruction with key caps drawn inline. It stays on one line when that fits;
/// otherwise the text after the caps wraps on the following lines, so no part of a
/// translation is truncated and the caps stay visible (practice lights them).
struct KeyCapsSentenceView<Caps: View>: View {
    let sentence: KeyCapsSentence
    /// The keys as VoiceOver should read them.
    let spokenKeys: String
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 6
    @ViewBuilder var caps: Caps

    init(_ resolved: String, spokenKeys: String, alignment: HorizontalAlignment = .leading,
         spacing: CGFloat = 6, @ViewBuilder caps: () -> Caps) {
        sentence = KeyCapsSentence(resolved)
        self.spokenKeys = spokenKeys
        self.alignment = alignment
        self.spacing = spacing
        self.caps = caps()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                if !sentence.before.isEmpty { Text(sentence.before) }
                caps
                if !sentence.after.isEmpty { Text(sentence.after) }
            }
            .fixedSize()
            VStack(alignment: alignment, spacing: 4) {
                HStack(spacing: spacing) {
                    if !sentence.before.isEmpty {
                        Text(sentence.before).fixedSize(horizontal: false, vertical: true)
                    }
                    caps
                }
                if !sentence.after.isEmpty {
                    Text(sentence.after).fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence.spelled(spokenKeys))
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Every shortcut instruction as a complete sentence per gesture. `keys` is the
/// key-caps marker, or the shortcut spelled out where the sentence is plain text.
enum ShortcutCopy {
    private static var keys: String { KeyCapsSentence.marker }

    /// Home's overview before the first dictation, with the caps inline.
    static func overviewInvitation(_ gesture: HotkeyGesture) -> String {
        switch gesture {
        case .hold:
            String(localized: "Hold \(keys) and speak. Each dictation adds a bar.",
                   comment: "%@ is the shortcut, drawn as key caps")
        case .press:
            String(localized: "Press \(keys) and speak. Each dictation adds a bar.",
                   comment: "%@ is the shortcut, drawn as key caps")
        case .holdThenPress:
            String(localized: "Hold \(keys) to start, then speak. Each dictation adds a bar.",
                   comment: "%@ is the shortcut, drawn as key caps. Toggle with a trigger delay: hold to start, press to stop")
        }
    }

    /// The practice card's instruction under the sentence to read, with the caps inline.
    static func practiceInstruction(_ gesture: HotkeyGesture) -> String {
        switch gesture {
        case .hold:
            String(localized: "Hold \(keys) and speak. Let go to insert.",
                   comment: "%@ is the shortcut, drawn as key caps")
        case .press:
            String(localized: "Press \(keys) and speak. Press again to insert.",
                   comment: "%@ is the shortcut, drawn as key caps")
        case .holdThenPress:
            String(localized: "Hold \(keys) to start, then speak. Press again to insert.",
                   comment: "%@ is the shortcut, drawn as key caps. Toggle with a trigger delay: hold to start, press to stop")
        }
    }

    /// Home's compact readiness hint beside the caps: "Hold ⌃ ⌥".
    static func shortcutHint(_ gesture: HotkeyGesture) -> String {
        gesture.startsByHolding
            ? String(localized: "Hold \(keys)", comment: "Short hint; %@ is the shortcut, drawn as key caps")
            : String(localized: "Press \(keys)", comment: "Short hint; %@ is the shortcut, drawn as key caps")
    }

    /// The menu's tooltip, with the shortcut spelled in symbols.
    static func menuHelp(_ gesture: HotkeyGesture, shortcut: String) -> String {
        gesture.startsByHolding
            ? String(localized: "Hold \(shortcut) to dictate.", comment: "Menu tooltip; %@ is the shortcut, such as ⌃ ⌥")
            : String(localized: "Press \(shortcut) to dictate.", comment: "Menu tooltip; %@ is the shortcut, such as ⌃ ⌥")
    }

    /// The shortcut step's prompt, with the keys named in words ("Control and Option").
    static func rehearsalPrompt(_ gesture: HotkeyGesture, keyNames: String, together: Bool) -> String {
        switch (gesture.startsByHolding, together) {
        case (true, true):
            String(localized: "Hold \(keyNames) together.", comment: "%@ names two or more keys, such as Control and Option")
        case (true, false):
            String(localized: "Hold \(keyNames).", comment: "%@ names one key, such as Right Option")
        case (false, true):
            String(localized: "Press \(keyNames) together.", comment: "%@ names two or more keys, such as Control and Option")
        case (false, false):
            String(localized: "Press \(keyNames).", comment: "%@ names one key, such as Right Option")
        }
    }

    /// The empty practice box once it has focus.
    static func practicePlaceholder(_ gesture: HotkeyGesture) -> String {
        switch gesture {
        case .hold: String(localized: "Now hold your shortcut and speak.")
        case .press: String(localized: "Now press your shortcut and speak.")
        case .holdThenPress: String(localized: "Now hold your shortcut to start, then speak.")
        }
    }

    /// The practice step's subtitle before the first dictation.
    static func practiceSubtitle(_ gesture: HotkeyGesture) -> String {
        gesture.startsByHolding
            ? String(localized: "Click in the box below, hold your shortcut and read the sentence aloud.")
            : String(localized: "Click in the box below, press your shortcut and read the sentence aloud.")
    }

    /// Welcome's first beat.
    static func welcomeFirstBeat(_ behavior: HotkeyBehavior) -> String {
        behavior == .hold ? String(localized: "Hold your shortcut") : String(localized: "Press your shortcut")
    }

    /// Welcome's three beats for VoiceOver, with the keys named in words.
    static func welcomeDescription(_ behavior: HotkeyBehavior, keyNames: String) -> String {
        behavior == .hold
            ? String(localized: "Hold \(keyNames), speak, then let go. Your words appear where you were typing.",
                     comment: "%@ names the shortcut's keys, such as Control and Option")
            : String(localized: "Press \(keyNames), speak, then press again. Your words appear where you were typing.",
                     comment: "%@ names the shortcut's keys, such as Control and Option")
    }
}
