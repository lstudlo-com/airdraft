// THESIS: The app icon's silver capsule becomes the place where installation happens.
// OWN-WORLD: Cool silver, slate ink, the existing outlined wordmark, a violet-blue arrow.
// STORY: Welcome, drag the real app into Applications, then open the installed copy.
// FIRST VIEWPORT: A 760 × 560 canvas with bottom bleed; branding above two 112 pt icons
// at (220,270) and (540,270), inside one recessed capsule; instructions below.
// FORM: The user's two-icon DMG reference, expanded with Airdraft's established geometry.
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish
// review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
// Usage: swift scripts/render-dmg-background.swift <output-directory>
import AppKit
import SwiftUI

struct Layout: Decodable {
    let width: CGFloat
    let height: CGFloat
    let iconSize: CGFloat
    let textSize: CGFloat
    let appPosition: [CGFloat]
    let applicationsPosition: [CGFloat]
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: root.appendingPathComponent("scripts/dmg-layout.json")))
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/dmg-artwork", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// AppKit rasterizes SVGs at their declared dimensions. Request enough pixels for
// the 126 pt wordmark at 2x before SwiftUI receives the image.
let wordmarkSource = try String(contentsOf: root.appendingPathComponent("Sources/App/Assets.xcassets/SidebarWordmark.imageset/wordmark.svg"), encoding: .utf8)
let wordmarkSVG = wordmarkSource.replacingOccurrences(of: "width=\"108\" height=\"24\"", with: "width=\"504\" height=\"112\"")
let wordmark = NSImage(data: Data(wordmarkSVG.utf8))!

func color(_ hex: UInt32) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
          green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
}

struct InstallArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX - 8, y: rect.midY - 8))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.midY + 8))
        return path
    }
}

struct InstallerBackground: View {
    let ink = color(0x263146)
    let muted = color(0x505C73)
    let shadow = color(0x8F9BB1)

    var body: some View {
        ZStack {
            LinearGradient(colors: [color(0xF1F4F9), color(0xE6EAF1), color(0xDCE1E9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // Oversized concentric contours carry the capsule shape to the window edges.
            // These are precise brand geometry, not an illustration or generated texture.
            ForEach(0..<4) { index in
                Capsule()
                    .stroke(.white.opacity(0.48 - Double(index) * 0.08), lineWidth: 1)
                    .shadow(color: shadow.opacity(0.14), radius: 1, y: 1)
                    .frame(width: 620 + CGFloat(index) * 116, height: 228 + CGFloat(index) * 116)
                    .position(x: layout.width / 2, y: 278)
            }

            // Upper-left light, a contact shadow and a broad offset shadow match the app icon.
            Capsule()
                .fill(LinearGradient(colors: [color(0xF5F7FA), color(0xE2E7EE)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 574, height: 194)
                .shadow(color: shadow.opacity(0.28), radius: 20, x: 6, y: 16)
                .shadow(color: color(0x5F6C87).opacity(0.18), radius: 2, y: 2)
                .position(x: layout.width / 2, y: 278)

            Capsule()
                .fill(color(0xE6EAF1)
                    .shadow(.inner(color: shadow.opacity(0.40), radius: 10, x: 5, y: 7))
                    .shadow(.inner(color: .white.opacity(0.95), radius: 8, x: -5, y: -6)))
                .frame(width: 544, height: 164)
                .position(x: layout.width / 2, y: 278)

            Image(nsImage: wordmark)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(ink)
                .frame(width: 126, height: 28)
                .position(x: layout.width / 2, y: 51)

            Text("Welcome to Airdraft.")
                .font(.system(size: 30, weight: .medium))
                .tracking(-0.6)
                .foregroundStyle(ink)
                .position(x: layout.width / 2, y: 110)

            InstallArrow()
                .stroke(color(0x6879A5), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 54, height: 20)
                .position(x: layout.width / 2, y: layout.appPosition[1] - 6)

            Text("Drag \(Text("Airdraft").fontWeight(.semibold)) to \(Text("Applications").fontWeight(.semibold)) to install.")
                .font(.system(size: 16))
                .foregroundStyle(ink)
                .position(x: layout.width / 2, y: 414)

            Text("Then open Airdraft from Applications.")
                .font(.system(size: 13))
                .foregroundStyle(muted)
                .position(x: layout.width / 2, y: 443)
        }
        .frame(width: layout.width, height: layout.height)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}

@MainActor func render() throws {
    var representations: [NSBitmapImageRep] = []
    for scale in [1, 2] {
        let renderer = ImageRenderer(content: InstallerBackground())
        renderer.scale = CGFloat(scale)
        guard let image = renderer.cgImage else { fatalError("DMG artwork rendering failed") }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: layout.width, height: layout.height)
        try rep.representation(using: .png, properties: [:])!.write(
            to: output.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png"))
        representations.append(rep)
    }
    // Finder reads the point size and chooses a native-resolution representation on Retina.
    guard let tiff = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff,
                                                               properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])
    else { fatalError("Could not encode multi-resolution TIFF") }
    try tiff.write(to: output.appendingPathComponent("background.tiff"))
    try "Generated by scripts/render-dmg-background.swift from Airdraft's existing icon geometry and vector wordmark. No generated or third-party imagery.\n".write(
        to: output.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
    print("Rendered DMG artwork at 1x and 2x: \(output.path)")
}

try MainActor.assumeIsolated { try render() }
