import AirdraftCore
import SwiftUI

struct ModelsPage: View {
    @Environment(AppContainer.self) private var container
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var localProvider: String?
    @State private var cloudProvider: ASRProviderKind?
    /// Experimental models stay one click away; searching always includes them.
    @State private var showsExperimental = false
    @State private var installedIDs: Set<String> = []
    @State private var initialized = false
    @State private var openRouterModels: [SpeechModelInfo] = []
    @State private var openRouterLoading = false
    @State private var openRouterCatalogError: String?
    @State private var openRouterRefreshID = UUID()

    enum Filter: String, CaseIterable, Identifiable {
        case all, local, cloud
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All models")
            case .local: return String(localized: "On this Mac")
            case .cloud: return String(localized: "Cloud")
            }
        }
    }

    /// The provider filter belongs to the full list; the compact set ignores it.
    private var localModels: [ModelEntry] {
        let provider = container.settings.showsAllLocalModels ? localProvider : nil
        return ModelCatalogue.entries.filter {
            (provider == nil || $0.provider == provider) &&
                matches([$0.title, $0.provider, $0.vendor, $0.note] + $0.tags + ($0.languages?.names ?? []))
        }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// AD-071: the compact recommended set plus the user's models, or, when
    /// showing all models or searching, Recommended, then Verified (with
    /// built-in) rows, then the Experimental disclosure and, when open or
    /// searching, its rows. Each item is one list cell.
    private var localItems: [LocalModelItem] {
        ModelCatalogue.localItems(localModels, shortlist: ModelCatalogue.shortlist, inUse: inUseIDs,
                                  showsAll: container.settings.showsAllLocalModels,
                                  expanded: showsExperimental, searching: isSearching)
    }

    /// Entries the user relies on stay listed in the compact set and in a
    /// collapsed Experimental group: the app default, the active profile's
    /// model, running downloads and installed files (checked on a worker).
    private var inUseIDs: Set<String> {
        let asr = container.settings.asr
        let speech = container.speechConfig
        var ids = installedIDs
        for entry in ModelCatalogue.entries {
            if entry.isSelected(asr) || entry.isSelected(speech)
                || container.downloads.jobs[entry.config(from: asr).engineID] != nil {
                ids.insert(entry.id)
            }
        }
        return ids
    }

    /// Built-in Apple Speech is always available, so it only counts when in use.
    private func refreshInstalled() async {
        let asr = container.settings.asr
        let candidates = ModelCatalogue.entries.filter(\.isDownloadable).map { ($0.id, $0.config(from: asr)) }
        let installed = await Task.detached(priority: .utility) {
            Set(candidates.filter { LocalModels.isInstalled($0.1) }.map(\.0))
        }.value
        guard !Task.isCancelled else { return }
        installedIDs = installed
    }

    /// Shows or hides the full local catalogue; the choice is remembered.
    private var showAllModelsButton: some View {
        let showsAll = container.settings.showsAllLocalModels
        return Button {
            container.settings.showsAllLocalModels.toggle()
        } label: {
            if showsAll {
                Text("Show Recommended Only")
            } else {
                Text("Show All Models (\(ModelCatalogue.entries.count))")
            }
        }
        .buttonStyle(SoftButtonStyle())
        .help(showsAll ? String(localized: "List only the recommended models and the models you use.")
              : String(localized: "List every local model, with provider filters and experimental models."))
        .accessibilityIdentifier("models.show-all")
    }

    private var localProviders: [String] {
        Array(Set(ModelCatalogue.entries.map(\.provider))).sorted()
    }

    private struct CloudEntry: Identifiable {
        let preset: EndpointPreset.Speech
        let model: SpeechModelInfo
        var id: String { "\(preset.id)/\(model.id)" }
    }

    private var visibleCloudModels: [CloudEntry] {
        EndpointPreset.asr.filter { cloudProvider == nil || $0.kind == cloudProvider }.flatMap { preset in
            speechModels(for: preset).filter {
                matches([preset.name, $0.id, $0.title, $0.quality, $0.qualityDetail])
            }.map { CloudEntry(preset: preset, model: $0) }
        }
    }

    private var showsOpenRouter: Bool {
        cloudProvider == nil || cloudProvider == .openRouter
    }

    private var selectedOpenRouterModelMissing: Bool {
        container.settings.asr.kind == .openRouter && openRouterCatalogError == nil && !openRouterModels.isEmpty &&
            !openRouterModels.contains(where: { $0.id == container.settings.asr.model })
    }

    private func speechModels(for preset: EndpointPreset.Speech) -> [SpeechModelInfo] {
        let curated = SpeechModelInfo.models(for: preset.kind)
        guard preset.kind == .openRouter else { return curated }
        var models = openRouterModels.isEmpty ? curated : openRouterModels
        let selectedID = container.settings.asr.kind == .openRouter ? container.settings.asr.model : ""
        if !selectedID.isEmpty, !models.contains(where: { $0.id == selectedID }),
           let saved = container.settings.asr.selectedSpeechModel {
            models.insert(saved, at: 0)
        }
        return models
    }

    private func matches(_ values: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        @Bindable var settings = container.settings
        PageScaffold(.models) {
            if container.profiles.activeProfile.speechModel != nil {
                SettingsCard {
                    SettingRow(title: "\(container.profiles.activeProfile.displayName) uses its own speech model",
                               subtitle: "Selections here change the app default.") {
                        Button("Profiles") { container.navigation.page = .profiles }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }
            if filter != .cloud {
                PageSection("Speech on this Mac", trailing: {
                    if settings.showsAllLocalModels {
                        SoftPicker("Local speech provider", selection: $localProvider, width: 160) {
                            Text("All").tag(String?.none)
                            ForEach(localProviders, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    }
                }) {
                    let items = localItems
                    ModelTable(cost: String(localized: "Storage"), rowCount: items.count,
                               capped: settings.showsAllLocalModels || isSearching) {
                        if items.isEmpty {
                            EmptyNote("No local models match your search.")
                                .padding(Theme.cardPadding)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 0) {
                                if index > 0 { RowDivider() }
                                switch item {
                                case let .model(entry, header, role):
                                    if let header { LocalModelGroupHeader(header: header) }
                                    ModelRow(entry: entry, role: role)
                                case let .experimental(count, kept, expanded, searching):
                                    ExperimentalModelsDisclosure(count: count, kept: kept, expanded: expanded, searching: searching) {
                                        showsExperimental.toggle()
                                    }
                                }
                            }
                            .accessibilityElement(children: .contain)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .id("\(settings.showsAllLocalModels)|\(localProvider ?? "all")|\(query)")
                    HStack(alignment: .center, spacing: Theme.controlSpacing) {
                        EmptyNote("Relative ratings; results vary by Mac, language and audio.")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if !isSearching { showAllModelsButton }
                    }
                }
                // Finished or cancelled downloads change which files are installed.
                .task(id: container.downloads.jobs.keys.sorted()) { await refreshInstalled() }
            }

            if filter != .local, !RenderMode.excludesCredentials {
                cloudModels
                customSpeechSettings
            }

            PageSection("Speech options") {
                SettingsCard {
                    SpeechLanguageSettings()
                }
            }

            PageSection("Refinement", trailing: {
                SoftPicker("Refinement provider", selection: Binding(
                    get: { settings.llm.kind },
                    set: { settings.llm.select($0) }
                ), width: 200) {
                    ForEach(LLMProviderKind.allCases.filter { !RenderMode.excludesCredentials || !$0.requiresKey }) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }) {
                RefinementSettings()
            }

            if settings.livePreviewEnabled { SpeechPreviewSettings() }

            PageSection("Memory") {
                SettingsCard {
                    SettingRow(title: "Unload idle speech model", subtitle: "Frees memory between dictations") {
                        SoftPicker("Unload idle speech model", selection: $settings.idleUnloadMinutes, width: 140) {
                            Text("After 5 min").tag(5)
                            Text("After 10 min").tag(10)
                            Text("After 30 min").tag(30)
                            Text("Never").tag(0)
                        }
                    }
                    if settings.llm.kind == .openAICompatible {
                        RowDivider()
                        SettingRow(title: "Unload LM Studio model on quit") {
                            Toggle("Unload LM Studio model when quitting", isOn: $settings.unloadLLMOnQuit).labelsHidden().toggleStyle(.softSwitch)
                        }
                    }
                }
            }

        } accessory: {
            SearchField(text: $query, placeholder: "Search models")
            PageFilter(title: "Show models", selection: $filter,
                       options: Filter.allCases.filter { !RenderMode.excludesCredentials || $0 != .cloud }.map { ($0, $0.title) })
        }
        .onAppear {
            if !initialized {
                filter = RenderMode.excludesCredentials ? .local : .all
                if RenderMode.isActive,
                   let value = RenderMode.value("FILTER").flatMap(Filter.init(rawValue:)) {
                    filter = value
                }
                localProvider = RenderMode.value("LOCAL_PROVIDER")
                showsExperimental = RenderMode.value("SHOW_EXPERIMENTAL") == "1"
                // Renders of the full table: SHOW_ALL_MODELS=1, or the Experimental group.
                if RenderMode.isActive, let value = RenderMode.value("SHOW_ALL_MODELS") ?? (showsExperimental ? "1" : nil) {
                    settings.showsAllLocalModels = value == "1"
                }
                cloudProvider = RenderMode.value("CLOUD_PROVIDER").flatMap(ASRProviderKind.init(rawValue:))
                query = RenderMode.value("MODEL_QUERY") ?? ""
                initialized = true
            }
            Task { await container.models.refreshLLMStatus() }
        }
    }

    private var cloudModels: some View {
        let visible = visibleCloudModels
        return PageSection("Cloud speech", trailing: {
            HStack(spacing: Theme.sectionTitleSpacing) {
                if showsOpenRouter {
                    RefreshButton(loading: openRouterLoading, help: "Refresh OpenRouter speech models") {
                        openRouterRefreshID = UUID()
                    }
                }
                SoftPicker("Cloud speech provider", selection: $cloudProvider, width: 160) {
                    Text("All").tag(ASRProviderKind?.none)
                    ForEach(EndpointPreset.asr) { Text($0.name).tag(Optional($0.kind)) }
                }
            }
        }) {
            VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                if showsOpenRouter,
                   openRouterCatalogError != nil || openRouterLoading || selectedOpenRouterModelMissing {
                    VStack(alignment: .leading, spacing: 4) {
                        if let openRouterCatalogError {
                            Text(openRouterCatalogError)
                        } else if openRouterLoading {
                            Text("Loading speech models…")
                        }
                        if selectedOpenRouterModelMissing {
                            Label("Saved model unavailable. Choose another.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .appFont(.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                ModelTable(cost: String(localized: "Pricing"), rowCount: visible.count) {
                    if visible.isEmpty {
                        EmptyNote("No cloud models match your search.")
                            .padding(Theme.cardPadding)
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        VStack(spacing: 0) {
                            if index > 0 { RowDivider() }
                            CloudModelRow(preset: entry.preset, model: entry.model)
                        }
                        .accessibilityElement(children: .contain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .id("\(cloudProvider?.rawValue ?? "all")|\(query)")
                if let preset = cloudProvider?.preset ?? container.settings.asr.kind.preset {
                    cloudSettings(for: preset)
                }
            }
        }
        .task(id: "\(showsOpenRouter)|\(openRouterRefreshID)") {
            if showsOpenRouter { await refreshOpenRouterModels() }
        }
    }

    private func cloudSettings(for preset: EndpointPreset.Speech) -> some View {
        var config = container.settings.asr
        // Inspect the browsed provider's saved setup without selecting it.
        config.select(preset.kind)
        let selected = speechModels(for: preset).first { $0.id == config.model } ?? config.selectedSpeechModel
        return VStack(spacing: Theme.sectionTitleSpacing) {
            if let selected { CloudModelDetails(preset: preset, model: selected) }
            SettingsCard { SpeechKeyRows(preset: preset, config: config) }
        }
        .id(preset.id)
    }

    private func refreshOpenRouterModels() async {
        guard !RenderMode.isActive else { return }
        openRouterLoading = true
        openRouterCatalogError = nil
        defer { openRouterLoading = false }
        do {
            let fetched = try await OpenRouterSpeechCatalog.fetch()
            guard !Task.isCancelled else { return }
            if fetched.isEmpty {
                openRouterCatalogError = String(localized: "OpenRouter returned no speech models. Showing curated choices.")
            } else {
                openRouterModels = fetched
            }
        } catch {
            guard !Task.isCancelled else { return }
            openRouterCatalogError = openRouterModels.isEmpty
                ? String(localized: "Catalog unavailable; showing saved choices. Try Refresh.")
                : String(localized: "Refresh failed; showing the last list.")
        }
    }

    @ViewBuilder
    private var customSpeechSettings: some View {
        @Bindable var settings = container.settings
        if settings.asr.kind == .openAICompatible {
            PageSection("Custom speech endpoint") {
                SettingsCard {
                    SettingRow(title: "API key", subtitle: "Audio is sent to your configured endpoint") {
                        APIKeyField(account: settings.asr.apiKeyRef).id(settings.asr.apiKeyRef)
                    }
                    RowDivider()
                    SettingRow(title: "Endpoint") {
                        TextField("Endpoint", text: $settings.asr.baseURL).softField()
                            .labelsHidden().frame(width: Theme.fieldWidth)
                            .accessibilityLabel("Endpoint")
                    }
                    RowDivider()
                    ModelField(title: "Model", model: $settings.asr.model, baseURL: settings.asr.baseURL, apiKeyRef: settings.asr.apiKeyRef, speechOnly: true)
                }
            }
        }
    }
}

private struct CloudModelDetails: View {
    let preset: EndpointPreset.Speech
    let model: SpeechModelInfo
    @State private var expanded = false

    var body: some View {
        Card(spacing: Theme.controlSpacing) {
            DisclosureGroup("Pricing and performance", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if preset.kind != .openRouter { Text(model.qualityDetail) }
                    Text(model.billing)
                    Text(model.speedDetail)
                    if model.realtimeSpeedFactor != nil {
                        Text("Provider benchmarks: speed = audio ÷ processing time; accuracy = 1 − WER. Your results may vary.")
                    }
                    Text(preset.kind == .openRouter
                         ? "Availability and prices vary. See current provider pricing."
                         : "Provider data · Sep 18, 2026 · excludes add-ons and discounts")
                    HStack(spacing: 16) {
                        Link(preset.kind == .openRouter ? "OpenRouter model page" : "Official model documentation", destination: model.documentationURL)
                        Link(preset.kind == .openRouter ? "Speech model catalog" : "Official pricing", destination: preset.pricingURL)
                    }.foregroundStyle(Color.accentColor)
                }
                .supportingText()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.sectionTitleSpacing)
            }
            .settingsDisclosure()
        }
        .onAppear {
            if RenderMode.isActive,
               RenderMode.value("DETAILS") == "1" { expanded = true }
        }
    }
}

/// The same key row as refinement, plus a connection test of the saved key.
struct SpeechKeyRows: View {
    let preset: EndpointPreset.Speech
    let config: ASRConfig
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()

    private var keySubtitle: String {
        switch preset.kind {
        case .elevenLabs: return String(localized: "Needs User Read permission")
        case .openRouter: return String(localized: "Shared with OpenRouter refinement")
        default: return String(localized: "Stored in your Keychain")
        }
    }

    var body: some View {
        SettingRow(title: "\(preset.name) API key", detail: keySubtitle) {
            APIKeyField(account: preset.keyRef, console: preset.consoleURL)
        }
        RowDivider()
        SettingRow(title: "Connection", detail: message) {
            if task != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { cancel(); message = String(localized: "Connection test cancelled.") }
                        .buttonStyle(SoftButtonStyle())
                }
            } else {
                Button("Test") { test() }
                    .buttonStyle(SoftButtonStyle())
                    .help("Checks API access without sending audio. Transcription permissions and billing are not tested.")
            }
        }
        .task(id: preset.keyRef) {
            // Offscreen verification never reads the user's credentials.
            switch RenderMode.value("CONNECTION") {
            case "testing": task = Task { try? await Task.sleep(for: .seconds(60)) }
            case "success": message = "Connected. API key accepted."
            case "error": message = SpeechConnectionError.permissionDenied.localizedDescription
            default: break
            }
        }
        .onChange(of: config.engineID) { _, _ in cancel(); message = nil }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { note in
            guard note.object as? String == preset.keyRef else { return }
            cancel()
            message = nil
        }
        .onDisappear { cancel() }
    }

    private func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
    }

    private func test() {
        guard !RenderMode.excludesCredentials else { return }
        cancel()
        let token = generation
        let account = preset.keyRef
        let config = config
        message = nil
        task = Task { @MainActor in
            defer { if generation == token { task = nil } }
            do {
                let key = try await Task.detached { try Keychain.read(account) }.value ?? ""
                guard generation == token, !Task.isCancelled else { return }
                guard !key.isEmpty else {
                    message = String(localized: "Save an API key first.")
                    return
                }
                let result = try await SpeechConnectionChecker().check(config: config, apiKey: key)
                guard generation == token, !Task.isCancelled else { return }
                message = result.message
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = error.localizedDescription
            }
        }
    }
}

/// Language choices instead of typed codes. A saved custom value stays selectable.
enum SpeechLanguage {
    struct Choice { let code: String; let name: String }

    static func choices(including current: String) -> [Choice] {
        let codes = ["en", "zh", "ja", "ko", "es", "fr", "de", "it", "pt", "ru", "vi", "th", "id"]
        var list = [Choice(code: "", name: String(localized: "Detect Automatically"))] + codes.map { Choice(code: $0, name: name($0)) }
        if !current.isEmpty, !codes.contains(current) { list.append(Choice(code: current, name: String(localized: "\(name(current)) (custom)"))) }
        return list
    }

    static func appleLocales(including current: String) -> [Choice] {
        let codes = ["zh-TW", "zh-CN", "zh-HK", "en-US", "en-GB", "ja-JP", "ko-KR"]
        var list = codes.map { Choice(code: $0, name: name($0)) }
        if !codes.contains(current) { list.append(Choice(code: current, name: String(localized: "\(name(current)) (custom)"))) }
        return list
    }

    private static func name(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
