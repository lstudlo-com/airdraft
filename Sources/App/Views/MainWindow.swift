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
    @FocusState private var overlayFocus: WindowOverlay?
    @State private var focusRestoreTask: Task<Void, Never>?

    init(profileSelection: UUID? = nil, previewOverlay: WindowOverlay? = nil, microphoneRenderLevel: Float? = nil) {
        self.profileSelection = profileSelection
        self.microphoneRenderLevel = microphoneRenderLevel
        self._activeOverlay = State(initialValue: previewOverlay)
    }

    var body: some View {
        @Bindable var license = container.license
        Group {
            if container.settings.onboarding.isPresented {
                OnboardingView()
                    .background(WindowChromeView(onPointerDown: {}))
            } else {
                mainContent
            }
        }
        .sheet(isPresented: Binding(get: { container.meeting?.isPresented == true }, set: { container.meeting?.isPresented = $0 })) {
            MeetingSheet().environment(container)
        }
        .sheet(isPresented: $license.isPresented) { LicenseView().environment(container) }
        .sheet(isPresented: Binding(get: { container.dataAccessIssue != nil || container.cleanup.blocksWork || container.cleanup.finishedScope == .reset }, set: { _ in })) {
            DataCleanupProgress().environment(container).interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !container.pipeline.isBusy, let verified = license.record?.grant?.verifiedAt,
                  Date().timeIntervalSince(verified) >= 86_400 else { return }
            Task { await license.refresh() }
        }
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            SidebarView(
                openMicrophone: { activeOverlay = activeOverlay == .microphone ? nil : .microphone },
                openAccount: { container.showLicense() },
                overlayFocus: $overlayFocus
            )
            .frame(width: container.navigation.sidebarCollapsed ? Theme.sidebarCollapsedWidth : Theme.sidebarWidth)
            page.contentIsland()
        }
        .disabled(activeOverlay != nil)
        .accessibilityHidden(activeOverlay != nil)
        .overlay(alignment: .topLeading) {
            let collapsed = container.navigation.sidebarCollapsed
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    container.navigation.sidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: Theme.sidebarToggleSymbolSize))
                    // Always in the island's heading row, beside the page title; it follows
                    // the island's leading edge as the sidebar expands or collapses.
                    .frame(width: Theme.sidebarToggleWidth, height: Theme.pageHeaderRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, Theme.sidebarToggleLeading(
                sidebarWidth: collapsed ? Theme.sidebarCollapsedWidth : Theme.sidebarWidth))
            .padding(.top, Theme.sidebarToggleTop)
            .help(collapsed ? "Expand Sidebar" : "Collapse Sidebar")
            .accessibilityLabel(collapsed ? "Expand Sidebar" : "Collapse Sidebar")
            .accessibilityIdentifier("sidebar.toggle")
            .disabled(activeOverlay != nil)
            .accessibilityHidden(activeOverlay != nil)
        }
        .background(SidebarBackground())
        .background(WindowChromeView(onPointerDown: clearOverlayFocus))
        .ignoresSafeArea()
        .frame(width: Theme.windowWidth)
        .frame(minHeight: Theme.windowMinHeight, maxHeight: .infinity)
        .overlay {
            if let activeOverlay {
                Group {
                    if activeOverlay == .account {
                        Color.black.opacity(0.38)
                            .ignoresSafeArea()
                            .onTapGesture { self.activeOverlay = nil }
                            .accessibilityHidden(true)
                        AccountOverlay { self.activeOverlay = nil }
                    } else {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture { self.activeOverlay = nil }
                            .accessibilityHidden(true)
                        MicrophoneSelectionOverlay(onClose: { self.activeOverlay = nil },
                                                   renderLevel: microphoneRenderLevel)
                            // Left edge with the capsule it belongs to; 8 pt above it (52 pt footer + 38 pt capsule).
                            .padding(.leading, Theme.sidebarContentInset + 4)
                            .padding(.bottom, 98)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .transition(.opacity)
            }
        }
        .onExitCommand { activeOverlay = nil }
        .onChange(of: activeOverlay) { previous, next in
            clearOverlayFocus()
            guard next == nil else { return }
            guard let previous else { return }
            // Pointer dismissal should not leave the trigger outlined. Keyboard and
            // VoiceOver dismissal return focus after the background becomes enabled.
            let eventType = NSApp.currentEvent?.type
            guard eventType == .keyDown || eventType == .keyUp || NSWorkspace.shared.isVoiceOverEnabled else { return }
            focusRestoreTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled, activeOverlay == nil else { return }
                overlayFocus = previous
            }
        }
        .onDisappear { clearOverlayFocus() }

    }

    private func clearOverlayFocus() {
        focusRestoreTask?.cancel()
        focusRestoreTask = nil
        overlayFocus = nil
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

/// A raised capsule, drawn by light and shade alone, with the icon's waveform and caret
/// carved into it.
struct SidebarBrandMark: View {
    /// The sidebar size unless another surface (the License sheet) scales the same mark up.
    var height: CGFloat = Theme.sidebarBrandHeight
    var identifier = "sidebar.wordmark"
    private var scale: CGFloat { height / 364 }
    /// Shadow depth follows size, so a larger mark keeps the sidebar's proportions.
    private var depth: CGFloat { height / Theme.sidebarBrandHeight }
    private let levels: [CGFloat] = [0.36, 0.66, 1, 0.72, 0.48]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            raisedBody

            HStack(spacing: 30 * scale) {
                ForEach(levels.indices, id: \.self) { index in
                    groove.frame(width: 38 * scale, height: 190 * levels[index] * scale)
                }
                groove
                    .frame(width: 38 * scale, height: 208 * scale)
                    .padding(.leading, 20 * scale)
            }
        }
        .frame(width: 744 * scale, height: height)
        .frame(height: max(30, height))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Airdraft")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(identifier)
        .allowsHitTesting(false)
    }

    /// The face is the sidebar itself, lifted by soft, wide shadows only: an edge stroke or a
    /// tight highlight reads as an outline. Shadows stay outside the face.
    private var raisedBody: some View {
        let dark = scheme == .dark
        return SurfaceShadows(shape: Capsule(), shadows: [
            .init(color: .black.opacity(dark ? 0.55 : 0.2), radius: 2.6 * depth, x: 1.4 * depth, y: 2.2 * depth),
            .init(color: .white.opacity(dark ? 0.09 : 0.95), radius: 2.6 * depth, x: -1.2 * depth, y: -1.6 * depth),
        ], excludesInterior: true)
        .overlay {
            if contrast == .increased { Capsule().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1) }
        }
    }

    /// A stroke pressed into the capsule: a darker floor, shaded inside its top-left edge
    /// and lit at the bottom right. Opaque, so SwiftUI's inner shadows keep full strength.
    private var groove: some View {
        let dark = scheme == .dark
        return Capsule()
            .fill(Color(white: dark ? 0.12 : 0.80)
                .shadow(.inner(color: .black.opacity(dark ? 0.7 : 0.35), radius: 0.8 * depth, x: 0.6 * depth, y: 0.8 * depth))
                .shadow(.inner(color: .white.opacity(dark ? 0.14 : 0.9), radius: 0.6 * depth, x: -0.5 * depth, y: -0.6 * depth)))
            .overlay {
                if contrast == .increased { Capsule().strokeBorder(Color.primary.opacity(0.5), lineWidth: 0.5) }
            }
    }
}

/// A sidebar symbol. Selected, it is carved into its raised island: a darker floor with a
/// highlight along its lower-right edge from the top-left light.
struct SidebarIcon: View {
    let symbol: String
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        let glyph = Image(systemName: symbol).font(.system(size: Theme.sidebarIconSize, weight: .regular))
        ZStack {
            glyph.foregroundStyle(.primary)
                .opacity(selected ? 0 : 1)
            // Engraved: the lower-right rim catches the light, the upper-left rim falls in shade.
            ZStack {
                glyph.foregroundStyle(Color.white.opacity(dark ? 0.24 : 1))
                    .offset(x: 0.8, y: 1)
                glyph.foregroundStyle(Color.black.opacity(dark ? 0.6 : 0.35))
                    .offset(x: -0.5, y: -0.6)
                glyph.foregroundStyle(Color(white: dark ? 0.05 : 0.24))
            }
            .opacity(selected ? 1 : 0)
        }
        // The carving appears as the island arrives; leaving, it returns to plain at once.
        .animation(reduceMotion ? nil : selected ? SelectionMotion.islandCurve : SelectionMotion.curve, value: selected)
        .accessibilityHidden(true)
    }
}

struct SidebarView: View {
    @Environment(AppContainer.self) private var container
    let openMicrophone: () -> Void
    let openAccount: () -> Void
    var overlayFocus: FocusState<WindowOverlay?>.Binding
    @State private var wordsDictated = 0
    @State private var wordCountRefresh = UUID()

    private var isCollapsed: Bool { container.navigation.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrandMark()
                .padding(.horizontal, Theme.sidebarBrandInset)
                .padding(.top, 54)
                .padding(.bottom, 20)

            // One selection well spans both groups so it can slide between them.
            VStack(alignment: .leading, spacing: 0) {
                navigationGroup([.home, .profiles, .vocabulary, .history])
                navigationGroup([.configuration, .models])
                    .padding(.top, 16)
            }
            .sidebarSelectionWell(selection: container.navigation.page)

            Spacer(minLength: 20)
            Button(action: openMicrophone) {
                // A raised control with its symbol in a recessed socket: the inverse of a selected
                // destination, so it never reads as a page. Labels share the destinations' start.
                HStack(spacing: NavigationStyle.labelStart - NavigationStyle.iconIslandInset - NavigationStyle.microphoneSocketSize) {
                    Image(systemName: "mic")
                        .font(.system(size: Theme.sidebarIconSize))
                        .frame(width: NavigationStyle.microphoneSocketSize, height: NavigationStyle.microphoneSocketSize)
                        .background { MicrophoneIconSocket() }
                        .accessibilityHidden(true)
                    if !isCollapsed {
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
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, isCollapsed ? 0 : NavigationStyle.iconIslandInset)
                .padding(.trailing, isCollapsed ? 0 : 14)
                .frame(height: NavigationStyle.microphoneHeight)
            }
            .buttonStyle(MicrophoneButtonStyle())
            .frame(maxWidth: .infinity)
            .frame(height: NavigationStyle.microphoneHeight)
            .contentShape(NavigationStyle.wellShape)
            .padding(.horizontal, NavigationStyle.destinationInset)
            .padding(.top, 8)
            .disabled(container.pipeline.state.isBusy)
            .help("Change microphone. Your choice is saved as the default.")
            .accessibilityLabel("Microphone: \(container.microphones.label(container.settings.microphone))")
            .accessibilityIdentifier("sidebar.microphone")
            .focusable()
            .focused(overlayFocus, equals: .microphone)
            HStack(alignment: .center) {
                if isCollapsed { Spacer(minLength: 0) }
                Button(action: openAccount) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: Theme.sidebarIconSize))
                        .frame(width: 30, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("License")
                .accessibilityLabel("License")
                .accessibilityIdentifier("sidebar.account")
                .focusable()
                .focused(overlayFocus, equals: .account)
                if isCollapsed {
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 2)
                    footerLabel
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, Theme.sidebarContentInset)
        .task(id: container.pipeline.lastOutcome) { await refreshWordCount() }
        .onReceive(NotificationCenter.default.publisher(for: .historyEntriesChanged)) { _ in
            Task { await refreshWordCount() }
        }
        .onChange(of: container.pipeline.isSavingHistory) { _, saving in
            if !saving { Task { await refreshWordCount() } }
        }
    }

    /// Counted off the main actor after a save or deletion, never on redraw.
    private func refreshWordCount() async {
        guard let history = container.history else { return }
        let token = UUID()
        wordCountRefresh = token
        let count = await Task.detached { (try? history.stats().words) ?? 0 }.value
        guard !Task.isCancelled, wordCountRefresh == token else { return }
        wordsDictated = count
    }

    private func navigationGroup(_ pages: [Page]) -> some View {
        VStack(spacing: 2) {
            ForEach(pages) { page in
                Button { container.navigation.page = page } label: {
                    // Same width and label start as the microphone button below.
                    HStack(spacing: NavigationStyle.labelStart - NavigationStyle.iconIslandInset - NavigationStyle.iconIslandSize) {
                        SidebarIcon(symbol: page.symbol, selected: container.navigation.page == page)
                            .frame(width: NavigationStyle.iconIslandSize)
                            .sidebarSelectionIconAnchor(page)
                        if !isCollapsed {
                            Text(page.title)
                                .font(.system(size: 13, weight: .regular))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
                    .padding(.leading, isCollapsed ? 0 : NavigationStyle.iconIslandInset)
                    // Destinations have no trailing chevron, so their titles keep that space.
                    .padding(.trailing, isCollapsed ? 0 : 6)
                    .frame(height: NavigationStyle.destinationHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NavigationRowStyle(selected: container.navigation.page == page, slidingSelection: true))
                .sidebarSelectionAnchor(page)
                .padding(.horizontal, NavigationStyle.destinationInset)
                .help(page.title)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(container.navigation.page == page ? .isSelected : [])
                .accessibilityIdentifier("sidebar.\(page.rawValue)")
            }
        }
    }

    private var footerLabel: some View {
        Text(footerLine)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var footerLine: String {
        guard wordsDictated > 0 else { return "Ready to dictate" }
        return "\(wordsDictated.formatted()) words dictated"
    }
}
