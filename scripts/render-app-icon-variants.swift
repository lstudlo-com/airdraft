// Renders candidate app icons for choosing: small refinements of the shipping
// icon, each changing one or two things. Nothing in the asset catalogue
// changes: this writes 1024 px masters and a comparison sheet (the current
// icon first) to a scratch directory.
// Usage, from the repo root: swift scripts/render-app-icon-variants.swift [output-dir]
// Once a variant is chosen, port its settings into scripts/render-app-icon.swift.
import AppKit
import SwiftUI

// Same palette as render-app-icon.swift and apps/marketing/DESIGN.md.
let baseTop = Color(red: 0.945, green: 0.957, blue: 0.976)       // #F1F4F9
let baseBottom = Color(red: 0.863, green: 0.882, blue: 0.914)    // #DCE1E9
let base = Color(red: 0.902, green: 0.918, blue: 0.945)          // #E6EAF1
let darkShadow = Color(red: 0.639, green: 0.690, blue: 0.776)    // #A3B0C6
let contact = Color(red: 0.373, green: 0.424, blue: 0.529)       // #5F6C87
let neutral = Color(red: 0.682, green: 0.725, blue: 0.800)       // #AEB9CC
let ink = Color(red: 0.149, green: 0.192, blue: 0.275)           // #263146
let glowViolet = Color(red: 0.420, green: 0.478, blue: 1.000)    // #6B7AFF
let glowCyan = Color(red: 0.231, green: 0.765, blue: 0.957)      // #3BC3F4

let side = CGFloat(824)
let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)

func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let ca = NSColor(a).usingColorSpace(.sRGB)!, cb = NSColor(b).usingColorSpace(.sRGB)!
    func lerp(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x + (y - x) * CGFloat(t)) }
    return Color(red: lerp(ca.redComponent, cb.redComponent), green: lerp(ca.greenComponent, cb.greenComponent),
                 blue: lerp(ca.blueComponent, cb.blueComponent))
}

/// Every setting of the shipping icon. The defaults reproduce it exactly;
/// each variant overrides only what it changes.
struct Tune {
    // Body
    var bodyTop = baseTop
    var bodyBottom = baseBottom
    var sheen = 0.7
    // Raised pill (the "bar"); `nil` radius means a capsule.
    var showPill = true
    var pill = CGSize(width: 672, height: 330)
    var pillRadius: CGFloat? = nil
    var pillTop = baseTop
    var pillBottom = baseBottom
    var pillLight = (radius: CGFloat(30), x: CGFloat(-22), y: CGFloat(-22), opacity: 1.0)
    var pillDark = (radius: CGFloat(34), x: CGFloat(24), y: CGFloat(28), opacity: 0.9)
    var pillContact = 0.0
    var pillBevel = 0.0
    // Pressed track inside the pill.
    var track = CGSize(width: 584, height: 242)
    var trackFill = base
    var trackDark = (radius: CGFloat(16), x: CGFloat(12), y: CGFloat(12), opacity: 1.0)
    var trackLight = (radius: CGFloat(14), x: CGFloat(-10), y: CGFloat(-10), opacity: 1.0)
    // Waveform and caret.
    var levels: [CGFloat] = [0.36, 0.66, 1.0, 0.72, 0.48]
    var barWidth = CGFloat(34)
    var barSpacing = CGFloat(28)
    var barHeight = CGFloat(170)
    var warmth = 0.85
    var barShadow = 0.45
    var caretHeight = CGFloat(186)
    var caretGap = CGFloat(18)
    var caretGlow = CGFloat(22)
    var scale = CGFloat(1)
    // How the bars and the caret are drawn: coloured, or carved into / raised
    // from the silver with light and shadow only.
    var bars = Relief.color
    var caret = Relief.color
}

enum Relief { case color, carved, raised }

/// One waveform bar or the caret. Colourless reliefs use the icon's light:
/// from the upper left, so a groove is dark on its upper-left wall and lit on
/// its lower-right wall; a ridge is the reverse.
struct Mark: View {
    let relief: Relief
    let width: CGFloat
    let height: CGFloat
    var colors: [Color]
    var shadow = 0.0
    var glow = CGFloat(0)
    var body: some View {
        let shape = Capsule(style: .continuous)
        switch relief {
        case .color:
            shape
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)
                .shadow(color: darkShadow.opacity(shadow), radius: 4, x: 2, y: 3)
                .shadow(color: glowViolet.opacity(glow > 0 ? 0.6 : 0), radius: glow)
        case .carved:
            shape
                .fill(LinearGradient(colors: [Color(red: 0.87, green: 0.886, blue: 0.914), base], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: darkShadow, radius: 5, x: 5, y: 6))
                    .shadow(.inner(color: .white, radius: 3, x: -3, y: -4)))
                .frame(width: width, height: height)
                .shadow(color: .white.opacity(0.7), radius: 0.5, x: 1.5, y: 2)
        case .raised:
            shape
                .fill(LinearGradient(colors: [baseTop, baseBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0)],
                                                           startPoint: .top, endPoint: .center), lineWidth: 2))
                .frame(width: width, height: height)
                .shadow(color: contact.opacity(0.3), radius: 1.5, x: 1, y: 2)
                .shadow(color: darkShadow.opacity(0.75), radius: 6, x: 5, y: 7)
                .shadow(color: .white, radius: 5, x: -4, y: -4)
        }
    }
}

struct TunedIcon: View {
    var t = Tune()
    var body: some View {
        let pillShape = RoundedRectangle(cornerRadius: t.pillRadius ?? t.pill.height / 2, style: .continuous)
        let trackRadius = t.pillRadius.map { max($0 - (t.pill.height - t.track.height) / 2, 24) } ?? t.track.height / 2
        let trackShape = RoundedRectangle(cornerRadius: trackRadius, style: .continuous)
        ZStack {
            squircle
                .fill(LinearGradient(colors: [t.bodyTop, t.bodyBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(squircle.fill(RadialGradient(colors: [.white.opacity(t.sheen), .white.opacity(0)],
                                                      center: UnitPoint(x: 0.2, y: 0.12), startRadius: 0, endRadius: 520)))
                .overlay(squircle.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0)],
                                                              startPoint: .topLeading, endPoint: .center), lineWidth: 4))
            ZStack {
                if t.showPill {
                    pillShape
                        .fill(LinearGradient(colors: [t.pillTop, t.pillBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(pillShape.strokeBorder(LinearGradient(colors: [.white.opacity(t.pillBevel), .white.opacity(0)],
                                                                       startPoint: .top, endPoint: .center), lineWidth: 4))
                        .frame(width: t.pill.width, height: t.pill.height)
                        .shadow(color: .white.opacity(t.pillLight.opacity), radius: t.pillLight.radius, x: t.pillLight.x, y: t.pillLight.y)
                        .shadow(color: darkShadow.opacity(t.pillDark.opacity), radius: t.pillDark.radius, x: t.pillDark.x, y: t.pillDark.y)
                        .shadow(color: contact.opacity(t.pillContact), radius: 2, y: 3)
                }
                trackShape
                    .fill(t.trackFill
                        .shadow(.inner(color: darkShadow.opacity(t.trackDark.opacity), radius: t.trackDark.radius,
                                       x: t.trackDark.x, y: t.trackDark.y))
                        .shadow(.inner(color: .white.opacity(t.trackLight.opacity), radius: t.trackLight.radius,
                                       x: t.trackLight.x, y: t.trackLight.y)))
                    .frame(width: t.track.width, height: t.track.height)
                HStack(alignment: .center, spacing: t.barSpacing) {
                    ForEach(Array(t.levels.enumerated()), id: \.offset) { index, level in
                        let position = Double(index + 1) / Double(t.levels.count + 1)
                        Mark(relief: t.bars, width: t.barWidth, height: t.barHeight * level,
                             colors: [mix(neutral, glowViolet, position * t.warmth), mix(neutral, glowCyan, position * t.warmth)],
                             shadow: t.barShadow)
                    }
                    Mark(relief: t.caret, width: t.barWidth, height: t.caretHeight,
                         colors: [glowViolet, glowCyan], glow: t.caretGlow)
                        .padding(.leading, t.caretGap)
                }
            }
            .scaleEffect(t.scale)
            .frame(width: side, height: side)
            .clipShape(squircle)
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 20, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

func tuned(_ change: (inout Tune) -> Void) -> Tune {
    var tune = Tune()
    change(&tune)
    return tune
}

/// Edged: the pill loses its halo and gains a bright top edge and a short
/// shadow underneath. Chosen from the previous round.
func edged(_ tune: inout Tune) {
    tune.pillLight = (0, 0, 0, 0)
    tune.pillDark = (18, 0, 16, 0.55)
    tune.pillContact = 0.35
    tune.pillBevel = 0.9
    tune.barShadow = 0.2
}

/// Edged with a larger capsule, groove and waveform.
func edgedLarger(_ tune: inout Tune) {
    edged(&tune)
    tune.pill = CGSize(width: 744, height: 364)
    tune.track = CGSize(width: 650, height: 270)
    tune.pillDark = (20, 0, 18, 0.55)
    tune.barWidth = 38
    tune.barSpacing = 30
    tune.barHeight = 190
    tune.caretHeight = 208
    tune.caretGap = 20
}

let variants: [(slug: String, title: String, tune: Tune)] = [
    ("current", "Current", Tune()),
    ("edged", "Edged", tuned(edged)),
    ("edged-larger", "Edged, larger", tuned(edgedLarger)),
    // No colour: waveform and caret cut into the groove.
    ("edged-carved", "Carved", tuned {
        edgedLarger(&$0)
        $0.bars = .carved
        $0.caret = .carved
    }),
    // No colour: waveform and caret standing up out of the groove.
    ("edged-raised", "Raised", tuned {
        edgedLarger(&$0)
        $0.bars = .raised
        $0.caret = .raised
    }),
    // Carved waveform; the caret keeps its colour as the one accent.
    ("edged-carved-caret", "Carved, blue caret", tuned {
        edgedLarger(&$0)
        $0.bars = .carved
        $0.caretGlow = 14
    }),
]

// MARK: - Output

@MainActor func image(_ view: some View, scale: CGFloat = 1) -> NSImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else { fatalError("render failed") }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

@MainActor func write(_ image: NSImage, to url: URL) {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// Resample to a real pixel size, as the asset catalogue would, so small sizes
/// in the sheet show true legibility rather than a scaled-down master.
@MainActor func resampled(_ master: NSImage, to size: Int) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    master.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
}

struct Tile: View {
    let title: String
    let master: NSImage
    let small: [NSImage]
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: master).resizable().frame(width: 240, height: 240)
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(Array(small.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image).interpolation(.none)
                        .frame(width: image.size.width, height: image.size.height)
                }
            }
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(ink)
        }
        .frame(width: 280)
    }
}

struct Sheet: View {
    let tiles: [Tile]
    let columns = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 48) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: 40) {
                    ForEach(start..<min(start + columns, tiles.count), id: \.self) { tiles[$0] }
                }
            }
        }
        .padding(56)
        .background(base)
    }
}

@MainActor func render() {
    let args = CommandLine.arguments.dropFirst()
    let dir = URL(fileURLWithPath: args.first
        ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("airdraft-icon-variants"))
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var tiles: [Tile] = []
    for variant in variants {
        let master = image(TunedIcon(t: variant.tune))
        write(master, to: dir.appendingPathComponent("\(variant.slug)-1024.png"))
        tiles.append(Tile(title: variant.title, master: master, small: [64, 32, 16].map { resampled(master, to: $0) }))
    }
    write(image(Sheet(tiles: tiles)), to: dir.appendingPathComponent("comparison.png"))
    print("wrote \(dir.path)")
}

MainActor.assumeIsolated { render() }
