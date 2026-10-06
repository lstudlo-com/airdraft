import AirdraftCore
import AppKit
import Observation
import SwiftUI

/// Owns query work separately from row rendering. No persistence, I/O or setting writes.
@MainActor @Observable
final class SettingsSearchState {
    var query = "" {
        didSet {
            let active = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if active != isSearching { isSearching = active }
        }
    }
    private(set) var isSearching = false
    private(set) var appliedQuery = ""
    private(set) var matches: [SettingsSearchDocument] = []
    private(set) var selectedID: SettingsSearchDocument.ID?
    private(set) var matchedIDs = Set<SettingsSearchDocument.ID>()
    private(set) var scrollRequest = 0
    @ObservationIgnored private var documents: [SettingsSearchDocument] = []
    @ObservationIgnored private var index = SettingsSearchIndex([])
    #if DEBUG
    @ObservationIgnored private(set) var indexBuilds = 0
    @ObservationIgnored private(set) var queryPasses = 0
    #endif

    var selectedIndex: Int? { matches.firstIndex { $0.id == selectedID } }

    func replaceDocuments(_ documents: [SettingsSearchDocument]) {
        guard self.documents != documents else { return }
        self.documents = documents
        index = SettingsSearchIndex(documents)
        #if DEBUG
        indexBuilds += 1
        #endif
        // The delayed query owns typing. Copy changes refresh only the settled query.
        refresh(preservingSelection: true)
    }

    func applyQuery() {
        guard query != appliedQuery else { return }
        appliedQuery = query
        refresh(preservingSelection: false)
    }

    func move(by offset: Int) {
        if query != appliedQuery { applyQuery(); return }
        guard !matches.isEmpty else { return }
        let position = ((selectedIndex ?? 0) + offset + matches.count) % matches.count
        selectedID = matches[position].id
        scrollRequest += 1
    }

    func clear() {
        query = ""
        applyQuery()
    }

    private func refresh(preservingSelection: Bool) {
        #if DEBUG
        queryPasses += 1
        #endif
        let results = index.matches(appliedQuery)
        let ids = Set(results.map(\.id))
        let next = preservingSelection && selectedID.map(ids.contains) == true ? selectedID : results.first?.id
        matches = results
        matchedIDs = ids
        if next != selectedID || !preservingSelection {
            selectedID = next
            if next != nil { scrollRequest += 1 }
        }
    }
}

private struct SettingsSearchStateKey: EnvironmentKey {
    static let defaultValue: SettingsSearchState? = nil
}

private struct SettingsSearchSectionKey: EnvironmentKey {
    static let defaultValue = ""
}

private struct SettingsSearchRevealKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsSearch: SettingsSearchState? {
        get { self[SettingsSearchStateKey.self] }
        set { self[SettingsSearchStateKey.self] = newValue }
    }
    var settingsSearchSection: String {
        get { self[SettingsSearchSectionKey.self] }
        set { self[SettingsSearchSectionKey.self] = newValue }
    }
    /// Exposes conditional controls for discovery, without enabling their prerequisite.
    var revealSearchSettings: Bool {
        get { self[SettingsSearchRevealKey.self] }
        set { self[SettingsSearchRevealKey.self] = newValue }
    }
}

struct SettingsSearchDocumentsKey: PreferenceKey {
    static var defaultValue: [SettingsSearchDocument] = []
    static func reduce(value: inout [SettingsSearchDocument], nextValue: () -> [SettingsSearchDocument]) {
        value.append(contentsOf: nextValue())
    }
}

struct SettingsSearchScaffold<Content: View>: View {
    @Bindable var search: SettingsSearchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            PageScaffold(.configuration) {
                content
                    .environment(\.settingsSearch, search)
                    .environment(\.revealSearchSettings, search.isSearching)
            } accessory: {
                SettingsSearchField(search: search)
            }
            .onPreferenceChange(SettingsSearchDocumentsKey.self) { search.replaceDocuments($0) }
            .task(id: search.query) {
                if search.isSearching {
                    do { try await Task.sleep(for: .milliseconds(160)) }
                    catch { return }
                }
                guard !Task.isCancelled else { return }
                search.applyQuery()
            }
            .onChange(of: search.scrollRequest) { _, _ in
                guard let id = search.selectedID else { return }
                // Centering keeps the matched row below the sticky header's blur.
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

/// Section/row copy is the index source, including descriptions that change with state.
/// This is inert outside a page that opts into settings search.
struct SearchableSetting: ViewModifier {
    @Environment(\.settingsSearch) private var search
    @Environment(\.settingsSearchSection) private var section
    let title: String
    let detail: String?
    private let highlightInset: CGFloat = 4

    func body(content: Content) -> some View {
        if let search {
            let document = SettingsSearchDocument(section: section, title: title, detail: detail ?? "")
            let matched = search.matchedIDs.contains(document.id)
            let selected = search.selectedID == document.id
            content
                .id(document.id)
                .preference(key: SettingsSearchDocumentsKey.self, value: [document])
                .background {
                    if matched {
                        NeumorphicSurface(shape: RoundedRectangle(cornerRadius: Theme.cardRadius - highlightInset, style: .continuous),
                                          inset: true, depth: selected ? 2 : 0.8)
                            .opacity(selected ? 1 : 0.55)
                            .padding(-(Theme.cardPadding - highlightInset))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.row.\(section).\(title)")
                .accessibilityValue(selected ? "Current search result" : matched ? "Search result" : "")
        } else {
            content
        }
    }
}

/// One recessed find control in the page heading; results remain in their real context.
struct SettingsSearchField: View {
    @Bindable var search: SettingsSearchState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search settings", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .accessibilityLabel("Search settings")
                .accessibilityIdentifier("settings.search")
                .onSubmit { search.move(by: NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? -1 : 1) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    guard !isComposing else { return .ignored }
                    if search.query.isEmpty { focused = false } else { search.clear() }
                    return .handled
                }
            if search.isSearching {
                Text(resultLabel)
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel(resultDescription)
                    .accessibilityIdentifier("settings.search.count")
                if search.matches.count > 1 {
                    stepButton("chevron.up", label: "Previous Setting", by: -1)
                    stepButton("chevron.down", label: "Next Setting", by: 1)
                }
            }
            if !search.query.isEmpty {
                Button { search.clear(); focused = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Clear Search (Esc)").accessibilityLabel("Clear Search")
                .accessibilityIdentifier("settings.search.clear")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 270, height: SoftControl.height)
        .background { SoftInsetTrack(shape: Capsule()) }
        .overlay { Capsule().strokeBorder(focused ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1.5).allowsHitTesting(false) }
        .background {
            Button("Find Setting") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden().accessibilityHidden(true)
        }
        .help("Search section names, settings and descriptions. Return or arrows moves between matches.")
    }

    private var resultLabel: String {
        if search.query != search.appliedQuery { return "…" }
        guard let index = search.selectedIndex else { return "No matches" }
        return "\(index + 1)/\(search.matches.count)"
    }

    private var resultDescription: String {
        guard let index = search.selectedIndex else { return resultLabel }
        let result = search.matches[index]
        return "Result \(index + 1) of \(search.matches.count), \(result.section), \(result.title)"
    }

    private var isComposing: Bool { (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard !isComposing, !search.matches.isEmpty else { return .ignored }
        search.move(by: offset)
        return .handled
    }

    private func stepButton(_ symbol: String, label: String, by offset: Int) -> some View {
        Button { search.move(by: offset); focused = true } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 24)
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .help(label).accessibilityLabel(label)
    }
}
