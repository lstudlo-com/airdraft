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
        case .profiles: return "square.and.pencil"
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
    var profileSelection: UUID?
    var microphoneRenderLevel: Float?
    @State private var activeOverlay: WindowOverlay?

    init(profileSelection: UUID? = nil, previewOverlay: WindowOverlay? = nil, microphoneRenderLevel: Float? = nil) {
        self.profileSelection = profileSelection
        self.microphoneRenderLevel = microphoneRenderLevel
        self._activeOverlay = State(initialValue: previewOverlay)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !container.navigation.sidebarCollapsed {
                SidebarView(
                    openMicrophone: { activeOverlay = activeOverlay == .microphone ? nil : .microphone },
                    openSettings: { activeOverlay = .settings }
                )
                    .frame(width: Theme.sidebarWidth)
                    .background(SidebarBackground())
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 0.5)
                            .allowsHitTesting(false)
                    }
                    .transition(.move(edge: .leading))
            }
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                page
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    container.navigation.sidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
                    .frame(width: 28, height: Theme.titlebarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .padding(.leading, Theme.sidebarToggleLeading)
            .help(container.navigation.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
            .accessibilityLabel(container.navigation.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
            .accessibilityIdentifier("sidebar.toggle")
            .disabled(activeOverlay != nil)
            .accessibilityHidden(activeOverlay != nil)
        }
        .background(TranslucentWindowView())
        .ignoresSafeArea()
        .frame(minWidth: 900, minHeight: 600)
        .overlay {
            if let activeOverlay {
                Group {
                    if activeOverlay == .settings {
                        Color.black.opacity(0.38)
                            .onTapGesture { self.activeOverlay = nil }
                        AccountSettingsOverlay { self.activeOverlay = nil }
                    } else {
                        Color.black.opacity(0.001)
                            .onTapGesture { self.activeOverlay = nil }
                        MicrophoneSelectionOverlay(onClose: { self.activeOverlay = nil },
                                                   renderLevel: microphoneRenderLevel)
                            .padding(.leading, 16)
                            .padding(.bottom, 99)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .transition(.opacity)
            }
        }
        .onExitCommand { activeOverlay = nil }

    }

    @ViewBuilder
    private var page: some View {
        switch container.navigation.page {
        case .home: HomePage()
        case .profiles: ProfilesPage(selection: profileSelection)
        case .vocabulary: VocabularyPage()
        case .configuration: ConfigurationPage()
        case .models: ModelsPage()
        case .history: HistoryPage()
        }
    }
}

/// An open capsule rim around the icon's raised waveform and caret.
private struct SidebarBrandMark: View {
    // Scale the original compact mark uniformly to 1.25×.
    private let scale: CGFloat = 25 / 364
    private let levels: [CGFloat] = [0.36, 0.66, 1, 0.72, 0.48]

    var body: some View {
        ZStack {
            NeumorphicSurface(shape: Capsule(), depth: 1, translucent: true, outlineOnly: true)

            HStack(spacing: 30 * scale) {
                ForEach(levels.indices, id: \.self) { index in
                    NeumorphicSurface(shape: Capsule(), depth: 0.375)
                        .frame(width: 38 * scale, height: 190 * levels[index] * scale)
                }
                NeumorphicSurface(shape: Capsule(), depth: 0.375)
                    .frame(width: 38 * scale, height: 208 * scale)
                    .padding(.leading, 20 * scale)
            }
        }
        .frame(width: 744 * scale, height: 364 * scale)
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Airdraft")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("sidebar.wordmark")
        .allowsHitTesting(false)
    }
}

struct SidebarView: View {
    @Environment(AppContainer.self) private var container
    let openMicrophone: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrandMark()
                .padding(.horizontal, 10)
                .padding(.top, 54)
                .padding(.bottom, 20)

            navigationGroup([.home, .profiles, .vocabulary, .history])
            navigationGroup([.configuration, .models])
                .padding(.top, 16)

            Spacer(minLength: 20)
            Button(action: openMicrophone) {
                HStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 15))
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(container.microphones.label(container.settings.microphone))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .frame(width: 12)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule())
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .disabled(container.pipeline.state.isBusy)
            .help("Change microphone. Your choice is saved as the default.")
            .accessibilityLabel("Microphone: \(container.microphones.label(container.settings.microphone))")
            HStack(alignment: .center) {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("sidebar.settings")
                Spacer(minLength: 2)
                Text(footerLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 14)
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
