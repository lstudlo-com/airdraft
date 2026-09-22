import AirdraftCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home, profiles, vocabulary, history, configuration, models
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
        case .home: return "house"
        case .profiles: return "sparkles"
        case .vocabulary: return "book.closed"
        case .configuration: return "gearshape"
        case .models: return "square.stack.3d.up"
        case .history: return "clock"
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
        VStack(alignment: .leading, spacing: 0) {
            Text("Airdraft")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.top, 54)
                .padding(.bottom, 20)

            navigationGroup([.home, .profiles, .vocabulary, .history])
            navigationGroup([.configuration, .models])
                .padding(.top, 16)

            Spacer(minLength: 20)
            Text(footerLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 10)
    }

    private func navigationGroup(_ pages: [Page]) -> some View {
        VStack(spacing: 2) {
            ForEach(pages) { page in
                Button { container.navigation.page = page } label: {
                    HStack(spacing: 10) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 15, weight: .regular))
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(page.title)
                            .font(.system(size: 13, weight: .regular))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: NavigationStyle.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NavigationRowStyle(selected: container.navigation.page == page))
                .accessibilityAddTraits(container.navigation.page == page ? .isSelected : [])
                .accessibilityIdentifier("sidebar.\(page.rawValue)")
            }
        }
    }

    private var footerLine: String {
        let stats = (try? container.history?.stats()) ?? nil
        guard let stats, stats.words > 0 else { return "Ready to dictate" }
        return "\(stats.words.formatted()) words dictated"
    }
}
