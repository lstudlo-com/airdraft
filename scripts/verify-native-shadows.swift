// Compile with Sources/App/Views/SurfaceShadows.swift, then run the executable.
// Checks both rendering paths: cacheDisplay previously inverted outer shadows.
import AppKit
import SwiftUI

private struct LightingFixture: View {
    let inset: Bool
    let legacy: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.5)
            Group {
                if inset {
                    Rectangle().fill(Color(white: 0.5)
                        .shadow(.inner(color: .red, radius: 1, x: 12, y: 12))
                        .shadow(.inner(color: .blue, radius: 1, x: -12, y: -12)))
                } else if legacy {
                    Rectangle().fill(Color(white: 0.5))
                        .shadow(color: .red, radius: 1, x: 12, y: 12)
                        .shadow(color: .blue, radius: 1, x: -12, y: -12)
                } else {
                    Rectangle().fill(Color(white: 0.5))
                        .background {
                            SurfaceShadows(shape: Rectangle(), shadows: [
                                .init(color: .red, radius: 1, x: 12, y: 12),
                                .init(color: .blue, radius: 1, x: -12, y: -12),
                            ])
                        }
                }
            }
            .frame(width: 80, height: 60)
            .offset(x: 80, y: 80)
        }
        .frame(width: 240, height: 220)
    }
}

@main
@MainActor
private enum VerifyNativeShadows {
    static func main() throws {
        _ = NSApplication.shared
        let outputPath = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") }
        let output = URL(fileURLWithPath: outputPath ?? "/tmp/airdraft-shadow-check")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failures = 0
        for dark in [false, true] {
            for inset in [false, true] {
                let fixture = LightingFixture(inset: inset, legacy: CommandLine.arguments.contains("--legacy"))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: fixture)
                host.frame = NSRect(x: 0, y: 0, width: 240, height: 220)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let cached = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: cached)
                let renderer = ImageRenderer(content: fixture)
                renderer.scale = 2
                let rendered = NSBitmapImageRep(cgImage: renderer.cgImage!)
                for (method, bitmap) in [("hosting", cached), ("image-renderer", rendered)] {
                    let name = "\(dark ? "dark" : "light")-\(inset ? "inset" : "raised")-\(method)"
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
                    let scale = CGFloat(bitmap.pixelsWide) / 240
                    func red(at point: CGPoint) -> Bool {
                        let color = bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.deviceRGB)!
                        return color.redComponent > color.blueComponent + 0.25
                    }
                    func blue(at point: CGPoint) -> Bool {
                        let color = bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.deviceRGB)!
                        return color.blueComponent > color.redComponent + 0.25
                    }
                    // Raised: cast shadow below/right, highlight above/left.
                    // Recessed: occlusion above/left, lit inner edge below/right.
                    let correct = inset
                        ? red(at: CGPoint(x: 120, y: 84)) && red(at: CGPoint(x: 84, y: 110))
                            && blue(at: CGPoint(x: 120, y: 136)) && blue(at: CGPoint(x: 156, y: 110))
                        : red(at: CGPoint(x: 120, y: 148)) && red(at: CGPoint(x: 168, y: 110))
                            && blue(at: CGPoint(x: 120, y: 72)) && blue(at: CGPoint(x: 72, y: 110))
                    print("\(correct ? "PASS" : "FAIL") \(name)")
                    if !correct { failures += 1 }
                }
            }
        }
        if failures > 0 { exit(1) }
    }
}
