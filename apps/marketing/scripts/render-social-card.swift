// Render the shared 1200 x 630 sharing image using the existing app icon.
// Uses the website's neutral chrome/island colors and native SF typography.
// No model output, user data, price, or distribution claim appears in the card.
// From the repository root:
// swift apps/marketing/scripts/render-social-card.swift
import AppKit

let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let publicDirectory = repository.appendingPathComponent("apps/marketing/public")
let width = 1200
let height = 630

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: width * 4,
    bitsPerPixel: 32
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap),
   let icon = NSImage(contentsOf: publicDirectory.appendingPathComponent("airdraft-icon.png"))
else {
    fatalError("The bitmap context and existing app icon are required.")
}

func frame(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(height) - top - h, width: w, height: h)
}

func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat,
          size: CGFloat, weight: NSFont.Weight, gray: CGFloat = 0.133) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: gray, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: size >= 50 ? -1.5 : 0,
    ]
    (value as NSString).draw(
        in: frame(x, top, width, size * 1.45),
        withAttributes: attributes
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

NSColor(white: 0.95, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let island = NSBezierPath(roundedRect: frame(18, 18, 1164, 594), xRadius: 28, yRadius: 28)
NSColor(white: 0.90, alpha: 1).setFill()
island.fill()
NSColor(white: 0.78, alpha: 0.5).setStroke()
island.lineWidth = 1
island.stroke()

text("Airdraft", x: 78, top: 72, width: 650, size: 32, weight: .semibold)
text("The Mac", x: 76, top: 162, width: 710, size: 66, weight: .semibold)
text("transcription app", x: 76, top: 236, width: 710, size: 66, weight: .semibold)
text("you own.", x: 76, top: 310, width: 710, size: 66, weight: .semibold)
text("Open source · Local or cloud models", x: 79, top: 430,
     width: 720, size: 25, weight: .regular, gray: 0.36)
text("airdraft.app", x: 79, top: 527, width: 650, size: 22, weight: .medium, gray: 0.36)

icon.draw(in: frame(785, 154, 340, 340))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the sharing image.")
}
let output = publicDirectory.appendingPathComponent("social-card.png")
try png.write(to: output)
print("Wrote \(output.path) (\(width) x \(height))")
