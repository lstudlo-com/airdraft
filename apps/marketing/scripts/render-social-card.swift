// Render the 1200 x 630 sharing image in each website language, using the
// existing app icon: social-card.png (English) and social-card-<code>.png.
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

struct Card {
    let file: String
    let lines: [String]
    let tagline: String
    let size: CGFloat
}

// Each card's words match that language's og:image:alt (src/lib/seo.ts).
let cards = [
    Card(file: "social-card.png",
         lines: ["Speak into any app.", "Transcribe anything.", "Keep it on your Mac."],
         tagline: "Open source · Local or cloud models", size: 60),
    Card(file: "social-card-zh-tw.png",
         lines: ["在任何 App 裡用說的輸入。", "什麼聲音都能轉成逐字稿。", "資料留在你的 Mac。"],
         tagline: "開放原始碼 · 本機或雲端模型", size: 52),
    Card(file: "social-card-zh-cn.png",
         lines: ["在任何 App 里用说的输入。", "什么声音都能转成文字稿。", "数据留在你的 Mac。"],
         tagline: "开源 · 本机或云端模型", size: 52),
    Card(file: "social-card-es.png",
         lines: ["Habla en cualquier app.", "Transcribe lo que sea.", "Mantenlo en tu Mac."],
         tagline: "Código abierto · Modelos locales o en la nube", size: 54),
    Card(file: "social-card-ja.png",
         lines: ["どのアプリにも話して入力。", "なんでも文字起こし。", "データは Mac に。"],
         tagline: "オープンソース · ローカルまたはクラウド", size: 52),
]

guard let icon = NSImage(contentsOf: publicDirectory.appendingPathComponent("airdraft-icon.png")) else {
    fatalError("The existing app icon is required.")
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

for card in cards {
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
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("The bitmap context is required.")
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
for (index, line) in card.lines.enumerated() {
    text(line, x: 76, top: 162 + CGFloat(index) * 70, width: 710,
         size: card.size, weight: .semibold)
}
text(card.tagline, x: 79, top: 430,
     width: 720, size: 25, weight: .regular, gray: 0.36)
text("airdraft.app", x: 79, top: 527, width: 650, size: 22, weight: .medium, gray: 0.36)

icon.draw(in: frame(785, 154, 340, 340))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the sharing image.")
}
let output = publicDirectory.appendingPathComponent(card.file)
try png.write(to: output)
print("Wrote \(output.path) (\(width) x \(height))")
}
