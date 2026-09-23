import AppKit
import AVFoundation
import AirdraftCore
import SwiftUI

enum Theme {
    static let sidebarWidth: CGFloat = 200
    static let pagePadding: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let sectionTitleSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let contentMaxWidth: CGFloat = 860
}

/// Window-level blur, the base of the Superwhisper look.
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

struct PageSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            SectionTitle(title)
            content
        }
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
            Spacer()
            trailing
        }
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
                Text(title).font(.system(size: 14, weight: .semibold))
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
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
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

/// Coloured rounded square with a white symbol, as in the sidebar.
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
        VStack(spacing: 8) {
            preview
                .frame(width: 96, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                )
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .foregroundStyle(.primary)
    }
}

/// Page skeleton without a separate title row.
struct PageScaffold<Content: View, Accessory: View>: View {
    @Environment(AppContainer.self) private var container
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory
    var scrollsContent: Bool
    private let hasAccessory: Bool

    init(scrollsContent: Bool = true, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.content = content()
        self.accessory = accessory()
        self.scrollsContent = scrollsContent
        self.hasAccessory = true
    }

    init(scrollsContent: Bool = true, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.content = content()
        self.accessory = EmptyView()
        self.scrollsContent = scrollsContent
        self.hasAccessory = false
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
            if hasAccessory {
                HStack(spacing: 12) {
                    accessory
                    Spacer()
                }
            }
            content
        }
        .padding(Theme.pagePadding)
        .padding(.top, container.navigation.sidebarCollapsed ? 44 : 0)
        .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Five-segment meter used in the model table.
struct SegmentMeter: View {
    let value: Int   // 0...5
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < value ? Color.primary.opacity(0.7) : Color.primary.opacity(0.14))
                    .frame(width: 9, height: 3)
            }
        }
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
