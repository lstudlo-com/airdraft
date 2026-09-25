import AppKit
import AirdraftCore
import SwiftUI

/// Provider selection lives in the Models section heading. Show only the
/// settings required by the selected provider here.
struct RefinementSettings: View {
    @Environment(AppContainer.self) private var container
    @State private var testResult = ""
    @State private var testTask: Task<Void, Never>?
    @State private var testID = UUID()
    private var llm: LLMConfig { container.settings.llm }

    var body: some View {
        @Bindable var settings = container.settings
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            SettingsCard {
                switch llm.kind {
                case .none:
                    SettingRow(title: "Refinement is off", subtitle: "Dictation inserts the raw transcript, with vocabulary and script conversion only") {
                        EmptyView()
                    }
                case .openAICompatible:
                    localServerRows
                case .claudeCode, .codex:
                    cliRows
                default:
                    cloudRows
                }
            }

            if llm.kind != .none {
            DisclosureGroup("Advanced") {
                SettingsCard {
                    if llm.kind != .anthropic && !llm.kind.isCLI {
                    SettingRow(title: "Temperature") {
                        HStack {
                            Slider(value: $settings.llm.temperature, in: 0...1, step: 0.1).frame(width: 160).accessibilityLabel("Temperature")
                            Text(String(format: "%.1f", settings.llm.temperature)).monospacedDigit().frame(width: 28)
                        }
                    }
                    RowDivider()
                    }
                    SettingRow(title: "Timeout", subtitle: llm.kind.isCLI
                               ? "CLI providers wait at least 60 s to start a session; then the raw transcript is inserted"
                               : "Then the raw transcript is inserted") {
                        SettingsNumberStepper(title: "Timeout", value: Binding(
                            get: { Int(settings.llm.timeoutSeconds) },
                            set: { settings.llm.timeoutSeconds = Double($0) }
                        ), in: 3...120, unit: "s")
                    }
                    RowDivider()
                    SettingRow(title: "Skip refinement under") {
                        SettingsNumberStepper(title: "Skip refinement under", value: $settings.llm.minWordsForLLM, in: 0...20, unit: "words")
                    }
                    if !llm.kind.isCLI {
                        RowDivider()
                        SettingRow(title: "Thinking effort", subtitle: thinkingSubtitle) {
                            Picker("Thinking effort", selection: Binding(
                                get: { llm.kind == .gemini && settings.llm.thinkingEffort != .off ? .high : settings.llm.thinkingEffort },
                                set: { settings.llm.thinkingEffort = $0 }
                            )) {
                                ForEach(llm.kind == .gemini ? [.off, .high] : ThinkingEffort.standard) {
                                    Text(llm.kind == .gemini && $0 == .high ? "Automatic" : $0.title).tag($0)
                                }
                            }
                            .pickerStyle(.segmented).settingsPicker(width: 260)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .settingsDisclosure()
            }
        }
        .onChange(of: llm) { _, _ in cancelTest() }
        .onDisappear { cancelTest() }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { note in
            if note.object as? String == llm.keyRef { cancelTest() }
        }
    }

    private var thinkingSubtitle: String {
        if llm.kind == .gemini { return "Off requests no thinking when supported; Automatic uses the model default" }
        if [.cerebras, .groq].contains(llm.kind), llm.model.contains("gpt-oss") {
            return "This model requires reasoning; Off uses its lowest effort"
        }
        return "Cleanup needs none; higher levels cost seconds per dictation"
    }

    // MARK: - Provider rows

    @ViewBuilder
    private var localServerRows: some View {
        @Bindable var settings = container.settings
        SettingRow(title: "Model status", subtitle: statusSubtitle) {
            HStack(spacing: 8) {
                StatusDot(statusTone)
                switch container.models.llmStatus.state {
                case .loaded:
                    Button("Unload") { container.models.unloadLLM() }.buttonStyle(SoftButtonStyle())
                case .notLoaded, .failed:
                    Button("Load") { container.models.loadLLM() }.buttonStyle(SoftButtonStyle())
                case .loading:
                    ProgressView().controlSize(.small)
                default:
                    EmptyView()
                }
            }
        }
        RowDivider()
        SettingRow(title: "Server") {
            Picker("Server", selection: Binding<String>(
                get: { EndpointPreset.llm.first { $0.baseURL == settings.llm.baseURL }?.name ?? "Custom" },
                set: { name in
                    guard let p = EndpointPreset.llm.first(where: { $0.name == name }) else { return }
                    settings.llm.baseURL = p.baseURL
                    settings.llm.model = p.defaultModel
                    settings.llm.apiKeyRef = p.keyRef
                }
            )) {
                ForEach(EndpointPreset.llm) { Text($0.name).tag($0.name) }
            }
            .settingsPicker(width: Theme.fieldWidth)
        }
        RowDivider()
        SettingRow(title: "Base URL") {
            TextField("Base URL", text: $settings.llm.baseURL).textFieldStyle(.roundedBorder)
                .labelsHidden().frame(width: Theme.fieldWidth)
        }
        RowDivider()
        SettingRow(title: "API key", subtitle: "Local servers usually need none") {
            APIKeyField(account: llm.keyRef)
        }
        RowDivider()
        RefinementModelRow()
        RowDivider()
        testRow
    }

    @ViewBuilder
    private var cloudRows: some View {
        SettingRow(title: "\(llm.kind.title) API key", subtitle: llm.kind == .openRouter ? "Shared with OpenRouter speech recognition" : "Stored in your Keychain") {
            APIKeyField(account: llm.keyRef, console: llm.kind.keyConsoleURL)
        }
        RowDivider()
        RefinementModelRow()
        if llm.kind == .openRouter {
            RowDivider()
            OpenRouterProviderSettings()
        }
        RowDivider()
        testRow
    }

    /// A CLI already installed and logged in on this Mac: nothing to configure but
    /// where it lives and which model it should ask for.
    @ViewBuilder
    private var cliRows: some View {
        SettingRow(title: "Command", subtitle: cliSubtitle) {
            HStack(spacing: 8) {
                StatusDot(ok: llm.cliExecutable != nil)
                Button("Locate Again") {
                    var config = container.settings.llm
                    config.cliPaths[config.kind.rawValue] = config.kind.cliTool?.locate() ?? ""
                    container.settings.llm = config
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
        RowDivider()
        RefinementModelRow()
        RowDivider()
        testRow
    }

    private var cliSubtitle: String {
        guard let path = llm.cliExecutable else {
            return "\(llm.kind.cliTool?.executableName ?? "CLI") not found. Install it, then press Locate Again."
        }
        return path
    }

    private var testRow: some View {
        SettingRow(title: "Connection", subtitle: testResult.isEmpty ? nil : testResult) {
            if testTask != nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { cancelTest() }.buttonStyle(SoftButtonStyle())
                }
            } else {
                Button("Test") {
                    let token = UUID()
                    testID = token
                    testTask = Task { await test(token: token) }
                }.buttonStyle(SoftButtonStyle())
            }
        }
    }

    private var statusSubtitle: String {
        let label = container.models.llmStatus.label
        switch container.models.llmStatus.state {
        case .loaded, .notLoaded, .loading:
            return label + (container.settings.unloadLLMOnQuit ? " · unloads when Airdraft quits" : "")
        default:
            return label
        }
    }

    private var statusTone: StatusDot.Tone {
        switch container.models.llmStatus.state {
        case .loaded: return .ok
        case .loading: return .busy
        case .failed, .unreachable: return .attention
        default: return .inactive
        }
    }

    private func cancelTest() {
        testID = UUID()
        testTask?.cancel()
        testTask = nil
        testResult = ""
    }

    private func test(token: UUID) async {
        let config = llm
        testResult = ""
        defer { if testID == token { testTask = nil } }
        let candidate = await container.factory.refiner(for: config)
        guard testID == token, !Task.isCancelled else { return }
        guard let refiner = candidate else {
            testResult = "Refinement is off"
            return
        }
        let req = RefineRequest(
            transcript: "嗯 這是一個 測試 就是說 我們今天要 第一 買牛奶 第二 寫程式",
            profile: container.profiles.activeProfile,
            baseRules: container.profiles.baseRules,
            context: .empty, family: .general, dictionary: []
        )
        do {
            let r = try await refiner.refine(req)
            guard testID == token, !Task.isCancelled else { return }
            let host = config.kind == .openRouter
                ? " · " + (r.servedBy.map { "Served by \($0)" } ?? "Provider not reported")
                : ""
            testResult = "OK in \(r.latencyMs) ms\(host): \(r.text.prefix(60))"
        } catch {
            guard testID == token, !Task.isCancelled else { return }
            testResult = "Failed. \(error.localizedDescription)"
        }
    }
}

struct APIKeyField: View {
    let account: String
    var console: URL? = nil
    @State private var editor = CredentialEditor()

    private var needsAccess: Bool {
        editor.needsAccess || (RenderMode.isActive &&
            RenderMode.value("KEYCHAIN") == "locked")
    }

    var body: some View {
        @Bindable var editor = editor
        VStack(alignment: .trailing, spacing: Theme.controlSpacing) {
            HStack(spacing: 8) {
                if let console {
                    Button("Get a Key") { NSWorkspace.shared.open(console) }
                        .buttonStyle(.link).font(.system(size: 12)).fixedSize()
                }
                SecureField(needsAccess ? "Saved key needs approval" : "Enter API key", text: $editor.value)
                    .textFieldStyle(.roundedBorder).frame(width: Theme.fieldWidth).disabled(editor.isBusy)
                Button("Save") { Task { await editor.save() } }
                    .buttonStyle(SoftButtonStyle()).fixedSize().disabled(!editor.canSave)
            }
                if needsAccess {
                    Button("Allow Access") { Task { await editor.authorize() } }
                        .buttonStyle(SoftButtonStyle()).fixedSize().disabled(editor.isBusy)
                }
            if let message = editor.message ?? (needsAccess ? "Your saved key needs access approval." : nil) {
                Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Theme.fieldWidth + 100, alignment: .trailing)
            }
        }
        .task(id: account) {
            guard !RenderMode.isActive else { return }
            await editor.load(account: account)
        }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { note in
            guard note.object as? String == account, !editor.isBusy, !editor.canSave else { return }
            Task { await editor.load(account: account) }
        }
        .onDisappear { editor.cancel() }
    }
}

/// Model picker for refinement: asks the selected provider what it serves.
struct RefinementModelRow: View {
    @Environment(AppContainer.self) private var container
    @State private var models: [String] = []
    @State private var cliModels: [CLIModelInfo] = []
    @State private var status = ""
    @State private var loading = false
    @State private var customModel = false
    @State private var refreshID = UUID()

    private var llm: LLMConfig { container.settings.llm }
    private var tool: CLIRefiner.Tool? { llm.kind.cliTool }
    private var availableEfforts: [ThinkingEffort] {
        CLIModelInfo.selected(llm.model, in: cliModels)?.dictationEfforts ?? tool?.effortSuggestions ?? ThinkingEffort.standard
    }
    private var selectedEffort: ThinkingEffort {
        llm.thinkingEffort.supported(in: availableEfforts) ?? .off
    }
    private var effortSubtitle: String {
        if availableEfforts.isEmpty { return "This model does not offer thinking effort control" }
        if llm.thinkingEffort != selectedEffort {
            return "This model uses \(selectedEffort.title.lowercased()) for the saved \(llm.thinkingEffort.title.lowercased()) setting"
        }
        return "Lower levels are faster; higher levels spend more tokens"
    }

    var body: some View {
        @Bindable var settings = container.settings
        Group {
            SettingRow(title: "Model", subtitle: status.isEmpty ? nil : status) {
                HStack(spacing: 6) {
                    if models.isEmpty || customModel {
                        TextField("Model ID or alias", text: $settings.llm.model)
                            .textFieldStyle(.roundedBorder).frame(width: Theme.fieldWidth)
                            .accessibilityLabel("Model ID or alias")
                    } else {
                        Picker("Model", selection: $settings.llm.model) {
                            if tool != nil { Text("CLI default").tag("") }
                            ForEach(models, id: \.self) { id in
                                Text(modelTitle(id)).tag(id)
                            }
                            if !settings.llm.model.isEmpty, !models.contains(settings.llm.model) {
                                Text("\(settings.llm.model) (custom)").tag(settings.llm.model)
                            }
                        }
                        .settingsPicker(width: Theme.fieldWidth)
                    }
                    if !models.isEmpty {
                        Button { customModel.toggle() } label: {
                            Image(systemName: customModel ? "list.bullet" : "pencil")
                        }
                        .buttonStyle(SoftButtonStyle())
                        .help(customModel ? "Choose from the model list" : "Use a model ID supported by the provider")
                        .accessibilityLabel(customModel ? "Choose a listed model" : "Enter a custom model")
                    }
                    RefreshButton(loading: loading, help: "Reload the model list from the provider") { refreshID = UUID() }
                }
            }
            if tool != nil {
                RowDivider()
                SettingRow(title: "Thinking effort", subtitle: effortSubtitle) {
                    if availableEfforts.isEmpty {
                        Text("Not supported").foregroundStyle(.secondary)
                    } else {
                        Picker("Thinking effort", selection: Binding(
                            get: { selectedEffort },
                            set: { settings.llm.thinkingEffort = $0 }
                        )) {
                            ForEach(availableEfforts) { Text($0.title).tag($0) }
                        }
                        .settingsPicker(width: 170)
                    }
                }
            }
        }
        .task(id: "\(taskKey)|\(refreshID)") { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { note in
            if note.object as? String == llm.keyRef { refreshID = UUID() }
        }
    }

    private func modelTitle(_ id: String) -> String {
        guard let info = cliModels.first(where: { $0.id == id }) else { return id }
        return info.title + (info.hidden ? " (hidden)" : "")
    }

    private var taskKey: String { "\(llm.kind.rawValue)|\(llm.baseURL)|\(llm.keyRef)|\(llm.cliExecutable ?? "")" }

    private func refresh() async {
        guard !RenderMode.isActive else { return }
        let key = taskKey
        let config = llm
        loading = true
        models = config.kind.cliTool?.modelSuggestions ?? []
        cliModels = []
        status = "Loading models…"
        defer { if key == taskKey, !Task.isCancelled { loading = false } }
        do {
            let ids: [String]
            var info: [CLIModelInfo] = []
            if let tool = config.kind.cliTool {
                guard let executable = config.cliExecutable else { throw RefinerError.invalidResponse }
                info = try await CLIModelCatalog.shared.models(tool: tool, executable: executable, refresh: true)
                ids = info.map(\.id)
            } else {
                ids = try await ModelCatalog.refinementModels(for: config)
            }
            guard key == taskKey, !Task.isCancelled else { return }
            models = ids
            cliModels = info
            status = ids.isEmpty ? "No models listed; enter a model ID." : "\(ids.count) models from \(config.kind.isCLI ? "your CLI" : "the provider")"
            if !config.kind.isCLI, container.settings.llm.model.isEmpty, let first = ids.first {
                container.settings.llm.model = first
            }
        } catch {
            guard key == taskKey, !Task.isCancelled else { return }
            status = config.kind.isCLI
                ? "Could not read CLI models. Use a suggestion or enter any model ID."
                : Self.shortMessage(for: error)
        }
    }

    /// Endpoints answer with a page of JSON; the row only has space for the point of it.
    static func shortMessage(for error: Error) -> String {
        if let error = error as? Keychain.AccessError { return error.localizedDescription }
        if case RefinerError.http(let status, _) = error {
            switch status {
            case 401, 403: return "Add a valid API key to list models."
            case 404: return "Endpoint not found; check the base URL."
            case 429: return "Rate limited by the provider; try again shortly."
            default: return "Provider returned HTTP \(status); type the model id."
            }
        }
        if error is RefinerError { return error.localizedDescription }
        return "Could not reach the provider; type the model id."
    }
}
