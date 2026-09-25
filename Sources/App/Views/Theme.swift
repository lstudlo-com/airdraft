import AppKit
import AVFoundation
import AirdraftCore
import SwiftUI

enum Theme {
    static let windowWidth: CGFloat = 784
    static let windowMinHeight: CGFloat = 600
    static let windowControlsInset: CGFloat = 16
    static let titlebarHeight: CGFloat = 46
    static let sidebarToggleLeading: CGFloat = 73
    static let sidebarToggleWidth: CGFloat = 28
    static let sidebarWidth: CGFloat = 200
    static let sidebarContentInset: CGFloat = 10
    static let sidebarBrandInset: CGFloat = 10
    static let sidebarBrandHeight: CGFloat = 25
    static let sidebarBrandWidth: CGFloat = 744 * sidebarBrandHeight / 364
    static let sidebarCollapsedWidth = sidebarBrandWidth + 2 * (sidebarContentInset + sidebarBrandInset)
    static let pagePadding: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let sectionTitleSpacing: CGFloat = 12
    static let sectionTitleMinHeight: CGFloat = 32
    static let sectionTitleLeadingInset: CGFloat = 4
    static let controlSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 18
    /// Width of text fields and model pickers in settings rows.
    static let fieldWidth: CGFloat = 240
}

/// Window-level blur behind the sidebar.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// The upper half keeps native desktop blur; the lower half fades to an opaque base.
struct SidebarBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let tint = Color(white: scheme == .dark ? 0.12 : 0.86)
        let translucentTint = tint.opacity(reduceTransparency ? 1 : 0.70)

        ZStack {
            if !reduceTransparency {
                VisualEffectView(material: .sidebar)
            }
            LinearGradient(
                stops: [
                    .init(color: translucentTint, location: 0),
                    .init(color: translucentTint, location: 0.5),
                    .init(color: tint, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Let the sidebar material sample the desktop behind the window.
struct TranslucentWindowView: NSViewRepresentable {
    final class BackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize),
                                                      name: NSWindow.didResizeNotification, object: window)
            }
            configureWindow()
        }

        override func layout() {
            super.layout()
            positionWindowControls()
        }

        @objc private func windowDidResize(_ notification: Notification) {
            positionWindowControls()
        }

        func configureWindow() {
            window?.isOpaque = false
            window?.backgroundColor = .clear
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
    func updateNSView(_ view: BackingView, context: Context) { view.configureWindow() }
}

/// Rounded, softly filled container for a group of rows.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.cardPadding
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
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
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
                .focused($isEditing)
                .onSubmit(commit)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
            Stepper(title, value: Binding(
                get: { value },
                set: { newValue in
                    value = newValue
                    draft = String(newValue)
                }
            ), in: range, step: step)
                .labelsHidden()
                .accessibilityLabel("Adjust \(title)")
        }
        .onChange(of: value) { _, newValue in
            if !isEditing { draft = String(newValue) }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { commit() }
        }
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
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, rowInset)
    }
}

struct RowDivider: View {
    var body: some View { Divider().opacity(0.45) }
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

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .softControlSurface(pressed: configuration.isPressed)
            .foregroundStyle(.primary)
    }
}

private struct SoftControlSurface: ViewModifier {
    var pressed = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(Capsule().fill(Color.primary.opacity(pressed ? 0.16 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
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

/// Shared page header: destination title on the left, page controls on the right.
struct PageScaffold<Content: View, Accessory: View>: View {
    let page: Page
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory
    var scrollsContent: Bool

    init(_ page: Page, scrollsContent: Bool = true, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.page = page
        self.content = content()
        self.accessory = accessory()
        self.scrollsContent = scrollsContent
    }

    init(_ page: Page, scrollsContent: Bool = true, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.page = page
        self.content = content()
        self.accessory = EmptyView()
        self.scrollsContent = scrollsContent
    }

    var body: some View {
        Group {
            if scrollsContent {
                ScrollView { pageContent }
            } else {
                pageContent.frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            HStack(spacing: Theme.controlSpacing) {
                Text(page.title)
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Theme.controlSpacing)
                accessory
            }
            .frame(minHeight: 30)
            content
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
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
        Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
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

/// Chrome shared by the window's floating panels (microphone, account).
struct OverlayPanel<Content: View>: View {
    @FocusState private var closeFocused: Bool
    let title: String
    var subtitle: String? = nil
    var width: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close \(title)")
                .focused($closeFocused)
            }
            content
        }
        .padding(Theme.pagePadding)
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .background {
            SurfaceShadows(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), shadows: [
                .init(color: .black.opacity(0.24), radius: 28, x: 6, y: 12),
            ])
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { closeFocused = true }
    }
}
