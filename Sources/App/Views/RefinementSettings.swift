import AppKit
import AirdraftCore
import SwiftUI

/// The refinement section on the Models page: pick a provider, then only the
/// rows that provider needs. Everything that is the same for all of them
/// (temperature, timeout, thresholds) sits under Advanced.
struct RefinementSettings: View {
    @Environment(AppContainer.self) private var container
    @State private var testResult = ""
    @State private var keysPresent: Set<String> = []

    private var llm: LLMConfig { container.settings.llm }

    var body: some View {
        @Bindable var settings = container.settings
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            Card {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(LLMProviderKind.allCases) { kind in
                        ProviderTile(
                            kind: kind,
                            selected: llm.kind == kind,
                            status: status(for: kind)
                        ) {
                            settings.llm.select(kind)
                            testResult = ""
                        }
                    }
                }
            }

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

            DisclosureGroup("Advanced") {
                SettingsCard {
                    SettingRow(title: "Temperature") {
                        HStack {
                            Slider(value: $settings.llm.temperature, in: 0...1, step: 0.1).frame(width: 160)
                            Text(String(format: "%.1f", settings.llm.temperature)).monospacedDigit().frame(width: 28)
                        }
                    }
                    RowDivider()
                    SettingRow(title: "Timeout", subtitle: "Then the raw transcript is inserted") {
                        Stepper("\(Int(settings.llm.timeoutSeconds)) s", value: $settings.llm.timeoutSeconds, in: 3...120, step: 1).frame(width: 110)
                    }
                    RowDivider()
                    SettingRow(title: "Skip LLM under") {
                        Stepper("\(settings.llm.minWordsForLLM) words", value: $settings.llm.minWordsForLLM, in: 0...20).frame(width: 120)
                    }
                    if !llm.kind.isCLI {
                        RowDivider()
                        SettingRow(title: "Thinking effort", subtitle: thinkingSubtitle) {
                            Picker("", selection: $settings.llm.thinkingEffort) {
                                ForEach(ThinkingEffort.standard) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshKeys)
    }

    private var thinkingSubtitle: String {
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
                statusDot
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
            Picker("", selection: Binding<String>(
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
            .labelsHidden().frame(width: 220)
        }
        RowDivider()
        SettingRow(title: "Base URL") {
            TextField("", text: $settings.llm.baseURL).textFieldStyle(.roundedBorder).frame(width: 300)
        }
        RowDivider()
        SettingRow(title: "API key", subtitle: "Local servers usually need none") {
            APIKeyField(account: llm.keyRef, onSave: refreshKeys)
        }
        RowDivider()
        RefinementModelRow()
        RowDivider()
        testRow
    }

    @ViewBuilder
    private var cloudRows: some View {
        SettingRow(title: "\(llm.kind.title) API key", subtitle: "Stored in your Keychain") {
            APIKeyField(account: llm.keyRef, console: llm.kind.keyConsoleURL, onSave: refreshKeys)
        }
        RowDivider()
        RefinementModelRow()
        RowDivider()
        testRow
        Text("Text is sent to \(llm.kind.title) for refinement. Audio is handled by your speech recognition provider.")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
    }

    /// A CLI already installed and logged in on this Mac: nothing to configure but
    /// where it lives and which model it should ask for.
    @ViewBuilder
    private var cliRows: some View {
        SettingRow(title: "Command", subtitle: cliSubtitle) {
            HStack(spacing: 8) {
                Circle().fill(llm.cliExecutable == nil ? Color.orange : Color.green).frame(width: 7, height: 7)
                Button("Locate again") {
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
        Text("Runs on this Mac through your \(llm.kind == .claudeCode ? "Claude" : "ChatGPT") subscription: no API key, no per-token bill. Each call is a one-shot run with no tools and no project context.")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
    }

    private var cliSubtitle: String {
        guard let path = llm.cliExecutable else {
            return "\(llm.kind.cliTool?.executableName ?? "CLI") not found. Install it, then press Locate again."
        }
        return path
    }

    private var testRow: some View {
        SettingRow(title: "Connection", subtitle: testResult.isEmpty ? nil : testResult) {
            Button("Test") { Task { await test() } }.buttonStyle(SoftButtonStyle())
        }
    }

    // MARK: - Status

    private func status(for kind: LLMProviderKind) -> String {
        switch kind {
        case .none: return "No LLM"
        case .openAICompatible: return llm.kind == kind ? container.models.llmStatus.label : "LM Studio, Ollama"
        case .claudeCode, .codex: return kind.cliTool?.locate() == nil ? "Not installed" : "Subscription"
        default: return keysPresent.contains(kind.keyRef) ? "Key saved" : "Add key"
        }
    }

    private func refreshKeys() {
        keysPresent = Set(LLMProviderKind.allCases.filter { !$0.keyRef.isEmpty && !(Keychain.get($0.keyRef) ?? "").isEmpty }.map(\.keyRef))
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

    private var statusDot: some View {
        let color: Color = {
            switch container.models.llmStatus.state {
            case .loaded: return .green
            case .loading: return .yellow
            case .failed, .unreachable: return .orange
            default: return .secondary.opacity(0.5)
            }
        }()
        return Circle().fill(color).frame(width: 7, height: 7)
    }

    private func test() async {
        testResult = "Testing…"
        guard let refiner = await container.factory.refiner(for: container.settings.llm) else {
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
            testResult = "OK in \(r.latencyMs) ms: \(r.text.prefix(60))"
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }
}

/// One provider choice: icon, name, and what it needs right now.
struct ProviderTile: View {
    let kind: LLMProviderKind
    let selected: Bool
    let status: String
    let action: () -> Void
    @State private var hovering = false

    private var color: Color {
        switch kind {
        case .openAICompatible: return .indigo
        case .openAI: return .green
        case .anthropic: return .orange
        case .gemini: return .blue
        case .openRouter: return .purple
        case .cerebras: return .orange
        case .groq: return .pink
        case .claudeCode: return .orange
        case .codex: return .teal
        case .none: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            IconBadge(symbol: kind.symbol, color: color, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.shortTitle).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(status).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.12) : (hovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.035)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help("\(kind.title) — \(kind.subtitle)")
    }
}

struct APIKeyField: View {
    let account: String
    var console: URL? = nil
    var onSave: (() -> Void)? = nil
    @State private var value = ""
    @State private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            if let console {
                Button("Get a key") { NSWorkspace.shared.open(console) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .fixedSize()
            }
            SecureField("", text: $value).textFieldStyle(.roundedBorder).frame(width: 200)
            Button(saved ? "Saved" : "Save") {
                Keychain.set(value, for: account)
                saved = true
                onSave?()
                Task { try? await Task.sleep(for: .seconds(1.2)); saved = false }
            }
            .buttonStyle(SoftButtonStyle())
            .fixedSize()
        }
        .onAppear { value = Keychain.get(account) ?? "" }
        .onChange(of: account) { _, new in value = Keychain.get(new) ?? "" }
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
                            .textFieldStyle(.roundedBorder).frame(width: 240)
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
                        .labelsHidden().frame(width: 240)
                    }
                    if !models.isEmpty {
                        Button { customModel.toggle() } label: {
                            Image(systemName: customModel ? "list.bullet" : "pencil")
                        }
                        .buttonStyle(SoftButtonStyle())
                        .help(customModel ? "Choose from the model list" : "Use a model ID supported by the provider")
                        .accessibilityLabel(customModel ? "Choose a listed model" : "Enter a custom model")
                    }
                    Button { refreshID = UUID() } label: {
                        if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(loading)
                    .help("Reload the model list from the provider")
                    .accessibilityLabel("Reload models")
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
                        .labelsHidden().frame(width: 170)
                    }
                }
            }
        }
        .task(id: "\(taskKey)|\(refreshID)") { await refresh() }
    }

    private func modelTitle(_ id: String) -> String {
        guard let info = cliModels.first(where: { $0.id == id }) else { return id }
        return info.title + (info.hidden ? " (hidden)" : "")
    }

    private var taskKey: String { "\(llm.kind.rawValue)|\(llm.baseURL)|\(llm.cliExecutable ?? "")" }

    private func refresh() async {
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
    private static func shortMessage(for error: Error) -> String {
        if case RefinerError.http(let status, _) = error {
            switch status {
            case 401, 403: return "Add a valid API key to list models."
            case 404: return "Endpoint not found; check the base URL."
            case 429: return "Rate limited by the provider; try again shortly."
            default: return "Provider returned HTTP \(status); type the model id."
            }
        }
        return "Could not reach the provider; type the model id."
    }
}
