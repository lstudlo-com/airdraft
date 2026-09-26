import AppKit
import QuartzCore
import SwiftUI

/// Samples the live content behind the header without fading in an opaque fill.
/// Core Animation's variable backdrop blur is not a public API. Keep all runtime
/// access here; unsupported systems use a standard within-window material.
struct ProgressiveHeaderBlur: NSViewRepresentable {
    var maximumRadius: CGFloat

    func makeNSView(context: Context) -> ProgressiveHeaderBlurView {
        ProgressiveHeaderBlurView(maximumRadius: maximumRadius)
    }

    func updateNSView(_ view: ProgressiveHeaderBlurView, context: Context) {
        view.maximumRadius = maximumRadius
    }
}

final class ProgressiveHeaderBlurView: NSView {
    var maximumRadius: CGFloat {
        didSet { if maximumRadius != oldValue { needsLayout = true } }
    }
    private let backdrop: CALayer?
    private let variableBlur: NSObject?
    private let fallback: NSVisualEffectView?
    private var appliedSize = CGSize.zero
    private var appliedScale: CGFloat = 0
    private var appliedRadius: CGFloat = -1

    /// Alpha encodes radius, not the opacity of the displayed background.
    /// The first image row is the top of the header, the last is its bottom.
    static let radiusMask: CGImage = {
        let height = 256
        let bytes: [UInt8] = (0..<height).flatMap { row in
            let alpha = UInt8(255 - row)
            return [alpha, alpha, alpha, alpha]
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: 1, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }()

    init(maximumRadius: CGFloat) {
        self.maximumRadius = maximumRadius
        let selector = NSSelectorFromString("filterWithType:")
        let keysSelector = NSSelectorFromString("inputKeys")
        if let layerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
           filterClass.responds(to: selector),
           let filter = filterClass.perform(selector, with: "variableBlur")?.takeUnretainedValue() as? NSObject,
           filter.responds(to: keysSelector),
           let keys = filter.perform(keysSelector)?.takeUnretainedValue() as? [String],
           Set(["inputRadius", "inputMaskImage", "inputNormalizeEdges"]).isSubset(of: Set(keys)) {
            backdrop = layerClass.init()
            variableBlur = filter
            fallback = nil
        } else {
            backdrop = nil
            variableBlur = nil
            fallback = NSVisualEffectView()
        }
        super.init(frame: .zero)
        setAccessibilityElement(false)
        wantsLayer = true
        layer?.masksToBounds = true
        if let backdrop {
            layer?.addSublayer(backdrop)
        } else if let fallback {
            fallback.material = .headerView
            fallback.blendingMode = .withinWindow
            fallback.state = .active
            addSubview(fallback)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fallback?.frame = bounds
        guard let backdrop, let variableBlur, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        guard bounds.size != appliedSize || scale != appliedScale || maximumRadius != appliedRadius else { return }
        appliedSize = bounds.size
        appliedScale = scale
        appliedRadius = maximumRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        backdrop.contentsScale = scale
        // Reattach after changing inputs. Never alter a filter while it is installed.
        backdrop.filters = nil
        variableBlur.setValue(maximumRadius, forKey: "inputRadius")
        variableBlur.setValue(Self.radiusMask, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")
        backdrop.filters = [variableBlur]
        CATransaction.commit()
    }
}
