import AppKit
import AVFoundation
import AirdraftCore
import SwiftUI

enum Theme {
    static let windowWidth: CGFloat = 784
    static let windowMinHeight: CGFloat = 600
    static let windowControlsInset: CGFloat = 16
    static let titlebarHeight: CGFloat = 46
    static let sidebarToggleWidth: CGFloat = 28
    static let sidebarToggleSymbolSize: CGFloat = 14
    static let sidebarWidth: CGFloat = 180
    static let sidebarContentInset: CGFloat = 10
    static let sidebarBrandInset: CGFloat = 10
    static let sidebarBrandHeight: CGFloat = 28
    /// Destination, microphone and account symbols in the sidebar.
    static let sidebarIconSize: CGFloat = 13
    static let sidebarBrandWidth: CGFloat = 744 * sidebarBrandHeight / 364
    static let sidebarCollapsedWidth = sidebarBrandWidth + 2 * (sidebarContentInset + sidebarBrandInset)
    // Pages sit on one rounded island in the window chrome. Its gutter repeats the
    // sidebar's inset, so the selected row is centred between the window edge and the island.
    static let islandInset: CGFloat = sidebarContentInset
    static let islandRadius: CGFloat = 12
    static let pagePadding: CGFloat = 24
    static let pageHeaderTopInset: CGFloat = 16
    static let pageHeaderRowHeight: CGFloat = 32
    static let pageHeaderBottomInset: CGFloat = 12
    static let pageHeaderBlurRadius: CGFloat = 32
    // Center the heading row in the full blur, including its 4 pt outer feather.
    static let pageHeaderBlurExtension = pageHeaderTopInset - pageHeaderBottomInset
    // The sidebar toggle sits in the island's heading row whether the sidebar is expanded
    // or collapsed, with its symbol on the page title's leading inset.
    static func sidebarToggleLeading(sidebarWidth: CGFloat) -> CGFloat {
        sidebarWidth + pagePadding - (sidebarToggleWidth - sidebarToggleSymbolSize) / 2
    }
    static let sidebarToggleTop = islandInset + pageHeaderTopInset
    static let pageHeaderToggleInset = (sidebarToggleWidth + sidebarToggleSymbolSize) / 2
        + controlSpacing
    static let cardPadding: CGFloat = 16
    static let modelTableMaxHeight: CGFloat = 300
    static let sectionSpacing: CGFloat = 28
    static let sectionTitleSpacing: CGFloat = 12
    static let sectionTitleMinHeight: CGFloat = 32
    static let sectionTitleLeadingInset: CGFloat = 4
    static let controlSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 18
    // Floating panels use the sidebar's scale: 32 pt rows inside a small inset, with a
    // corner concentric to the 7 pt row selection.
    static let overlayPadding: CGFloat = 8
    static let overlayRowInset: CGFloat = 10
    static let overlayRadius: CGFloat = NavigationStyle.cornerRadius + overlayPadding
    static let supportingFont = Font.system(size: 11, weight: .regular)
    /// Width of text fields and model pickers in settings rows.
    static let fieldWidth: CGFloat = 240
    /// The page island is a mid-tone at the Home hero's surface gray (0.91–0.89 light,
    /// 0.19–0.17 dark), so neumorphic surfaces rise from it, and below the chrome.
    static let islandBackground = Color(nsColor: NSColor(name: "airdraft.island") { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.15 : 0.90, alpha: 1)
    })
    /// The opaque window chrome behind the sidebar and around the island, lighter than the island.
    static let chromeNSColor = NSColor(name: "airdraft.chrome") { appearance in
        NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.21 : 0.95, alpha: 1)
    }
    static let chromeBackground = Color(nsColor: chromeNSColor)
}

/// The window chrome behind the sidebar and around the page island: one opaque color,
/// with no desktop blur, lighter than the island, which keeps the Home hero's gray.
struct SidebarBackground: View {
    var body: some View {
        Theme.chromeBackground
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// One rounded surface for page content, inset into the window chrome on its
/// top, trailing and bottom edges. The sidebar's own inset is its leading gutter.
/// It sits below the lighter chrome, so a hairline edge separates it without a shadow.
private struct ContentIsland: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.islandRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.islandBackground)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : scheme == .dark ? 0.08 : 0.06),
                                   lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .padding([.top, .bottom, .trailing], Theme.islandInset)
    }
}

extension View {
    func contentIsland() -> some View {
        modifier(ContentIsland())
    }
}

/// Configures the opaque main window: chrome background, inset window buttons, no zoom or
/// full screen, and pointer focus dismissal.
struct WindowChromeView: NSViewRepresentable {
    var onPointerDown: () -> Void = {}

    final class BackingView: NSView {
        var onPointerDown: () -> Void = {}
        private var pointerMonitor: Any?

        deinit {
            if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
            pointerMonitor = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize),
                                                      name: NSWindow.didResizeNotification, object: window)
                pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }
                    self.onPointerDown()
                    Self.dismissFocus(in: window, at: event.locationInWindow)
                    return event
                }
            }
            configureWindow()
        }

        /// Clear stale control focus before dispatching the click to its new target.
        /// Leave clicks within the current editor alone so selection and IME composition survive.
        static func dismissFocus(in window: NSWindow, at point: NSPoint) {
            if let editor = window.firstResponder as? NSTextView {
                if editor.bounds.intersection(editor.visibleRect).contains(editor.convert(point, from: nil)) { return }
                if editor.isFieldEditor, let field = editor.delegate as? NSView,
                   field.bounds.intersection(field.visibleRect).contains(field.convert(point, from: nil)) { return }
            }
            window.makeFirstResponder(nil)
        }

        override func layout() {
            super.layout()
            positionWindowControls()
        }

        @objc private func windowDidResize(_ notification: Notification) {
            positionWindowControls()
        }

        func configureWindow() {
            window?.isOpaque = true
            window?.backgroundColor = Theme.chromeNSColor
            window?.titlebarAppearsTransparent = true
            if let zoom = window?.standardWindowButton(.zoomButton), !zoom.isHidden {
                zoom.isHidden = true
            }
            window?.collectionBehavior.remove([.fullScreenPrimary, .fullScreenAuxiliary, .fullScreenAllowsTiling])
            window?.collectionBehavior.insert([.fullScreenNone, .fullScreenDisallowsTiling])
            positionWindowControls()
        }

        private func positionWindowControls() {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  let minimize = window.standardWindowButton(.miniaturizeButton),
                  let titlebar = close.superview?.superview else { return }

            // Grow the native titlebar so inset buttons retain their full hit areas.
            let spacing = minimize.frame.minX - close.frame.minX
            var frame = titlebar.frame
            frame.size.height = Theme.titlebarHeight
            frame.origin.y = window.frame.height - frame.height
            if titlebar.frame != frame { titlebar.frame = frame }
            let y = frame.height - Theme.windowControlsInset - close.frame.height
            close.setFrameOrigin(NSPoint(x: Theme.windowControlsInset, y: y))
            minimize.setFrameOrigin(NSPoint(x: Theme.windowControlsInset + spacing, y: y))
        }
    }

    func makeNSView(context: Context) -> BackingView { BackingView() }
    func updateNSView(_ view: BackingView, context: Context) {
        view.onPointerDown = onPointerDown
        view.configureWindow()
    }
}

/// A section card raised from the island like the Home hero, at half its spread.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .background {
                SoftRaisedSurface(shape: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous), elevation: .card)
            }
    }
}

private struct SettingRowInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 11
}

extension EnvironmentValues {
    var settingRowInset: CGFloat {
        get { self[SettingRowInsetKey.self] }
        set { self[SettingRowInsetKey.self] = newValue }
    }
}

/// The card owns all four outer insets; rows add no second vertical inset.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Card(spacing: Theme.controlSpacing) { content }
            .environment(\.settingRowInset, 0)
    }
}

struct PageSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.title = title
        self.content = content()
        self.trailing = EmptyView()
    }

    init(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self.trailing = trailing()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            SectionTitle(title) { trailing }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.sectionTitleLeadingInset)
            Spacer()
            trailing
        }
        .frame(maxWidth: .infinity, minHeight: Theme.sectionTitleMinHeight)
    }
}

extension View {
    /// Keep the visible edge of a native picker at the settings card's trailing inset.
    /// Pages use `SoftPicker`; this remains for native pickers outside the page cards.
    func settingsPicker(width: CGFloat) -> some View {
        labelsHidden().frame(width: width, alignment: .trailing)
    }
}

/// An editable numeric setting with the native stepper available for small changes.
struct SettingsNumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    @State private var draft: String
    @FocusState private var isEditing: Bool

    init(title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, unit: String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self._draft = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $draft)
                .multilineTextAlignment(.trailing)
                .focused($isEditing)
                .softField(focused: isEditing)
                .frame(width: 60)
                .onSubmit(commit)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                stepButton("minus", label: "Decrease \(title)", by: -step)
                stepButton("plus", label: "Increase \(title)", by: step)
            }
        }
        .onChange(of: value) { _, newValue in
            if !isEditing { draft = String(newValue) }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { commit() }
        }
    }

    /// Raised round buttons replace the native stepper arrows.
    private func stepButton(_ symbol: String, label: String, by delta: Int) -> some View {
        Button {
            set(value + delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(SoftIconButtonStyle())
        .disabled(delta < 0 ? value <= range.lowerBound : value >= range.upperBound)
        .accessibilityLabel(label)
    }

    private func set(_ newValue: Int) {
        value = min(max(newValue, range.lowerBound), range.upperBound)
        draft = String(value)
    }

    private func commit() {
        guard let entered = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            draft = String(value)
            return
        }
        value = min(max(entered, range.lowerBound), range.upperBound)
        draft = String(value)
    }
}

/// Title + optional subtitle on the left, any control on the right.
struct SettingRow<Trailing: View>: View {
    @Environment(\.settingRowInset) private var rowInset
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).supportingText()
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, rowInset)
    }
}

extension View {
    /// Descriptions stay smaller and quieter than the setting they explain.
    func supportingText() -> some View {
        font(Theme.supportingFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A separator engraved into the raised card: a shade line under the top-left light with
/// a highlight line just below it, like the cards' own light and shade.
struct RowDivider: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        let increased = contrast == .increased
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(increased ? (dark ? 0.7 : 0.35) : (dark ? 0.42 : 0.13)))
            Rectangle().fill(Color.white.opacity(dark ? 0.09 : 0.85))
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .frame(minWidth: 24)
            .background {
                NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 5, style: .continuous), depth: 1.2)
            }
    }
}

/// A hotkey as separate key caps: ⌥ Space.
struct KeyCaps: View {
    let hotkey: Hotkey
    var body: some View {
        HStack(spacing: 5) {
            ForEach(hotkey.keyCaps, id: \.self) { KeyCap(text: $0) }
        }
    }
}

/// Coloured rounded square with a white symbol, identifying a local model.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

struct PillTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.4)
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// Selectable preview tile (theme / recording window pickers).
struct ChoiceTile<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var preview: Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 96, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(5)
                    .background {
                        NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), inset: true, depth: 2)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

/// A raised capsule that sinks into an inset well while pressed.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(configuration: configuration)
    }

    private struct SoftButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .softControlSurface(pressed: configuration.isPressed)
                .foregroundStyle(.primary)
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

/// A round raised button for a single symbol, such as the stepper's minus and plus.
struct SoftIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftIconBody(configuration: configuration)
    }

    private struct SoftIconBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .background { SoftRaisedSurface(shape: Circle(), pressed: configuration.isPressed) }
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

private struct SoftControlSurface: ViewModifier {
    var pressed = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: SoftControl.height)
            .background { SoftRaisedSurface(shape: Capsule(), pressed: pressed) }
            .contentShape(Capsule())
    }
}

extension View {
    func softControlSurface(pressed: Bool = false) -> some View {
        modifier(SoftControlSurface(pressed: pressed))
    }
}

/// The same compact selector is used by every page-level filter.
struct PageFilter<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.0
                } label: {
                    if selection == option.0 {
                        Label(option.1, systemImage: "checkmark")
                    } else {
                        Text(option.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.0 == selection }?.1 ?? title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .softControlSurface()
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.0 == selection }?.1 ?? title)
    }
}

/// A fixed page heading above content that becomes more blurred toward the top.
struct PageScaffold<Content: View, Accessory: View>: View {
    @Environment(AppContainer.self) private var container
    let page: Page
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory
    var scrollsContent: Bool
    var contentTopInset: CGFloat

    init(_ page: Page, scrollsContent: Bool = true, contentTopInset: CGFloat = Theme.pagePadding, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.page = page
        self.content = content()
        self.accessory = accessory()
        self.scrollsContent = scrollsContent
        self.contentTopInset = contentTopInset
    }

    init(_ page: Page, scrollsContent: Bool = true, contentTopInset: CGFloat = Theme.pagePadding, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.page = page
        self.content = content()
        self.accessory = EmptyView()
        self.scrollsContent = scrollsContent
        self.contentTopInset = contentTopInset
    }

    var body: some View {
        pageBody
            .safeAreaInset(edge: .top, spacing: 0) {
                header.background(alignment: .top) { PageHeaderBackdrop() }
            }
    }

    private var pageBody: some View {
        Group {
            if scrollsContent {
                ScrollView { pageContent }
                    .pageScrollEdge()
            } else {
                pageContent.frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.controlSpacing) {
            Text(page.title)
                .font(.system(size: 20, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.controlSpacing)
            accessory
        }
        .padding(.leading, Theme.pageHeaderToggleInset)
        .padding(.horizontal, Theme.pagePadding)
        .frame(height: Theme.pageHeaderRowHeight)
        .padding(.top, Theme.pageHeaderTopInset)
        .padding(.bottom, Theme.pageHeaderBottomInset)
        .accessibilityIdentifier("page.header")
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            content
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, Theme.pagePadding)
        .padding(.top, contentTopInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The shared blur owns the transition; suppress the system's hard scroll-edge separator.
    @ViewBuilder func pageScrollEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}

/// Blur starts in the content inset below the header and grows toward its top.
/// Header labels and controls sit above the filtered layer.
private struct PageHeaderBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let headerHeight = Theme.pageHeaderTopInset + Theme.pageHeaderRowHeight + Theme.pageHeaderBottomInset
        Group {
            if reduceTransparency {
                Theme.islandBackground
                    .frame(height: headerHeight)
            } else {
                ProgressiveHeaderBlur(maximumRadius: Theme.pageHeaderBlurRadius)
                    .frame(height: headerHeight + Theme.pageHeaderBlurExtension)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Five-segment meter used in the model table.
struct SegmentMeter: View {
    /// nil means unmeasured, distinct from a measured zero.
    let fraction: Double?
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        if let fraction {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.primary.opacity(0.7))
                                .frame(width: 9 * min(1, max(0, fraction * 5 - Double(i))))
                        }
                    }
                    .frame(width: 9, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Toolbar-style search field.
struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 13))
        }
        .padding(.horizontal, 9)
        .frame(height: SoftControl.height)
        .background { SoftRaisedSurface(shape: Capsule()) }
        .frame(width: 220)
    }
}

/// The one status indicator: setup checks, permissions, model and server state.
struct StatusDot: View {
    enum Tone { case ok, attention, busy, inactive }
    let tone: Tone

    init(_ tone: Tone) { self.tone = tone }
    init(ok: Bool) { tone = ok ? .ok : .attention }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch tone {
        case .ok: return .green
        case .attention: return .orange
        case .busy: return .yellow
        case .inactive: return Color.secondary.opacity(0.5)
        }
    }

    private var label: String {
        switch tone {
        case .ok: return "Ready"
        case .attention: return "Needs attention"
        case .busy: return "In progress"
        case .inactive: return "Off"
        }
    }
}

/// Reloads a list from its source; shows progress while loading.
struct RefreshButton: View {
    let loading: Bool
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
        }
        .buttonStyle(SoftButtonStyle())
        .disabled(loading || disabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Short secondary text for an empty list or search without results.
struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).supportingText()
    }
}

extension View {
    /// Shared look for disclosure groups on settings pages. Only the header is styled.
    func settingsDisclosure() -> some View {
        disclosureGroupStyle(SettingsDisclosureStyle())
    }
}

struct SettingsDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chrome shared by the window's floating panels. Compact by design: an 8 pt inset,
/// a 28 pt heading row, and content that brings its own 32 pt rows.
struct OverlayPanel<Content: View>: View {
    @FocusState private var closeFocused: Bool
    let title: String
    var width: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.overlayRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close \(title)")
                .focused($closeFocused)
            }
            // The title lines up with row text; the glyph, not its hit area, lines up with row trailing content.
            .padding(.leading, Theme.overlayRowInset)
            .padding(.trailing, Theme.overlayRowInset - 7)
            .frame(height: NavigationStyle.rowHeight - 4)
            content
        }
        .padding(Theme.overlayPadding)
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor), in: shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .background {
            SurfaceShadows(shape: shape, shadows: [
                .init(color: .black.opacity(0.24), radius: 28, x: 6, y: 12),
            ])
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { closeFocused = true }
    }
}
