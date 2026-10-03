// Renders the airdraft app icon (neumorphic "speech → cursor" bar) on the
// macOS icon grid and writes every size of the app's AppIcon.appiconset, plus
// the website's copies of the icon and favicon.
// Usage, from the repo root: swift scripts/render-app-icon.swift
import AppKit
import SwiftUI

// Soft-UI palette: the app window's neutral grays (Theme, HomeHero), lit from the
// top left. No hue: the bars and caret are raised gray pills, as on Home.
let base = Color(white: 0.91)
let baseTop = Color(white: 0.96)
let baseBottom = Color(white: 0.85)
let lightShadow = Color.white
let darkShadow = Color(white: 0.58)
let contact = Color(white: 0.36)
let barTop = Color(white: 0.79)        // HomeHero raisedTop
let barBottom = Color(white: 0.54)     // HomeHero raisedBottom
let caretTop = Color(white: 0.40)      // a step darker than Home's caret,
let caretBottom = Color(white: 0.18)   // so it still reads at 16 px

struct Icon: View {
    // macOS icon grid: 824 pt body inside a 1024 pt canvas.
    let side = CGFloat(824)
    let levels: [CGFloat] = [0.36, 0.66, 1.0, 0.72, 0.48]

    var body: some View {
        let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            // Body: raised squircle with a soft top-left light.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [baseTop, baseBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)], center: UnitPoint(x: 0.2, y: 0.12), startRadius: 0, endRadius: 520))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .topLeading, endPoint: .center), lineWidth: 4)
                )

            // Everything on the body is clipped to it, so soft shadows never spill past the edge.
            ZStack {
            // Raised pill: the "bar". A bright top edge and a short shadow
            // underneath give it its height, instead of a wide soft halo.
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [baseTop, baseBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Capsule(style: .continuous)
                    .strokeBorder(LinearGradient(colors: [lightShadow.opacity(0.9), lightShadow.opacity(0)],
                                                 startPoint: .top, endPoint: .center), lineWidth: 4))
                .frame(width: 744, height: 364)
                .shadow(color: darkShadow.opacity(0.55), radius: 20, x: 10, y: 18)
                .shadow(color: contact.opacity(0.35), radius: 2, x: 2, y: 3)

            // Pressed track inside the pill.
            Capsule(style: .continuous)
                .fill(base.shadow(.inner(color: darkShadow, radius: 16, x: 12, y: 12))
                          .shadow(.inner(color: lightShadow, radius: 14, x: -10, y: -10)))
                .frame(width: 650, height: 270)

            // Waveform bars raised from the track floor, then the caret where text lands:
            // light up-left, shade down-right, like Home's waveform.
            HStack(alignment: .center, spacing: 30) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [barTop, barBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Capsule(style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                        .frame(width: 38, height: 190 * level)
                        .shadow(color: .black.opacity(0.32), radius: 7, x: 5, y: 8)
                        .shadow(color: .white, radius: 6, x: -4, y: -5)
                }
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [caretTop, caretBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Capsule(style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                    .frame(width: 38, height: 208)
                    .shadow(color: .black.opacity(0.38), radius: 8, x: 6, y: 9)
                    .shadow(color: .white, radius: 6, x: -4, y: -5)
                    .padding(.leading, 20)
            }
            }
            .frame(width: side, height: side)
            .clipShape(squircle)
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 20, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func master(_ icon: Icon) -> CGImage {
    let renderer = ImageRenderer(content: icon)
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("render failed") }
    return image
}

/// Resample to `size` pixels and write a PNG.
@MainActor func write(_ image: CGImage, size: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

@MainActor func render() {
    let dir = URL(fileURLWithPath: "Sources/App/Assets.xcassets/AppIcon.appiconset")
    let icon = master(Icon())
    for size in [16, 32, 64, 128, 256, 512, 1024] {
        write(icon, size: size, to: dir.appendingPathComponent("icon_\(size).png"))
    }
    print("wrote \(dir.path)")

    let site = URL(fileURLWithPath: "apps/marketing/public")
    write(icon, size: 512, to: site.appendingPathComponent("airdraft-icon.png"))
    write(icon, size: 64, to: site.appendingPathComponent("favicon.png"))
    print("wrote \(site.path)")
}

MainActor.assumeIsolated { render() }
