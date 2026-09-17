import AirdraftCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home, profiles, vocabulary, configuration, models, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .profiles: return "Profiles"
        case .vocabulary: return "Vocabulary"
        case .configuration: return "Configuration"
        case .models: return "Models"
        case .history: return "History"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .profiles: return "sparkles"
        case .vocabulary: return "book.closed.fill"
        case .configuration: return "gearshape.fill"
        case .models: return "books.vertical.fill"
        case .history: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .home: return .orange
        case .profiles, .vocabulary: return .blue
        case .configuration, .models: return .gray
        case .history: return .purple
        }
    }

    /// Sidebar groups get extra spacing between them, like Superwhisper.
    var group: Int {
        switch self {
        case .home, .profiles, .vocabulary: return 0
        case .configuration, .models: return 1
        case .history: return 2
        }
    }
}

@MainActor
@Observable
final class Navigation {
    var page: Page = .home
    var sidebarCollapsed = false
}

struct MainWindowView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        HStack(spacing: 0) {
            if !container.navigation.sidebarCollapsed {
                SidebarView()
                    .frame(width: Theme.sidebarWidth)
                    .background(VisualEffectView(material: .sidebar))
                    .transition(.move(edge: .leading))
                Divider().opacity(0.4)
            }
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                page
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var page: some View {
        switch container.navigation.page {
        case .home: HomePage()
        case .profiles: ProfilesPage()
        case .vocabulary: VocabularyPage()
        case .configuration: ConfigurationPage()
        case .models: ModelsPage()
        case .history: HistoryPage()
        }
    }
}

struct SidebarView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 44) // traffic lights
            ForEach(Array(Page.allCases.enumerated()), id: \.element.id) { index, page in
                if index > 0, page.group != Page.allCases[index - 1].group {
                    Spacer().frame(height: 16)
                }
                SidebarItem(page: page, selected: container.navigation.page == page) {
                    container.navigation.page = page
                }
            }
            Spacer()
            footer
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(footerLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            HStack(spacing: 8) {
                Text("Airdraft").font(.system(size: 14, weight: .semibold))
                PillTag(text: "LOCAL")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }

    private var footerLine: String {
        let stats = (try? container.history?.stats()) ?? nil
        guard let stats, stats.words > 0 else { return "No dictations yet" }
        return "\(stats.words.formatted()) words dictated"
    }
}

struct SidebarItem: View {
    let page: Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: page.symbol, color: page.color)
            Text(page.title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.11) : (hovering ? Color.primary.opacity(0.05) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}
