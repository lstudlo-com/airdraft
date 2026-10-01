import SwiftUI

/// Home's neutral material, scaled down for controls and instrument tracks.
/// Light falls from the top left; wells reverse the same light and shade.
private struct NeumorphicPalette {
    let top, bottom, well, light, shade: Color

    init(dark: Bool, translucent: Bool, prominent: Bool) {
        if prominent {
            top = Color(white: dark ? 0.70 : 0.68)
            bottom = Color(white: dark ? 0.46 : 0.44)
            light = .white.opacity(dark ? 0.38 : 0.85)
            shade = .black.opacity(dark ? 0.80 : 0.40)
        } else if translucent {
            // A softer microphone well: the same light and shade, about two-thirds as strong.
            top = .white.opacity(dark ? 0.11 : 0.28)
            bottom = .white.opacity(dark ? 0.035 : 0.10)
            light = .white.opacity(dark ? 0.07 : 0.80)
            shade = .black.opacity(dark ? 0.42 : 0.18)
        } else {
            top = Color(white: dark ? 0.34 : 0.97)
            bottom = Color(white: dark ? 0.22 : 0.80)
            light = .white.opacity(dark ? 0.09 : 1)
            shade = .black.opacity(dark ? 0.75 : 0.28)
        }
        // Translucent wells move toward the microphone's opaque well: lighter in light mode, darker in dark.
        well = translucent ? (dark ? Color.black.opacity(0.22) : Color.white.opacity(0.22))
            : Color(white: dark ? 0.14 : 0.90)
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
    /// Stronger neutral faces and edges for the small sidebar brand.
    var prominent = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let glass = translucent && !reduceTransparency
        let palette = NeumorphicPalette(dark: scheme == .dark, translucent: glass, prominent: prominent)
        Group {
            if inset && glass {
                shape.fill(palette.well).overlay {
                    SurfaceShadows(shape: shape, shadows: [
                        .init(color: palette.shade, radius: depth * 1.5, x: depth, y: depth),
                        .init(color: palette.light, radius: depth * 1.5, x: -depth, y: -depth),
                    ], inner: true)
                }
            } else if inset {
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
                colors: inset ? [palette.shade.opacity(0.3), palette.light]
                    : [palette.light, palette.shade.opacity(prominent ? 0.65 : 0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: prominent && outlineOnly ? 1 : 0.75)
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

        var body: some View {
            label
                .background {
                    NeumorphicSurface(shape: Capsule(), inset: true, depth: 2.5)
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
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
