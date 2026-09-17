// Renders the airdraft app icon (neumorphic "speech → cursor" bar) on the
// macOS icon grid and writes every size of the app's AppIcon.appiconset.
// Usage, from the repo root: swift scripts/render-app-icon.swift
import AppKit
import SwiftUI

// Soft-UI palette: one cool base colour, a light and a dark shadow, one accent.
let base = Color(red: 0.902, green: 0.918, blue: 0.945)          // #E6EAF1
let baseTop = Color(red: 0.945, green: 0.957, blue: 0.976)       // #F1F4F9
let baseBottom = Color(red: 0.863, green: 0.882, blue: 0.914)     // #DCE1E9
let lightShadow = Color.white
let darkShadow = Color(red: 0.639, green: 0.690, blue: 0.776)     // #A3B0C6
let accentTop = Color(red: 0.420, green: 0.478, blue: 1.000)      // #6B7AFF
let accentBottom = Color(red: 0.231, green: 0.765, blue: 0.957)   // #3BC3F4

struct Icon: View {
    // macOS icon grid: 824 pt body inside a 1024 pt canvas.
    let side = CGFloat(824)
    let levels: [CGFloat] = [0.36, 0.66, 1.0, 0.72, 0.48]
    let neutral = Color(red: 0.682, green: 0.725, blue: 0.800)    // #AEB9CC

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
            // Raised pill: the "bar".
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [baseTop, baseBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 672, height: 330)
                .shadow(color: lightShadow, radius: 30, x: -22, y: -22)
                .shadow(color: darkShadow.opacity(0.9), radius: 34, x: 24, y: 28)

            // Pressed track inside the pill.
            Capsule(style: .continuous)
                .fill(base.shadow(.inner(color: darkShadow, radius: 16, x: 12, y: 12))
                          .shadow(.inner(color: lightShadow, radius: 14, x: -10, y: -10)))
                .frame(width: 584, height: 242)

            // Waveform bars warming from neutral to the accent, then the caret where text lands.
            HStack(alignment: .center, spacing: 28) {
                ForEach(Array(levels.enumerated()), id: \.offset) { i, level in
                    let t = Double(i + 1) / Double(levels.count + 1)
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [mix(neutral, accentTop, t * 0.85), mix(neutral, accentBottom, t * 0.85)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 34, height: 170 * level)
                        .shadow(color: darkShadow.opacity(0.45), radius: 4, x: 2, y: 3)
                }
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 186)
                    .shadow(color: accentTop.opacity(0.6), radius: 22)
                    .padding(.leading, 18)
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

func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let ca = NSColor(a).usingColorSpace(.sRGB)!, cb = NSColor(b).usingColorSpace(.sRGB)!
    func lerp(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x + (y - x) * CGFloat(t)) }
    return Color(red: lerp(ca.redComponent, cb.redComponent), green: lerp(ca.greenComponent, cb.greenComponent), blue: lerp(ca.blueComponent, cb.blueComponent))
}

@MainActor func render() {
    let dir = URL(fileURLWithPath: "Sources/App/Assets.xcassets/AppIcon.appiconset")
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let master = renderer.cgImage else { fatalError("render failed") }
    for size in [16, 32, 64, 128, 256, 512, 1024] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.imageInterpolation = .high
        NSGraphicsContext.current = context
        context.cgContext.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(size).png"))
    }
    print("wrote \(dir.path)")
}

MainActor.assumeIsolated { render() }
