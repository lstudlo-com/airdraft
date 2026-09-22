import SwiftUI

// THESIS: Quiet navigation and a focused profile editor, following the user's Codex reference.
// OWN-WORLD: System type, monochrome SF Symbols, neutral selection, restrained native controls.
// STORY: Choose a destination or profile, edit its behavior, return to dictation.
// FIRST VIEWPORT: A 200 pt sidebar with 32 pt rows; Profiles pairs a compact list with an open editor.
// FORM: User-pinned native macOS direction; code-led, seed 43724242 (brief overrides assignment).
// FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
// the verdict, DESIGN.md, and every shipping raster carrying its provenance.
enum NavigationStyle {
    static let rowHeight: CGFloat = 32
    static let cornerRadius: CGFloat = 7
}

/// Shared selection, hover and press treatment for navigation and profile rows.
struct NavigationRowStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background {
                    RoundedRectangle(cornerRadius: NavigationStyle.cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : selected ? 0.09 : hovering ? 0.045 : 0))
                }
                .onHover { hovering = $0 }
        }
    }
}
