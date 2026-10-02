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

/// Where a sliding-selection row and its icon sit, so the well and its icon disc can travel.
struct SidebarSelectionAnchor {
    var row: Anchor<CGRect>?
    var icon: Anchor<CGRect>?
}

/// Row and icon bounds published by sliding-selection rows, keyed by their identifier.
struct SidebarSelectionAnchors<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: SidebarSelectionAnchor] { [:] }
    static func reduce(value: inout [ID: SidebarSelectionAnchor], nextValue: () -> [ID: SidebarSelectionAnchor]) {
        value.merge(nextValue()) { old, new in
            SidebarSelectionAnchor(row: new.row ?? old.row, icon: new.icon ?? old.icon)
        }
    }
}

extension View {
    /// Publishes this row's bounds so the container's selection well can travel to it.
    func sidebarSelectionAnchor<ID: Hashable>(_ id: ID) -> some View {
        transformAnchorPreference(key: SidebarSelectionAnchors<ID>.self, value: .bounds) { value, anchor in
            value[id, default: SidebarSelectionAnchor()].row = anchor
        }
    }

    /// Publishes the row icon's bounds so the raised icon disc can float beneath it.
    func sidebarSelectionIconAnchor<ID: Hashable>(_ id: ID) -> some View {
        transformAnchorPreference(key: SidebarSelectionAnchors<ID>.self, value: .bounds) { value, anchor in
            value[id, default: SidebarSelectionAnchor()].icon = anchor
        }
    }

    /// Draws the microphone's recessed well behind the selected row, with a raised disc
    /// floating in it under the icon like a switch knob on its track, and slides both to a
    /// newly selected row on `SelectionMotion.curve`, wherever the change came from.
    func sidebarSelectionWell<ID: Hashable>(selection: ID) -> some View {
        backgroundPreferenceValue(SidebarSelectionAnchors<ID>.self) { anchors in
            SidebarSelectionWell(anchor: anchors[selection], selection: selection)
        }
    }
}

enum SidebarIconDisc {
    /// Leaves a 5-point margin of well around the disc in a 32-point row.
    static let diameter: CGFloat = 22
}

private struct SidebarSelectionWell<ID: Hashable>: View {
    let anchor: SidebarSelectionAnchor?
    let selection: ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let row = anchor?.row {
                    let rect = proxy[row]
                    NeumorphicSurface(shape: NavigationStyle.wellShape, inset: true, depth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                if let icon = anchor?.icon {
                    let rect = proxy[icon]
                    NeumorphicSurface(shape: Circle(), depth: 1.5)
                        .frame(width: SidebarIconDisc.diameter, height: SidebarIconDisc.diameter)
                        .offset(x: rect.midX - SidebarIconDisc.diameter / 2, y: rect.midY - SidebarIconDisc.diameter / 2)
                }
            }
            .animation(reduceMotion ? nil : SelectionMotion.curve, value: selection)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
