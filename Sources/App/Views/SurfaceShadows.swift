import SwiftUI

/// Draws independent shadows in SwiftUI's top-left coordinate space.
/// AppKit's cacheDisplay path can invert View.shadow's vertical offset;
/// Canvas keeps the same direction in live windows and offscreen renders.
struct SurfaceShadows<S: Shape>: View {
    struct Shadow {
        let color: Color
        let radius: CGFloat
        var x: CGFloat = 0
        var y: CGFloat = 0
    }

    let shape: S
    let shadows: [Shadow]
    /// Translucent faces must not reveal the shadow's solid interior.
    var excludesInterior = false

    var body: some View {
        let margin = shadows.map { $0.radius * 3 + max(abs($0.x), abs($0.y)) }.max() ?? 0
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
            let path = shape.path(in: bounds)
            if excludesInterior {
                context.clip(to: path, options: .inverse)
            }
            for shadow in shadows {
                var layer = context
                layer.addFilter(.shadow(color: shadow.color, radius: shadow.radius,
                                        x: shadow.x, y: shadow.y, options: .shadowOnly))
                layer.fill(path, with: .color(.white))
            }
        }
        .padding(-margin)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
