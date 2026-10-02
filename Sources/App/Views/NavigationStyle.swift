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
    /// The sidebar's icon island moves on the same curve 300 ms after its well.
    static let islandDelay: TimeInterval = 0.3
    static let islandCurve = curve.delay(islandDelay)
}

enum NavigationStyle {
    static let rowHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 7
    /// Shared by the selected destination well and the microphone button.
    static let wellRadius: CGFloat = 12
    /// Destinations are 34 points high; the microphone button is a taller 38-point control.
    /// Both are inset 4 points from the sidebar content edges, so they share one width.
    static let destinationHeight: CGFloat = 34
    static let microphoneHeight: CGFloat = 38
    static let destinationInset: CGFloat = 4
    /// The icon island (destinations) and icon socket (microphone) sit this far inside
    /// their surface's top, bottom and leading edges, like a switch knob in its track.
    static let iconIslandInset: CGFloat = 3
    static let iconIslandSize = destinationHeight - 2 * iconIslandInset
    static let microphoneSocketSize = microphoneHeight - 2 * iconIslandInset
    /// Destination and microphone labels share this start, measured inside the inset.
    static let labelStart: CGFloat = 44
    /// Concentric with the well: its corners are the well's, less the inset.
    static var iconIslandShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: wellRadius - iconIslandInset, style: .continuous)
    }
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

/// Where a sliding-selection row and its icon sit, so the well and its icon island can travel.
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

    /// Publishes the row icon's bounds so the icon island can rest beneath it.
    func sidebarSelectionIconAnchor<ID: Hashable>(_ id: ID) -> some View {
        transformAnchorPreference(key: SidebarSelectionAnchors<ID>.self, value: .bounds) { value, anchor in
            value[id, default: SidebarSelectionAnchor()].icon = anchor
        }
    }

    /// Draws the microphone's recessed well behind the selected row, with a flat raised
    /// island in it under the icon like a switch knob on its track, and slides both to a
    /// newly selected row on `SelectionMotion.curve`, wherever the change came from.
    func sidebarSelectionWell<ID: Hashable>(selection: ID) -> some View {
        backgroundPreferenceValue(SidebarSelectionAnchors<ID>.self) { anchors in
            SidebarSelectionWell(anchor: anchors[selection], selection: selection)
        }
    }
}

private struct SidebarSelectionWell<ID: Hashable>: View {
    let anchor: SidebarSelectionAnchor?
    let selection: ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let row = anchor?.row {
                let rect = proxy[row]
                let side = rect.height - 2 * NavigationStyle.iconIslandInset
                ZStack(alignment: .topLeading) {
                    NeumorphicSurface(shape: NavigationStyle.wellShape, inset: true, depth: 2.5)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .animation(reduceMotion ? nil : SelectionMotion.curve, value: selection)
                    if let icon = anchor?.icon {
                        let center = proxy[icon]
                        // The island follows the well after a pause, and is only ever visible
                        // inside the moving well: its light and shade never leave it.
                        SoftWellIsland()
                            .frame(width: side, height: side)
                            .offset(x: center.midX - side / 2, y: center.midY - side / 2)
                            .animation(reduceMotion ? nil : SelectionMotion.islandCurve, value: selection)
                            .mask(alignment: .topLeading) {
                                NavigationStyle.wellShape
                                    .frame(width: rect.width, height: rect.height)
                                    .offset(x: rect.minX, y: rect.minY)
                                    .animation(reduceMotion ? nil : SelectionMotion.curve, value: selection)
                            }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
