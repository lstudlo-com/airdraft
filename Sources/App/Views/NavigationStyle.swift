import SwiftUI

// THESIS: Quiet navigation and a focused profile editor, following the user's Codex reference.
// OWN-WORLD: System type, monochrome SF Symbols, neutral selection, restrained native controls.
// STORY: Choose a destination or profile, edit its behavior, return to dictation.
// FIRST VIEWPORT: A 200 pt sidebar with 32 pt rows; Profiles pairs a compact list with an open editor.
// FORM: User-pinned native macOS direction; code-led, seed 43724242 (brief overrides assignment).
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
// the verdict, DESIGN.md, and every shipping raster carrying its provenance.
/// Motion shared by sliding selections: the sidebar well and segmented controls.
enum SelectionMotion {
    /// A pronounced ease-in-out S-curve: eases away from the old choice, glides, then settles.
    static let curve = Animation.timingCurve(0.65, 0, 0.35, 1, duration: 0.36)
}

enum NavigationStyle {
    static let rowHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 7
    /// Shared by the selected destination well and the microphone well, whose heights differ.
    static let wellRadius: CGFloat = 12
    static var wellShape: RoundedRectangle { RoundedRectangle(cornerRadius: wellRadius, style: .continuous) }
}

/// Shared selection, hover and press treatment for navigation and profile rows.
/// With `slidingSelection`, the selected row draws nothing: its container slides one
/// `SidebarSelectionWell` between rows instead (see `View.sidebarSelectionWell`).
struct NavigationRowStyle: ButtonStyle {
    var selected = false
    var slidingSelection = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected, slidingSelection: slidingSelection)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let slidingSelection: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background {
                    if !(selected && slidingSelection) {
                        RoundedRectangle(cornerRadius: slidingSelection ? NavigationStyle.wellRadius : NavigationStyle.cornerRadius,
                                         style: .continuous)
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : selected ? 0.09 : hovering ? 0.045 : 0))
                    }
                }
                .onHover { hovering = $0 }
        }
    }
}

/// Row bounds published by sliding-selection rows, keyed by their identifier.
struct SidebarSelectionAnchors<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [ID: Anchor<CGRect>], nextValue: () -> [ID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Publishes this row's bounds so the container's selection well can travel to it.
    func sidebarSelectionAnchor<ID: Hashable>(_ id: ID) -> some View {
        anchorPreference(key: SidebarSelectionAnchors<ID>.self, value: .bounds) { [id: $0] }
    }

    /// Draws the microphone's recessed well behind the selected row and slides it to a
    /// newly selected row on a fast ease-out cubic curve, wherever the change came from.
    func sidebarSelectionWell<ID: Hashable>(selection: ID) -> some View {
        backgroundPreferenceValue(SidebarSelectionAnchors<ID>.self) { anchors in
            SidebarSelectionWell(anchor: anchors[selection], selection: selection)
        }
    }
}

private struct SidebarSelectionWell<ID: Hashable>: View {
    let anchor: Anchor<CGRect>?
    let selection: ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        GeometryReader { proxy in
            if let anchor {
                let rect = proxy[anchor]
                NeumorphicSurface(shape: NavigationStyle.wellShape, inset: true, depth: 2.5)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .animation(reduceMotion ? nil : SelectionMotion.curve, value: selection)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
