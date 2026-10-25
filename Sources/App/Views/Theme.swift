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
    // Extend the original 64 pt blur to 80 pt without moving the 60 pt header.
    static let pageHeaderBlurExtension: CGFloat = 20
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

        isolated deinit {
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
            let spacing = abs(minimize.frame.minX - close.frame.minX)
            var frame = titlebar.frame
            frame.size.height = Theme.titlebarHeight
            frame.origin.y = window.frame.height - frame.height
            if titlebar.frame != frame { titlebar.frame = frame }
            let y = frame.height - Theme.windowControlsInset - close.frame.height
            let x = Self.windowControlOrigins(containerWidth: close.superview?.bounds.width ?? window.frame.width,
                                              buttonWidth: close.frame.width, spacing: spacing,
                                              rightToLeft: window.windowTitlebarLayoutDirection == .rightToLeft)
            close.setFrameOrigin(NSPoint(x: x.close, y: y))
            minimize.setFrameOrigin(NSPoint(x: x.minimize, y: y))
        }

        /// The window buttons' x positions, inset from the leading edge. A right-to-left
        /// titlebar keeps AppKit's mirrored order: Close at the right, Minimize to its left.
        nonisolated static func windowControlOrigins(containerWidth: CGFloat, buttonWidth: CGFloat, spacing: CGFloat,
                                                     rightToLeft: Bool) -> (close: CGFloat, minimize: CGFloat) {
            guard rightToLeft else { return (Theme.windowControlsInset, Theme.windowControlsInset + spacing) }
            let close = containerWidth - Theme.windowControlsInset - buttonWidth
            return (close, close - spacing)
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

    init(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.title = String(localized: title)
        self.content = content()
        self.trailing = EmptyView()
    }

    init(_ title: LocalizedStringResource, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = String(localized: title)
        self.content = content()
        self.trailing = trailing()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            SectionTitle(title) { trailing }
            content
                .environment(\.settingsSearchSection, title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    init(_ text: LocalizedStringResource, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = String(localized: text)
        self.trailing = trailing()
    }

    /// Runtime text that is already localized, such as a formatted date.
    @_disfavoredOverload
    init(_ text: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(text)
                .appFont(.heading)
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.sectionTitleLeadingInset)
                // Section headings are VoiceOver headings, for rotor navigation between sections.
                .accessibilityAddTraits(.isHeader)
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
    @Environment(\.textScale) private var textScale
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    @State private var draft: String
    @FocusState private var isEditing: Bool

    init(title: LocalizedStringResource, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         unit: LocalizedStringResource) {
        self.title = String(localized: title)
        self._value = value
        self.range = range
        self.step = step
        self.unit = String(localized: unit)
        self._draft = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $draft)
                .multilineTextAlignment(.trailing)
                .focused($isEditing)
                .softField(focused: isEditing)
                .frame(width: 60 * textScale)
                .onSubmit(commit)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                stepButton("minus", label: String(localized: "Decrease \(title)"), by: -step)
                stepButton("plus", label: String(localized: "Increase \(title)"), by: step)
            }
        }
        .onChange(of: value) { _, newValue in
            if !isEditing { draft = String(newValue) }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { commit() }
        }
    }

    /// Raised square buttons replace the native stepper arrows.
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
/// Literal copy is localized; runtime text passes through `detail:` or `.verbatim`.
struct SettingRow<Trailing: View>: View {
    @Environment(\.settingRowInset) private var rowInset
    let title: String
    var subtitle: String? = nil
    var stacked = false
    @ViewBuilder var trailing: Trailing

    init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, stacked: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = String(localized: title)
        self.subtitle = subtitle.map { String(localized: $0) }
        self.stacked = stacked
        self.trailing = trailing()
    }

    /// A subtitle computed at runtime, already localized by its source.
    init(title: LocalizedStringResource, detail: String?, stacked: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = String(localized: title)
        self.subtitle = detail
        self.stacked = stacked
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: Theme.controlSpacing) {
                    label
                    trailing.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    label
                    Spacer(minLength: 12)
                    trailing
                }
            }
        }
        .padding(.vertical, rowInset)
        .modifier(SearchableSetting(title: title, detail: subtitle))
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).appFont(.body, weight: .medium)
            if let subtitle { Text(subtitle).supportingText() }
        }
    }
}

/// Quiet text that a fixed opacity would leave too faint under Increase Contrast.
private struct MutedForeground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let opacity: Double

    func body(content: Content) -> some View {
        content.foregroundStyle(Color.primary.opacity(contrast == .increased ? max(opacity, 0.9) : opacity))
    }
}

extension View {
    /// Primary text at a reduced opacity, raised to near full strength with Increase Contrast.
    func mutedForeground(_ opacity: Double) -> some View {
        modifier(MutedForeground(opacity: opacity))
    }

    /// Descriptions stay smaller and quieter than the setting they explain.
    func supportingText() -> some View {
        appFont(.supporting)
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
            .appFont(.annotation, weight: .medium, design: .rounded)
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .frame(minWidth: 24)
            .background {
                NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 5, style: .continuous), depth: 1.2)
            }
    }
}

/// A hotkey as separate key caps: ⌥ Space. Modifiers precede the key as printed on
/// the keyboard, so the caps stay in left-to-right order in every language.
/// A localized side word ("Right ⌥") still reads in the interface's direction inside its cap.
struct KeyCaps: View {
    let hotkey: Hotkey
    @Environment(\.layoutDirection) private var layoutDirection
    var body: some View {
        HStack(spacing: 5) {
            ForEach(hotkey.displayCaps, id: \.self) { KeyCap(text: $0).environment(\.layoutDirection, layoutDirection) }
        }
        .environment(\.layoutDirection, .leftToRight)
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
    @Environment(\.colorSchemeContrast) private var contrast
    let text: String
    init(text: LocalizedStringResource) { self.text = String(localized: text) }
    init(verbatim: String) { text = verbatim }
    var body: some View {
        Text(text)
            .appFont(.tag)
            .scriptAwareTracking(0.4)
            .fixedSize()
            .foregroundStyle(contrast == .increased ? .primary : .secondary)
            .padding(.horizontal, 5)
            // Devanagari and Arabic marks reach past Latin caps and descenders.
            .padding(.vertical, InterfaceScript.hasTallMarks ? 3 : 1.5)
            .background(Capsule().fill(Color.primary.opacity(contrast == .increased ? 0.12 : 0.07)))
            .overlay {
                if contrast == .increased { Capsule().strokeBorder(Color.primary.opacity(0.45), lineWidth: 0.5) }
            }
    }
}

/// Selectable preview tile (theme / recording window pickers).
struct ChoiceTile<Preview: View>: View {
    /// Already localized by the choice's model.
    let title: String
    let selected: Bool
    let action: () -> Void
    var previewSize = CGSize(width: 96, height: 60)
    @ViewBuilder var preview: Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: previewSize.width, height: previewSize.height)
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
                    .appFont(.detail, weight: selected ? .semibold : .regular)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(selected ? Text("Selected") : Text("Not selected"))
    }
}

/// A raised rounded button that sinks into an inset well while pressed.
struct SoftButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct SoftButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .appFont(.control)
                // One line: a longer translation widens the button instead of
                // wrapping inside it; neighbouring text wraps instead.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .softControlSurface(pressed: configuration.isPressed,
                                    tint: prominent ? Color(red: 0.05, green: 0.36, blue: 0.73) : nil)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .opacity(isEnabled ? 1 : 0.5)
        }
    }
}

/// A raised square button for a single symbol, such as the stepper's minus and plus.
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
                .background { SoftRaisedSurface(shape: SoftControl.shape, pressed: configuration.isPressed) }
                .contentShape(SoftControl.shape)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

private struct SoftControlSurface: ViewModifier {
    var pressed = false
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: SoftControl.height)
            .background { SoftRaisedSurface(shape: SoftControl.shape, pressed: pressed, tint: tint) }
            .contentShape(SoftControl.shape)
    }
}

extension View {
    func softControlSurface(pressed: Bool = false, tint: Color? = nil) -> some View {
        modifier(SoftControlSurface(pressed: pressed, tint: tint))
    }

    /// The single primary action everywhere, including onboarding, License and Meetings:
    /// the raised soft button with a blue face. Unlike the native prominent bezel it
    /// keeps its color when the window is not key.
    func primaryButtonStyle() -> some View {
        buttonStyle(SoftButtonStyle(prominent: true))
    }
}

/// The same compact selector is used by every page-level filter.
struct PageFilter<Selection: Hashable>: View {
    let title: LocalizedStringResource
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
                Text(current)
                    .lineLimit(1)
                Image(nsImage: Self.chevron)
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
            }
            .appFont(.control)
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(current)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .softControlSurface()
    }

    private var current: String { options.first { $0.0 == selection }?.1 ?? String(localized: title) }

    /// The chevron as a plain template image. AppKit names a menu button after any SF Symbol
    /// in its label ("Up and down chevrons"), ignoring SwiftUI's hidden flag; a drawn copy
    /// carries no symbol name, so VoiceOver reads only the filter's title and choice.
    private static var chevron: NSImage {
        let symbol = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 9, weight: .medium))!
        let image = NSImage(size: symbol.size, flipped: false) { rect in symbol.draw(in: rect); return true }
        image.isTemplate = true
        return image
    }
}

/// A pull-down menu on the shared soft button surface, for overflow actions and exports.
struct SoftMenuButton<Content: View, Label: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label
    @Environment(\.textScale) private var textScale

    var body: some View {
        if textScale == 1 {
            // The Default size keeps the native button title exactly as designed.
            Menu { content } label: { styledLabel }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .softControlSurface()
        } else {
            // AppKit draws a borderless menu button's title at its own size, so
            // above Default the label is SwiftUI text at the scaled control size.
            // The surface belongs to the label so the whole control opens the menu.
            Menu { content } label: {
                styledLabel.lineLimit(1).fixedSize()
                    .softControlSurface()
                    .contentShape(SoftControl.shape)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var styledLabel: some View {
        label
            .appFont(.control)
            .foregroundStyle(.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
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
                .appFont(.title)
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
    @Environment(\.colorSchemeContrast) private var contrast
    /// nil means unmeasured, distinct from a measured zero.
    let fraction: Double?
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    // Increase Contrast keeps unfilled segments visible against the card.
                    .fill(Color.primary.opacity(contrast == .increased ? 0.3 : 0.12))
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
    var placeholder: LocalizedStringResource = "Search"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(String(localized: placeholder), text: $text).textFieldStyle(.plain).appFont(.body)
                .accessibilityLabel(Text(placeholder))
        }
        .padding(.horizontal, 9)
        .frame(height: SoftControl.height)
        .background { SoftRaisedSurface(shape: SoftControl.shape) }
        .frame(width: 220)
    }
}

/// The one status indicator: setup checks, permissions, model and server state.
struct StatusDot: View {
    enum Tone { case ok, attention, busy, inactive }
    @Environment(\.colorSchemeContrast) private var contrast
    let tone: Tone

    init(_ tone: Tone) { self.tone = tone }
    init(ok: Bool) { tone = ok ? .ok : .attention }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                // Increase Contrast: an edge keeps pale tones (yellow, gray) visible on light surfaces.
                if contrast == .increased { Circle().strokeBorder(Color.primary.opacity(0.55), lineWidth: 0.75) }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }

    private var color: Color {
        switch tone {
        case .ok: return .green
        case .attention: return .orange
        case .busy: return .yellow
        case .inactive: return Color.secondary.opacity(0.5)
        }
    }

    private var label: Text {
        switch tone {
        case .ok: return Text("Ready")
        case .attention: return Text("Needs attention")
        case .busy: return Text("In progress")
        case .inactive: return Text("Off")
        }
    }
}

/// Reloads a list from its source; shows progress while loading.
struct RefreshButton: View {
    let loading: Bool
    let help: LocalizedStringResource
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
        }
        .buttonStyle(SoftButtonStyle())
        .disabled(loading || disabled)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }
}

/// Short secondary text for an empty list or search without results.
struct EmptyNote: View {
    let text: String
    init(_ text: LocalizedStringResource) { self.text = String(localized: text) }
    /// Runtime text, such as an error message, that is already localized.
    @_disfavoredOverload init(_ text: String) { self.text = text }
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
        SettingsDisclosure(configuration: configuration)
    }
}

private struct SettingsDisclosure: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    // Points along the reading direction; the rotation mirrors with it.
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                }
                .appFont(.detail, weight: .medium)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? Text("Expanded") : Text("Collapsed"))
            if configuration.isExpanded { configuration.content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chrome shared by the window's floating panels. Compact by design: an 8 pt inset,
/// a 28 pt heading row, and content that brings its own 32 pt rows.
struct OverlayPanel<Content: View>: View {
    @FocusState private var closeFocused: Bool
    let title: LocalizedStringResource
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
                    .appFont(.body, weight: .semibold)
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
                .accessibilityLabel(Text("Close \(String(localized: title))"))
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

extension LocalizedStringResource {
    /// Runtime text that is already localized or never translated, such as a model name.
    /// A string literal resource would still look the text up as a key in
    /// `Localizable`; this table never exists, so lookup returns the text as is.
    static func verbatim(_ text: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(text), table: verbatimTable)
    }

    static let verbatimTable = "AirdraftVerbatim"
}

/// One duration convention for Home and History: seconds, with one decimal below ten
/// ("1.3 s", "12 s"), so processing times and audio lengths read alike.
enum DurationLabel {
    static func seconds(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        let number = value < 9.95
            ? value.formatted(.number.precision(.fractionLength(1)))
            : value.formatted(.number.precision(.fractionLength(0)))
        return String(localized: "\(number) s", comment: "Audio duration in seconds")
    }

    static func milliseconds(_ milliseconds: Int) -> String {
        seconds(Double(milliseconds) / 1000)
    }
}
