// Renders the three waveform-only app icons from one reproducible Swift source.
// Usage from the repo root: swift scripts/render-app-icon.swift [output-root]
// Carved Wave is the bundled Finder icon. Running Dock icons follow the user's
// independently saved light/dark choices. Website PNGs use Carved Wave.
import AppKit
import SwiftUI

struct IconDesign {
    let name: String
    let material: String
}

// All materials use Carved Wave's geometry on the 1024-point canvas.
enum WaveGeometry {
    static let width = 84.0
    static let gap = 30.0
    static let height = 480.0
    static let levels = [0.36, 0.66, 1.0, 0.72, 0.48]
    static let horizontalOffset = -3.0
}

let designs = [
    IconDesign(name: "PureWave", material: "silver"),
    IconDesign(name: "CarvedWave", material: "carved"),
    IconDesign(name: "NightWave", material: "night")
]

func gray(_ value: Double) -> Color { Color(white: value) }

struct WaveBar: View {
    let study: IconDesign
    let level: Double
    var body: some View {
        let shape = Capsule(style: .continuous)
        let night = study.material == "night"
        let top: Double = switch study.material {
        case "night": 0.88
        default: 0.48
        }
        let bottom: Double = switch study.material {
        case "night": 0.63
        default: 0.25
        }
        if study.material == "carved" {
            shape
                .fill(LinearGradient(colors: [gray(0.43), gray(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .shadow(.inner(color: gray(0.25).opacity(0.65), radius: 9, x: 7, y: 9))
                    .shadow(.inner(color: .white.opacity(0.95), radius: 7, x: -6, y: -7)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [gray(0.53).opacity(0.3), .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                .frame(width: WaveGeometry.width, height: WaveGeometry.height * level)
                .shadow(color: .white.opacity(0.9), radius: 1.5, x: 1.5, y: 2)
        } else {
            shape
                .fill(LinearGradient(colors: [gray(top), gray(bottom)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(night ? 0.75 : 0.9), .white.opacity(0.02), .black.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5))
                .frame(width: WaveGeometry.width, height: WaveGeometry.height * level)
                .drawingGroup()
                .shadow(color: .black.opacity(night ? 0.5 : 0.24), radius: 11, x: 8, y: 12)
                .shadow(color: .white.opacity(night ? 0.10 : 0.9), radius: 9, x: -6, y: -7)
        }
    }
}

struct WaveIcon: View {
    let study: IconDesign
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        let night = study.material == "night"
        let top = night ? 0.18 : 0.96
        let bottom = night ? 0.08 : 0.85
        ZStack {
            tile.fill(LinearGradient(colors: [gray(top), gray(bottom)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(tile.fill(RadialGradient(colors: [.white.opacity(night ? 0.07 : 0.48), .white.opacity(0)], center: UnitPoint(x: 0.2, y: 0.12), startRadius: 0, endRadius: 560)))
                .overlay(tile.strokeBorder(LinearGradient(colors: [.white.opacity(night ? 0.20 : 0.9), .white.opacity(0)], startPoint: .topLeading, endPoint: .center), lineWidth: 3))
            HStack(alignment: .center, spacing: WaveGeometry.gap) {
                ForEach(Array(WaveGeometry.levels.enumerated()), id: \.offset) { _, level in
                    WaveBar(study: study, level: level)
                }
            }
            .offset(x: WaveGeometry.horizontalOffset)
        }
        .frame(width: 824, height: 824)
        .clipShape(tile)
        .compositingGroup()
        .shadow(color: .black.opacity(0.23), radius: 20, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render<V: View>(_ view: V) -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("SwiftUI image rendering failed") }
    return image
}

func pngData(_ image: CGImage, size: Int? = nil) -> Data {
    let width = size ?? image.width, height = size ?? image.height
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

@MainActor func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
    let assets = root.appendingPathComponent("Sources/App/Assets.xcassets")
    for design in designs {
        let image = render(WaveIcon(study: design))
        let directory = assets.appendingPathComponent("AppIcon\(design.name).imageset")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [512, 1024] {
            try pngData(image, size: size).write(to: directory.appendingPathComponent("icon_\(size).png"))
        }
        let contents: [String: Any] = [
            "images": [
                ["filename": "icon_512.png", "idiom": "universal", "scale": "1x"],
                ["filename": "icon_1024.png", "idiom": "universal", "scale": "2x"]
            ],
            "info": ["author": "xcode", "version": 1]
        ]
        try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("Contents.json"))
        if design.name == "CarvedWave" {
            let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
            try FileManager.default.createDirectory(at: appIcon, withIntermediateDirectories: true)
            for size in [16, 32, 64, 128, 256, 512, 1024] {
                try pngData(image, size: size).write(to: appIcon.appendingPathComponent("icon_\(size).png"))
            }
            let site = root.appendingPathComponent("apps/marketing/public")
            try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
            try pngData(image, size: 512).write(to: site.appendingPathComponent("airdraft-icon.png"))
            try pngData(image, size: 64).write(to: site.appendingPathComponent("favicon.png"))
        }
        print("Rendered \(design.name)")
    }
}

MainActor.assumeIsolated {
    do { try main() } catch { fputs("\(error)\n", stderr); exit(1) }
}
