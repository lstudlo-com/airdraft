import AirdraftCore
import SwiftUI

/// The app's shared type scale. Base sizes are the design sizes; Settings > Appearance >
/// Text size multiplies all of them, because macOS does not apply Dynamic Type to
/// SwiftUI text styles (`Font.body` stays 13 pt at every `dynamicTypeSize`).
/// Views use `.appFont(_:)` instead of `.font(.system(size:))`. Symbols keep fixed
/// point sizes unless they must align with scaled text; the recording HUD and the
/// native menu are not scaled.
enum TextStyle: CaseIterable, Sendable {
    /// 25 pt semibold: onboarding step titles.
    case display
    /// 23 pt semibold rounded: Home headline values and the meeting timer.
    case metric
    /// 20 pt semibold: large sheet titles.
    case sheetTitle
    /// 18 pt semibold: page titles and sheet titles.
    case title
    /// 17 pt semibold: the License headline.
    case headline
    /// 16 pt: compact statistics and illustration glyphs.
    case statistic
    /// 15 pt: emphasized onboarding values.
    case emphasis
    /// 14 pt semibold: section headings.
    case heading
    /// 14 pt: dictation transcripts in History and Home.
    case transcript
    /// 13 pt: setting titles, body copy and list rows.
    case body
    /// 12.5 pt medium: soft buttons, menus and filters.
    case control
    /// 12 pt: secondary rows, links and segmented choices.
    case detail
    /// 11.5 pt: compact secondary labels and key caps.
    case annotation
    /// 11 pt: descriptions (`.supportingText()`).
    case supporting
    /// 10.5 pt: waveform period labels.
    case caption
    /// 10 pt: timestamps, eyebrow labels and small badges.
    case caption2
    /// 9.5 pt semibold: pill tags.
    case tag
    /// 12 pt monospaced: prompts and code.
    case mono

    var size: CGFloat {
        switch self {
        case .display: return 25
        case .metric: return 23
        case .sheetTitle: return 20
        case .title: return 18
        case .headline: return 17
        case .statistic: return 16
        case .emphasis: return 15
        case .heading, .transcript: return 14
        case .body: return 13
        case .control: return 12.5
        case .detail, .mono: return 12
        case .annotation: return 11.5
        case .supporting: return 11
        case .caption: return 10.5
        case .caption2: return 10
        case .tag: return 9.5
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .metric, .sheetTitle, .title, .headline, .heading, .tag: return .semibold
        case .control: return .medium
        default: return .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .metric: return .rounded
        case .mono: return .monospaced
        default: return .default
        }
    }

    func font(scale: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: Self.scaled(size, by: scale), weight: weight ?? self.weight, design: design ?? self.design)
    }

    static func scaled(_ size: CGFloat, by scale: CGFloat) -> CGFloat {
        scale == 1 ? size : (size * scale).rounded(toPlaces: 1)
    }

    /// The AppKit equivalent, for native text views measured outside SwiftUI.
    func nsFont(scale: CGFloat) -> NSFont {
        .systemFont(ofSize: Self.scaled(size, by: scale))
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let factor = pow(10, CGFloat(places))
        return (self * factor).rounded() / factor
    }
}

extension EnvironmentValues {
    /// Multiplier from Settings > Appearance > Text size. 1 keeps the design sizes.
    @Entry var textScale: CGFloat = 1
}

extension TextSizePreference {
    var title: String {
        switch self {
        case .standard: return String(localized: "Default")
        case .large: return String(localized: "Large", comment: "Text size")
        case .larger: return String(localized: "Larger", comment: "Text size")
        }
    }

    /// The user's choice, or the system's larger Dynamic Type size if SwiftUI ever
    /// reports one on macOS (it reports `.large` by default and does not scale fonts).
    func effectiveScale(system: DynamicTypeSize) -> CGFloat {
        let systemScale: CGFloat = system >= .xxLarge ? 1.24 : system >= .xLarge ? 1.12 : 1
        return Swift.max(CGFloat(scale), systemScale)
    }
}

private struct AppFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: TextStyle.scaled(size, by: scale), weight: weight, design: design))
    }
}

/// Publishes the effective text scale and scales text that uses the default font.
/// At the default size the environment font stays unset, exactly as before.
private struct TextSizeEnvironment: ViewModifier {
    let preference: TextSizePreference
    @Environment(\.dynamicTypeSize) private var system

    func body(content: Content) -> some View {
        let scale = preference.effectiveScale(system: system)
        content
            .environment(\.textScale, scale)
            .font(scale == 1 ? nil : TextStyle.body.font(scale: scale))
    }
}

extension View {
    /// A shared text style at the user's text size.
    func appFont(_ style: TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(AppFont(size: style.size, weight: weight ?? style.weight, design: design ?? style.design))
    }

    /// A one-off size inside an illustration that still follows the user's text size.
    /// Prefer a `TextStyle`; this exists for proportional artwork such as key caps.
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFont(size: size, weight: weight, design: design))
    }

    /// The saved preference, or a render's override. Sheets inherit it from their presenter.
    func textSize(from settings: AppSettings) -> some View {
        textSize(RenderMode.textSize ?? settings.textSize)
    }

    /// Apply at each window or sheet root that should follow the Text size setting.
    func textSize(_ preference: TextSizePreference) -> some View {
        modifier(TextSizeEnvironment(preference: preference))
    }
}
