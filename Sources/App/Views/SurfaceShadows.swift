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
    /// Casts the shadows inward from the area outside the shape, like an inner shadow.
    /// SwiftUI scales `.inner` shadows by their fill's opacity, which flattens translucent wells.
    var inner = false

    var body: some View {
        let margin = shadows.map { $0.radius * 3 + max(abs($0.x), abs($0.y)) }.max() ?? 0
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
            let path = shape.path(in: bounds)
            var caster = path
            if inner {
                context.clip(to: path)
                caster = Path(CGRect(origin: .zero, size: size))
                caster.addPath(path)
            } else if excludesInterior {
                context.clip(to: path, options: .inverse)
            }
            for shadow in shadows {
                var layer = context
                layer.addFilter(.shadow(color: shadow.color, radius: shadow.radius,
                                        x: shadow.x, y: shadow.y, options: .shadowOnly))
                layer.fill(caster, with: .color(.white), style: FillStyle(eoFill: inner))
            }
        }
        .padding(-margin)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Right-to-left

/// The light falls from the physical top left in every language. SwiftUI mirrors
/// `UnitPoint.topLeading` gradients, `.offset(x:)` and custom paths under a right-to-left
/// layout, while Canvas, `SurfaceShadows` and `.shadow` offsets stay physical; without
/// these, a mirrored face would be lit from the top right against its own shadows.
extension View {
    /// Draws a decorative surface left to right so its gradients keep the top-left light.
    /// Use only on symmetric shapes and artwork, never on text, symbols or layout.
    func physicalLight() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }

    /// An offset in physical points: positive `x` moves right in every layout direction.
    func physicalOffset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(PhysicalOffset(x: x, y: y))
    }
}

private struct PhysicalOffset: ViewModifier {
    let x: CGFloat
    let y: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content.offset(x: layoutDirection == .rightToLeft ? -x : x, y: y)
    }
}
