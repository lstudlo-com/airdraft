import SwiftUI

/// Home's neutral material, scaled down for controls and instrument tracks.
/// Light falls from the top left; wells reverse the same light and shade.
private struct NeumorphicPalette {
    let top, bottom, well, light, shade: Color

    init(dark: Bool) {
        top = Color(white: dark ? 0.34 : 0.97)
        bottom = Color(white: dark ? 0.22 : 0.80)
        light = .white.opacity(dark ? 0.09 : 1)
        shade = .black.opacity(dark ? 0.75 : 0.28)
        well = Color(white: dark ? 0.14 : 0.90)
    }
}

struct NeumorphicSurface<S: InsettableShape>: View {
    let shape: S
    var inset = false
    var depth: CGFloat = 2

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = NeumorphicPalette(dark: scheme == .dark)
        Group {
            if inset {
                shape.fill(palette.well
                    .shadow(.inner(color: palette.shade, radius: depth * 1.5, x: depth, y: depth))
                    .shadow(.inner(color: palette.light, radius: depth * 1.5, x: -depth, y: -depth)))
            } else {
                shape.fill(LinearGradient(colors: [palette.top, palette.bottom],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background {
                        SurfaceShadows(shape: shape, shadows: [
                            .init(color: palette.shade.opacity(0.65), radius: depth, x: depth * 0.6, y: depth),
                            .init(color: palette.light, radius: depth, x: -depth * 0.5, y: -depth * 0.7),
                        ])
                    }
            }
        }
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: inset ? [palette.shade.opacity(0.3), palette.light]
                    : [palette.light, palette.shade.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A flat raised island resting in a recessed well, like a switch knob on its track. Its
/// corners follow the well's, inset by `NavigationStyle.iconIslandInset`, as a knob is
/// concentric with its capsule track. Its highlight (up-left) and shade (down-right) fall
/// inside the well: the well that holds it must clip it.
struct SoftWellIsland: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        let shape = NavigationStyle.iconIslandShape
        shape
            .fill(Color(white: dark ? 0.23 : 0.95))
            .background {
                SurfaceShadows(shape: shape, shadows: [
                    .init(color: .black.opacity(dark ? 0.7 : 0.3), radius: 2.5, x: 1.5, y: 2),
                    .init(color: .white.opacity(dark ? 0.1 : 1), radius: 2.5, x: -1.5, y: -2),
                ])
            }
            .overlay {
                if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1) }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// Used only by the sidebar microphone capsule, not every action button.
///
/// It inverts the destination selection so a control never reads as a selected page: the
/// selection is a recessed track holding a raised icon island; the microphone is a raised
/// button holding a recessed icon socket. Pressing sinks it into a well.
struct MicrophoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MicrophoneBody(configuration: configuration)
    }

    private struct MicrophoneBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            let shape = NavigationStyle.wellShape
            let dark = scheme == .dark
            configuration.label
                .background {
                    if configuration.isPressed {
                        NeumorphicSurface(shape: shape, inset: true, depth: 2.5)
                    } else {
                        // The sidebar's own tone, lifted by its light and shade like the brand capsule.
                        shape.fill(LinearGradient(colors: [Color(white: dark ? 0.235 : 0.965), Color(white: dark ? 0.205 : 0.935)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                            .background {
                                SurfaceShadows(shape: shape, shadows: [
                                    .init(color: .black.opacity(dark ? 0.55 : 0.22), radius: 4, x: 2, y: 3),
                                    .init(color: .white.opacity(dark ? 0.09 : 1), radius: 4, x: -2, y: -2.5),
                                ])
                            }
                            .overlay {
                                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.04), lineWidth: 0.5)
                            }
                    }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

/// The recessed socket holding the microphone symbol, concentric with its button.
struct MicrophoneIconSocket: View {
    var body: some View {
        NeumorphicSurface(shape: NavigationStyle.iconIslandShape, inset: true, depth: 1.5)
    }
}

/// A shallow inset for Home's proportional app-usage bars, holding a raised gray fill
/// in the hero bars' tones.
struct NeumorphicUsageTrack: View {
    let fraction: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
            let width = max(0, geometry.size.width - 2) * value
            ZStack(alignment: .leading) {
                NeumorphicSurface(shape: Capsule(), inset: true, depth: 1.2)
                if value > 0 {
                    let dark = scheme == .dark
                    Capsule()
                        .fill(Color(white: dark ? 0.32 : 0.66))
                        .background {
                            SurfaceShadows(shape: Capsule(), shadows: [
                                .init(color: .black.opacity(dark ? 0.6 : 0.25), radius: 1, x: 0.5, y: 0.8),
                                .init(color: .white.opacity(dark ? 0.1 : 0.9), radius: 1, x: -0.4, y: -0.5),
                            ])
                        }
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
