// xcrun swiftc Sources/App/Views/ProgressiveHeaderBlur.swift scripts/verify-progressive-header.swift -o /tmp/verify-progressive-header
// /tmp/verify-progressive-header [--live]
// The live fixture must be inspected through the window compositor, not bitmap capture.
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
            ProgressiveHeaderBlur(maximumRadius: 32).frame(height: 68)
            Text("Models")
                .font(.system(size: 20, weight: .semibold))
                .padding(.leading, 24)
                .padding(.top, 24)
        }
        .frame(width: 600, height: 300)
    }
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
        precondition(radius(atProgress: 0.25) > 0 && radius(atProgress: 0.25) <= 0.75,
                     "The first quarter must only soften small text, not obscure it")
        precondition((3.5...4.5).contains(radius(atProgress: 0.5)),
                     "Reserve strong blur for the upper half of the header")
        precondition(radius(atProgress: 0.75) > 12,
                     "The header must still build toward a strong blur at the top")

        let view = ProgressiveHeaderBlurView(maximumRadius: 32)
        view.frame = NSRect(x: 0, y: 0, width: 614, height: 68)
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
