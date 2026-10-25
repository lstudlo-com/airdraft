import AirdraftCore
import AppKit
import SwiftUI

/// A key cap at practice size. Raised at rest; held, it sinks into a well like a pressed
/// soft button, so the user sees the real key go down on screen.
struct OnboardingKeyCap: View {
    let text: String
    var pressed = false
    var size: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        let word = size >= 38 ? OnboardingKeyNames.capWord(text) : nil
        // Like the printing on a Mac keyboard: the symbol, with the key's name beneath it.
        VStack(spacing: size * 0.04) {
            Text(word == nil ? text : OnboardingKeyNames.symbol(text))
                .font(.system(size: text.count > 2 && word == nil ? size * 0.26 : size * (word == nil ? 0.4 : 0.32),
                              weight: .medium, design: .rounded))
            if let word {
                Text(word).font(.system(size: max(9, size * 0.17), weight: .medium, design: .rounded))
                    .foregroundStyle(pressed ? Color.accentColor : .secondary)
            }
        }
        .lineLimit(1)
        // A cap is as wide as its printed name, never truncated to fit a narrow
        // column: "control" must read in full beside its symbol.
        .fixedSize()
        .foregroundStyle(pressed ? Color.accentColor : .primary)
        .padding(.horizontal, size * 0.2)
        .frame(minWidth: size, minHeight: size)
        .background { NeumorphicSurface(shape: shape, inset: pressed, depth: pressed ? size * 0.05 : size * 0.06) }
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
    }
}

/// Plain names for shortcut keys, so nobody has to know what ⌃ or ⌥ means.
enum OnboardingKeyNames {
    private static let words = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command", "fn": "fn"]

    /// The small word printed on a modifier cap, or nil for ordinary keys.
    static func capWord(_ cap: String) -> String? {
        let parts = cap.split(separator: " ").map(String.init)
        guard let symbol = parts.last, let word = words[symbol] else { return nil }
        // The side word is localized ("右 option"); the key's own name stays as printed.
        return parts.count > 1 ? Hotkey.displayCap("\(parts[0]) \(word)").lowercased(with: .current) : word
    }

    static func symbol(_ cap: String) -> String {
        let symbol = cap.split(separator: " ").last.map(String.init) ?? cap
        return symbol == "fn" ? "🌐︎" : symbol
    }

    /// "Control and Option", "Option and Space", "Right Option". Key names stay as printed
    /// on Mac keyboards; only the joining words are localized.
    static func spoken(_ hotkey: Hotkey) -> String {
        let names = hotkey.keyCaps.map { cap in capWord(cap).map { $0.capitalized(with: .current) } ?? cap }
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        let head = names.dropLast().joined(separator: String(localized: "KeyNameSeparator", defaultValue: ", ",
                                                              comment: "Between key names in a list of three or more"))
        return String(localized: "\(head) and \(last)", comment: "Key names, e.g. Control and Option")
    }
}

/// The shortcut as practice key caps. Lit caps follow the keys actually held.
struct OnboardingKeyCaps: View {
    let hotkey: Hotkey
    var lit: Set<Int> = []
    var size: CGFloat = 56
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        // Modifiers precede the key as printed on the keyboard, in every language.
        HStack(spacing: size * 0.22) {
            ForEach(Array(hotkey.keyCaps.enumerated()), id: \.offset) { index, cap in
                OnboardingKeyCap(text: cap, pressed: lit.contains(index), size: size)
                    .environment(\.layoutDirection, layoutDirection)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(OnboardingKeyNames.spoken(hotkey))")
        .accessibilityValue(lit.isEmpty ? Text("Not pressed") : lit.count == hotkey.keyCaps.count ? Text("Pressed") : Text("Partly pressed"))
        .accessibilityAddTraits(.isImage)
    }
}

/// Welcome's three beats: hold the shortcut, speak, let go and read. One loop, so a
/// first-time user sees the whole gesture before being asked to perform it.
struct OnboardingWelcomeDemo: View {
    let hotkey: Hotkey
    let behavior: HotkeyBehavior
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var sentence: String { String(localized: "Running late. See you at ten!") }
    private static let cycle: Double = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || RenderMode.isActive)) { context in
            let t = reduceMotion || RenderMode.isActive ? 5.4 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle)
            let beat = t < 1.4 ? 0 : t < 3.6 ? 1 : 2
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                panel(1, title: ShortcutCopy.welcomeFirstBeat(behavior), active: beat == 0 || reduceMotion) {
                    OnboardingKeyCaps(hotkey: hotkey, lit: t > 0.4 && t < 3.8 ? Set(hotkey.keyCaps.indices) : [], size: 38)
                }
                panel(2, title: String(localized: "Speak naturally"), active: beat == 1 || reduceMotion) {
                    OnboardingSpeechBars(time: t, speaking: t > 1.4 && t < 3.6 || reduceMotion || RenderMode.isActive)
                }
                panel(3, title: behavior == .hold ? String(localized: "Let go. Your words appear.") : String(localized: "Press again. Your words appear."),
                      active: beat == 2 || reduceMotion) {
                    let count = Int(min(1, max(0, (t - 3.7) / 1.3)) * Double(Self.sentence.count))
                    OnboardingTypedLine(text: String(Self.sentence.prefix(count)), caret: beat == 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShortcutCopy.welcomeDescription(behavior, keyNames: OnboardingKeyNames.spoken(hotkey)))
        .accessibilityAddTraits(.isImage)
    }

    private func panel<Content: View>(_ number: Int, title: String, active: Bool,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 64)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number)")
                    .appFont(.supporting, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background { NeumorphicSurface(shape: Circle(), inset: true, depth: 1.2) }
                Text(title)
                    .appFont(.detail, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(active ? 1 : 0.42)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: active)
    }
}

/// Raised bars in a recessed well, like Home's waveform, moving while someone speaks.
private struct OnboardingSpeechBars: View {
    let time: Double
    let speaking: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<9, id: \.self) { index in
                let wave = speaking ? 0.5 + 0.5 * sin(time * 7 + Double(index) * 0.9) * cos(time * 2.3 + Double(index)) : 0
                OnboardingBar(height: 6 + 24 * abs(wave))
            }
        }
        // Audio flows left to right in every language, like the recording window.
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 44)
        .padding(.horizontal, 14)
        .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), inset: true, depth: 2) }
    }
}

private struct OnboardingBar: View {
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Capsule()
            .fill(LinearGradient(colors: [Color(white: dark ? 0.62 : 0.6), Color(white: dark ? 0.46 : 0.46)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: height)
            .background {
                SurfaceShadows(shape: Capsule(), shadows: [
                    .init(color: .black.opacity(dark ? 0.5 : 0.22), radius: 1, x: 0.6, y: 0.8),
                    .init(color: .white.opacity(dark ? 0.08 : 0.9), radius: 1, x: -0.5, y: -0.6),
                ])
            }
    }
}

/// A one-line text field mock that fills as the sentence arrives.
private struct OnboardingTypedLine: View {
    let text: String
    let caret: Bool

    var body: some View {
        HStack(spacing: 1) {
            Text(text.isEmpty ? " " : text)
                .appFont(.annotation)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if caret {
                Rectangle().fill(Color.accentColor).frame(width: 1.5, height: 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous), inset: true, depth: 1.5) }
    }
}

/// Live input level as recent history in Home's well: you see your own voice move it.
struct OnboardingVoiceWell: View {
    let level: Float
    private static let count = 40
    // Renders show a representative phrase; live use starts silent.
    @State private var samples: [Float] = RenderMode.isActive
        ? (0..<count).map { Float(0.15 + 0.6 * abs(sin(Double($0) * 0.55) * cos(Double($0) * 0.17))) }
        : Array(repeating: 0, count: count)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(samples.indices, id: \.self) { index in
                OnboardingBar(height: 5 + 30 * CGFloat(min(1, max(0, samples[index]))))
                    .frame(maxWidth: .infinity)
            }
        }
        // The newest level enters at the right in every language, like the recording window.
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), inset: true, depth: 2.2) }
        .onChange(of: level) { _, value in
            samples.removeFirst()
            samples.append(value.isFinite ? value : 0)
        }
        .levelMeterAccessibility(String(localized: "Microphone level"), level: level)
    }
}

/// Where the Accessibility switch is, drawn in the app's own material: the row a
/// first-time user looks for in System Settings, with its switch turning on.
struct OnboardingAccessibilitySwitch: View {
    let granted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: granted || reduceMotion || RenderMode.isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3)
            let on = granted || reduceMotion || RenderMode.isActive || t > 1.4
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text("Airdraft").appFont(.body)
                Spacer(minLength: 12)
                ZStack(alignment: on ? .trailing : .leading) {
                    SoftInsetTrack(shape: Capsule())
                    Capsule().fill(Color.accentColor.opacity(0.85)).padding(1.5).opacity(on ? 1 : 0)
                    SoftRaisedSurface(shape: Circle()).frame(width: 18, height: 18).padding(2)
                }
                .frame(width: 38, height: 22)
                .clipShape(Capsule())
                .animation(reduceMotion ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.2), value: on)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous), inset: true, depth: 1.5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In System Settings, turn on the switch next to Airdraft")
        .accessibilityAddTraits(.isImage)
    }
}

/// One of two large choices. Selection reads as an accent ring and check, never color fill.
struct OnboardingChoiceCard: View {
    let title: LocalizedStringResource
    let symbol: String
    var badge: LocalizedStringResource? = nil
    let points: [LocalizedStringResource]
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .frame(width: 30, height: 30)
                        .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 9, style: .continuous), inset: true, depth: 1.5) }
                    Text(title).appFont(.heading)
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                if let badge { PillTag(verbatim: String(localized: badge).uppercased()) }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(points.indices, id: \.self) { index in
                        Text(points[index]).supportingText().fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(shape)
            .background { SoftRaisedSurface(shape: shape, elevation: .card) }
            .overlay { shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
