import AirdraftCore
import SwiftUI

struct ModelsPage: View {
    @Environment(AppContainer.self) private var container
    @State private var query = ""
    @State private var filter: Filter = .all
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
            case .all: return "All models"
            case .local: return "On this Mac"
            case .cloud: return "Cloud"
            }
        }
    }

    private var localModels: [ModelEntry] {
        ModelCatalogue.entries.filter { matches([$0.title, $0.vendor, $0.note]) }
    }

    private var cloudPreset: EndpointPreset.Speech {
        container.settings.asr.kind.preset ?? EndpointPreset.asr[0]
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
            if filter != .cloud {
                PageSection("Speech on this Mac") {
                    Card(padding: 0) {
                        ModelTableHeader(cost: "Storage")
                        RowDivider()
                        if localModels.isEmpty {
                            EmptyNote("No local models match your search.")
                                .padding(Theme.cardPadding)
                        }
                        ForEach(Array(localModels.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { RowDivider() }
                            ModelRow(entry: entry)
                        }
                    }
                    EmptyNote("Relative ratings for local models. Speed varies with your Mac; accuracy varies with language and audio.")
                }
            }

            if filter != .local {
                cloudModels
                customSpeechSettings
            }

            PageSection("Speech options") {
                SettingsCard {
                    SettingRow(title: "Language") {
                        Picker("Language", selection: $settings.asr.language) {
                            ForEach(SpeechLanguage.choices(including: settings.asr.language), id: \.code) { Text($0.name).tag($0.code) }
                        }
                        .settingsPicker(width: 200)
                    }
                    RowDivider()
                    SettingRow(title: "Chinese script") {
                        Picker("Chinese script", selection: $settings.asr.chineseScript) {
                            ForEach(ChineseScript.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).settingsPicker(width: 240)
                    }
                    if settings.asr.kind == .apple {
                        RowDivider()
                        SettingRow(title: "Apple Speech locale", subtitle: "No auto language detection with this engine") {
                            Picker("Apple Speech locale", selection: $settings.asr.appleLocale) {
                                ForEach(SpeechLanguage.appleLocales(including: settings.asr.appleLocale), id: \.code) { Text($0.name).tag($0.code) }
                            }
                            .settingsPicker(width: 200)
                        }
                    }
                }
            }

            PageSection("Refinement", trailing: {
                Picker("Refinement provider", selection: Binding(
                    get: { settings.llm.kind },
                    set: { settings.llm.select($0) }
                )) {
                    ForEach(LLMProviderKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .settingsPicker(width: 200)
            }) {
                RefinementSettings()
            }

            PageSection("Memory") {
                SettingsCard {
                    SettingRow(title: "Unload idle speech model", subtitle: "Frees RAM when you have not dictated for a while") {
                        Picker("Unload idle speech model", selection: $settings.idleUnloadMinutes) {
                            Text("After 5 min").tag(5)
                            Text("After 10 min").tag(10)
                            Text("After 30 min").tag(30)
                            Text("Never").tag(0)
                        }
                        .settingsPicker(width: 140)
                    }
                    if settings.llm.kind == .openAICompatible {
                        RowDivider()
                        SettingRow(title: "Unload LM Studio model when quitting", subtitle: "LM Studio keeps models in memory until they are unloaded") {
                            Toggle("Unload LM Studio model when quitting", isOn: $settings.unloadLLMOnQuit).labelsHidden().toggleStyle(.switch)
                        }
                    }
                }
            }

        } accessory: {
            SearchField(text: $query, placeholder: "Search models")
            PageFilter(title: "Show models", selection: $filter,
                       options: Filter.allCases.map { ($0, $0.title) })
        }
        .onAppear {
            if !initialized {
                filter = settings.asr.kind.preset == nil ? .all : .cloud
                if RenderMode.isActive,
                   let value = RenderMode.value("FILTER").flatMap(Filter.init(rawValue:)) {
                    filter = value
                }
                initialized = true
            }
            Task { await container.models.refreshLLMStatus() }
        }
    }

    private var cloudModels: some View {
        let preset = cloudPreset
        let models = speechModels(for: preset)
        let visible = models.filter { matches([preset.name, $0.id, $0.title, $0.quality, $0.qualityDetail]) }
        var config = container.settings.asr
        config.select(preset.kind)
        let selected = models.first(where: { $0.id == config.model }) ?? config.selectedSpeechModel ?? models[0]
        return PageSection("Cloud speech", trailing: {
            HStack(spacing: Theme.sectionTitleSpacing) {
                Picker("Transcription provider", selection: Binding(
                    get: { cloudPreset.kind },
                    set: { container.settings.asr.select($0) }
                )) {
                    ForEach(EndpointPreset.asr) { Text($0.name).tag($0.kind) }
                }
                .settingsPicker(width: 200)
                if preset.kind == .openRouter {
                    RefreshButton(loading: openRouterLoading, help: "Refresh OpenRouter speech models") {
                        openRouterRefreshID = UUID()
                    }
                }
            }
        }) {
            VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                if preset.kind == .openRouter,
                   openRouterCatalogError != nil || openRouterLoading || selectedOpenRouterModelMissing {
                    VStack(alignment: .leading, spacing: 4) {
                        if let openRouterCatalogError {
                            Text(openRouterCatalogError)
                        } else if openRouterLoading {
                            Text("Loading OpenRouter's speech model catalog…")
                        }
                        if selectedOpenRouterModelMissing {
                            Label("Your saved speech model is not in the current catalog. Choose another model before dictating.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Card(padding: 0) {
                    ModelTableHeader(cost: preset.kind == .openRouter ? "Pricing" : "Price / hour")
                    RowDivider()
                    if visible.isEmpty {
                        EmptyNote("No \(preset.name) models match your search.")
                            .padding(Theme.cardPadding)
                    }
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, model in
                        if index > 0 { RowDivider() }
                        CloudModelRow(preset: preset, model: model)
                    }
                }
                CloudModelDetails(preset: preset, model: selected)
                SettingsCard {
                    SpeechKeyRows(preset: preset, config: config)
                }
                .id(preset.id)
            }
        }
        .task(id: "\(preset.kind.rawValue)|\(openRouterRefreshID)") {
            if preset.kind == .openRouter { await refreshOpenRouterModels() }
        }
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
                openRouterCatalogError = "OpenRouter returned no speech models. Showing curated choices."
            } else {
                openRouterModels = fetched
            }
        } catch {
            guard !Task.isCancelled else { return }
            openRouterCatalogError = openRouterModels.isEmpty
                ? "Could not load OpenRouter's speech models. Showing curated choices. Refresh to try again."
                : "Could not refresh OpenRouter's speech models. Showing the last loaded list."
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
                        TextField("Endpoint", text: $settings.asr.baseURL).textFieldStyle(.roundedBorder)
                            .labelsHidden().frame(width: Theme.fieldWidth)
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
            if preset.kind != .openRouter {
                Text(model.qualityDetail)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Pricing and performance details", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.billing)
                    Text(model.speedDetail)
                    if model.realtimeSpeedFactor != nil {
                        Text("Speed bars compare this provider's models; × is audio duration divided by processing time. Accuracy bars show 1 − word error rate (WER); lower WER is better. These are provider benchmarks, not measurements on your recordings.")
                    }
                    Text(preset.kind == .openRouter
                         ? "OpenRouter model availability and pricing can change. Check the linked model and pricing pages before use; displayed costs are not a bill for your recordings."
                         : "Provider-reported information · checked Sep 18, 2026. Prices exclude optional add-ons and account discounts.")
                    HStack(spacing: 16) {
                        Link(preset.kind == .openRouter ? "OpenRouter model page" : "Official model documentation", destination: model.documentationURL)
                        Link(preset.kind == .openRouter ? "Speech model catalog" : "Official pricing", destination: preset.pricingURL)
                    }.foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
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
private struct SpeechKeyRows: View {
    let preset: EndpointPreset.Speech
    let config: ASRConfig
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()

    private var keySubtitle: String {
        switch preset.kind {
        case .elevenLabs: return "Needs User Read permission"
        case .openRouter: return "Shared with OpenRouter refinement"
        default: return "Stored in your Keychain"
        }
    }

    var body: some View {
        SettingRow(title: "\(preset.name) API key", subtitle: keySubtitle) {
            APIKeyField(account: preset.keyRef, console: preset.consoleURL)
        }
        RowDivider()
        SettingRow(title: "Connection", subtitle: message) {
            if task != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { cancel(); message = "Connection test cancelled." }
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
                    message = "Save an API key first."
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
        var list = [Choice(code: "", name: "Detect automatically")] + codes.map { Choice(code: $0, name: name($0)) }
        if !current.isEmpty, !codes.contains(current) { list.append(Choice(code: current, name: "\(name(current)) (custom)")) }
        return list
    }

    static func appleLocales(including current: String) -> [Choice] {
        let codes = ["zh-TW", "zh-CN", "zh-HK", "en-US", "en-GB", "ja-JP", "ko-KR"]
        var list = codes.map { Choice(code: $0, name: name($0)) }
        if !codes.contains(current) { list.append(Choice(code: current, name: "\(name(current)) (custom)")) }
        return list
    }

    private static func name(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
