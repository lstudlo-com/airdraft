import SwiftUI

/// Home's neutral material, scaled down for controls and instrument tracks.
/// Light falls from the top left; wells reverse the same light and shade.
private struct NeumorphicPalette {
    let top, bottom, well, light, shade: Color

    init(dark: Bool, translucent: Bool) {
        if translucent {
            top = .white.opacity(dark ? 0.11 : 0.28)
            bottom = .white.opacity(dark ? 0.035 : 0.10)
            light = .white.opacity(dark ? 0.20 : 0.65)
            shade = .black.opacity(dark ? 0.28 : 0.12)
        } else {
            top = Color(white: dark ? 0.34 : 0.97)
            bottom = Color(white: dark ? 0.22 : 0.80)
            light = .white.opacity(dark ? 0.09 : 1)
            shade = .black.opacity(dark ? 0.75 : 0.28)
        }
        well = translucent ? .black.opacity(dark ? 0.12 : 0.06) : Color(white: dark ? 0.14 : 0.90)
    }
}

struct NeumorphicSurface<S: InsettableShape>: View {
    let shape: S
    var inset = false
    var depth: CGFloat = 2
    /// Sidebar accents share the blur already supplied by the sidebar, including inset wells.
    var translucent = false
    /// A raised rim with an empty center, used by the sidebar brand.
    var outlineOnly = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let glass = translucent && !reduceTransparency
        let palette = NeumorphicPalette(dark: scheme == .dark, translucent: glass)
        Group {
            if inset {
                shape.fill(palette.well
                    .shadow(.inner(color: palette.shade, radius: depth * 1.5, x: depth, y: depth))
                    .shadow(.inner(color: palette.light, radius: depth * 1.5, x: -depth, y: -depth)))
            } else {
                shape.fill(LinearGradient(colors: [palette.top, palette.bottom],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(outlineOnly ? 0 : 1)
                    .background {
                        SurfaceShadows(shape: shape, shadows: [
                            .init(color: palette.shade.opacity(0.65), radius: depth, x: depth * 0.6, y: depth),
                            .init(color: palette.light, radius: depth, x: -depth * 0.5, y: -depth * 0.7),
                        ], excludesInterior: glass || outlineOnly)
                    }
            }
        }
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: inset ? [palette.shade.opacity(0.3), palette.light] : [palette.light, palette.shade.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Used only by the sidebar microphone capsule, not every action button.
struct MicrophoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(label: configuration.label)
    }

    private struct CapsuleBody: View {
        let label: ButtonStyleConfiguration.Label
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            label
                .background {
                    NeumorphicSurface(shape: Capsule(), inset: !hovering || !isEnabled, depth: 2.5)
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

/// A shallow inset for Home's proportional app-usage bars.
struct NeumorphicUsageTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
            let width = max(0, geometry.size.width - 2) * value
            ZStack(alignment: .leading) {
                NeumorphicSurface(shape: Capsule(), inset: true, depth: 1.2)
                if value > 0 {
                    Capsule()
                        .fill(Brand.violet)
                        .frame(width: width, height: 5)
                        .padding(.horizontal, 1)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
