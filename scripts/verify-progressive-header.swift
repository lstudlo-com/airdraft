// xcrun swiftc Sources/App/Views/ProgressiveHeaderBlur.swift scripts/verify-progressive-header.swift -o /tmp/verify-progressive-header
// /tmp/verify-progressive-header [--live | --island <png>]
// The live fixture must be inspected through the window compositor, not bitmap capture.
// --island captures this process's own window through the compositor, which needs no
// Screen Recording access, and checks the header inside the page island's clip.
import AppKit
import SwiftUI

private struct BlurFixture: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(0..<16) { _ in
                    Text("Qwen3-ASR  ·  Speech on this Mac")
                        .font(.system(size: 13))
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 24)
            .padding(.top, 6)
            // 68 pt header + 24 pt content inset + 4 pt outer feather.
            ProgressiveHeaderBlur(maximumRadius: 32).frame(height: 96)
            Text("Models")
                .font(.system(size: 20, weight: .semibold))
                .padding(.leading, 24)
                .padding(.top, 24)
        }
        .frame(width: 600, height: 300)
    }
}

/// The app's shell in miniature: a saturated chrome makes any bleed into the island visible.
private struct IslandFixture: View {
    static let size = CGSize(width: 600, height: 320)
    static let island = CGRect(x: 170, y: 10, width: 420, height: 300)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.red
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<24) { _ in
                        Text("Qwen3-ASR  ·  Speech on this Mac")
                            .font(.system(size: 13))
                            .frame(height: 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Models")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .frame(height: 32)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                    .background(alignment: .top) { ProgressiveHeaderBlur(maximumRadius: 32).frame(height: 96) }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: Self.island.width, height: Self.island.height)
            .padding(.leading, Self.island.minX)
            .padding(.top, Self.island.minY)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
    }
}

extension NSView {
    fileprivate func firstScrollView() -> NSScrollView? {
        for subview in subviews {
            if let scroll = (subview as? NSScrollView) ?? subview.firstScrollView() { return scroll }
        }
        return nil
    }
}

@MainActor private func verifyIsland(output: String) {
    let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: 200, y: 200), size: IslandFixture.size),
                          styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = NSHostingView(rootView: IslandFixture())
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    // Put text beneath the header so the blur has live content to sample.
    guard let scroll = window.contentView?.firstScrollView() else { preconditionFailure("No scroll view in the island fixture") }
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
    scroll.reflectScrolledClipView(scroll.contentView)
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))

    // CGWindowListCreateImage is unavailable in the current SDK but still returns the
    // caller's own windows without Screen Recording access.
    typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage"),
          let image = unsafeBitCast(symbol, to: Capture.self)(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?
              .takeRetainedValue() else {
        preconditionFailure("The compositor capture is unavailable; inspect --live by eye instead")
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
    let scale = CGFloat(image.width) / IslandFixture.size.width
    func pixel(_ x: CGFloat, _ y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let color = bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) ?? .black
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }
    let island = IslandFixture.island
    let corner = pixel(island.minX + 1, island.minY + 1)
    precondition(corner.r - corner.g > 0.4,
                 "The island's rounded corner must clip the header and reveal the chrome")
    for y in stride(from: island.minY + 1, through: island.minY + 8, by: 1) {
        for x in stride(from: island.minX + 16, through: island.maxX - 16, by: 8) {
            let sample = pixel(x, y)
            precondition(sample.r - sample.g < 0.03,
                         "Chrome colour bled into the header blur at \(Int(x)), \(Int(y))")
        }
    }
    // Text under the header is blurred to mid-tones; the same text below it stays sharp.
    func darkest(_ rows: ClosedRange<CGFloat>) -> CGFloat {
        var minimum: CGFloat = 1
        for y in stride(from: rows.lowerBound, through: rows.upperBound, by: 1) {
            for x in stride(from: island.minX + 130, through: island.minX + 250, by: 1) {
                minimum = min(minimum, pixel(x, y).g)
            }
        }
        return minimum
    }
    let underHeader = darkest(island.minY + 4...island.minY + 56)
    let content = darkest(island.minY + 120...island.minY + 200)
    precondition(underHeader > 0.45 && content < 0.35,
                 "Text under the header must be blurred (darkest \(underHeader)) while content stays sharp (\(content))")
    print("PASS: Island clip keeps the chrome out of the live header blur; wrote \(output)")
}

@main
enum VerifyProgressiveHeader {
    @MainActor static func main() {
        let app = NSApplication.shared
        let mask = ProgressiveHeaderBlurView.radiusMask
        let data = mask.dataProvider!.data! as Data
        let alpha = (0..<mask.height).map { data[$0 * mask.bytesPerRow + 3] }
        precondition(alpha.first == 255 && alpha.last == 0, "Blur must be strongest at the top and clear at the bottom")
        precondition(zip(alpha, alpha.dropFirst()).allSatisfy { $0 >= $1 }, "Blur must never become stronger toward the bottom")
        func radius(atProgress progress: Double) -> Double {
            let row = Int((Double(mask.height - 1) * (1 - progress)).rounded())
            return Double(alpha[row]) / 255 * 32
        }
        precondition((0.9...1.25).contains(radius(atProgress: 4.0 / 96.0)),
                     "The bottom of the content inset must already have a visible light blur")
        precondition((2...3).contains(radius(atProgress: 0.25)),
                     "The lower region must be visibly blurred without immediately obscuring the text")
        precondition((7...9).contains(radius(atProgress: 0.5)),
                     "Blur must keep increasing through the middle of the header")
        precondition(radius(atProgress: 0.75) > 12,
                     "The header must still build toward a strong blur at the top")

        let view = ProgressiveHeaderBlurView(maximumRadius: 32)
        view.frame = NSRect(x: 0, y: 0, width: 614, height: 96)
        view.layoutSubtreeIfNeeded()
        guard let backdrop = view.layer?.sublayers?.first,
              let filter = backdrop.filters?.first as? NSObject else {
            preconditionFailure("This macOS runtime cannot provide variable backdrop blur; the app will use its standard-material fallback")
        }
        precondition(backdrop.frame == view.bounds && backdrop.opacity == 1 && backdrop.mask == nil,
                     "The blur must cover the full header without a layer-opacity mask")
        precondition((filter.value(forKey: "inputRadius") as? NSNumber)?.doubleValue == 32)
        precondition(filter.value(forKey: "inputMaskImage") != nil)
        precondition(view.hitTest(.zero) == nil, "The backdrop must not intercept header controls")
        view.frame.size.width = 693
        view.maximumRadius = 20
        view.layoutSubtreeIfNeeded()
        precondition(backdrop.frame == view.bounds)
        precondition((filter.value(forKey: "inputRadius") as? NSNumber)?.doubleValue == 20)
        print("PASS: Gentle blur onset, full-height radius ramp, compositor availability, resize and pointer passthrough")

        if let flag = CommandLine.arguments.firstIndex(of: "--island") {
            let arguments = CommandLine.arguments
            verifyIsland(output: arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "/tmp/progressive-header-island.png")
            return
        }
        guard CommandLine.arguments.contains("--live") else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Progressive header blur"
        window.contentView = NSHostingView(rootView: BlurFixture())
        app.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate()
        app.run()
    }
}
