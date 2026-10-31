import SwiftUI

/// The Mac app's neutral neumorphism, translated value for value (see
/// `Sources/App/Views/Theme.swift` and `SoftControls.swift`; DESIGN.md says
/// which values must change together). Only the content layer uses it: tab
/// bars, navigation bars and sheets stay the system's Liquid Glass.
enum MobileTheme {
    /// The page surface every raised card rises from: the Mac island's mid-tone.
    static let background = Color(uiColor: UIColor { traits in
        UIColor(white: traits.userInterfaceStyle == .dark ? 0.15 : 0.90, alpha: 1)
    })
    static let cardRadius: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let pagePadding: CGFloat = 16
    /// The smallest comfortable touch target.
    static let touchTarget: CGFloat = 44
    static let controlRadius: CGFloat = 12
    static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: cardRadius, style: .continuous) }
    static var controlShape: RoundedRectangle { RoundedRectangle(cornerRadius: controlRadius, style: .continuous) }
}

/// How far a raised surface casts its light and shade (`SoftElevation` on the Mac).
enum MobileElevation {
    case card
    case control
    /// Home's record key, the one large control.
    case hero

    var scale: CGFloat {
        switch self {
        case .card: 0.5
        case .control: 0.25
        case .hero: 0.75
        }
    }
}

/// The Mac `SoftRaisedSurface`: a flat face lit from the top left, a highlight
/// up-left and a shade down-right. Pressed, it sinks into a well.
struct MobileRaisedSurface<S: InsettableShape>: View {
    let shape: S
    var elevation: MobileElevation = .control
    var pressed = false
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        let spread = elevation.scale
        let shade = Color.black.opacity(dark ? 0.525 : 0.27)
        let light = Color.white.opacity(dark ? 0.09 : 1)
        let face: CGFloat = switch (elevation, dark) {
        case (.card, false): 0.90
        case (.card, true): 0.18
        case (_, false): 0.91
        case (_, true): 0.2
        }
        let rim = Color.white.opacity(dark ? 0.024 : 0.135)
        Group {
            if pressed {
                shape.fill((tint ?? Color(white: dark ? 0.15 : 0.87))
                    .shadow(.inner(color: shade, radius: 12 * spread, x: 7 * spread, y: 9 * spread))
                    .shadow(.inner(color: light, radius: 12 * spread, x: -6 * spread, y: -7 * spread)))
            } else {
                shape.fill(tint ?? Color(white: face))
            }
        }
        .overlay {
            if !pressed {
                shape.strokeBorder(LinearGradient(colors: [rim, rim.opacity(0)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.0175), lineWidth: 0.5)
        }
        .drawingGroup()
        .background {
            if !pressed {
                SurfaceShadows(shape: shape, shadows: [
                    .init(color: shade, radius: 12 * spread, x: 7 * spread, y: 9 * spread),
                    .init(color: light, radius: 12 * spread, x: -6 * spread, y: -7 * spread),
                ])
            }
        }
        .physicalLight()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A raised section card (`SettingsCard` on the Mac): equal 16-point insets, 18-point corners.
struct SoftCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { MobileRaisedSurface(shape: MobileTheme.cardShape, elevation: .card) }
    }
}

/// A sentence-case section title with its card below.
struct SoftSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            SoftCard { content }
        }
    }
}

/// The only separator inside cards: an engraved groove, shade over highlight.
struct RowDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(dark ? 0.45 : 0.12)).frame(height: 0.5)
            Rectangle().fill(Color.white.opacity(dark ? 0.06 : 0.8)).frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Raised buttons that sink into a well while pressed. Prominent buttons fill
/// with the system accent and keep the same geometry.
struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    /// Compact buttons size to their label, for actions at a row's trailing edge.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(configuration: configuration, prominent: prominent, compact: compact)
    }

    private struct SoftButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, compact ? 14 : 16)
                .frame(minHeight: compact ? 36 : MobileTheme.touchTarget)
                .frame(maxWidth: compact ? nil : .infinity)
                .background {
                    MobileRaisedSurface(shape: MobileTheme.controlShape, elevation: .control,
                                        pressed: configuration.isPressed,
                                        tint: prominent ? Color.accentColor : nil)
                }
                // A compact button keeps the full touch target around its smaller face.
                .padding(.vertical, compact ? 4 : 0)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
    static var softProminent: SoftButtonStyle { SoftButtonStyle(prominent: true) }
    static var softCompact: SoftButtonStyle { SoftButtonStyle(compact: true) }
    static var softCompactProminent: SoftButtonStyle { SoftButtonStyle(prominent: true, compact: true) }
}

/// Pages scroll over the island's mid-tone; the system bars float above it.
struct SoftPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.sectionSpacing) { content }
                .padding(.horizontal, MobileTheme.pagePadding)
                .padding(.vertical, 20)
        }
        .scrollContentBackground(.hidden)
        .background(MobileTheme.background.ignoresSafeArea())
    }
}
