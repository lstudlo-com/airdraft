import AirdraftCore
import SwiftUI

struct ModelsPage: View {
    @Environment(AppContainer.self) private var container
    @State private var query = ""
    @State private var filter: Filter = .all

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

    private var visible: [ModelEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ModelCatalogue.entries.filter { e in
            let matchesQuery = q.isEmpty || e.title.lowercased().contains(q) || e.vendor.lowercased().contains(q)
            let matchesFilter = filter == .all || (filter == .cloud) == e.isCloud
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        @Bindable var settings = container.settings
        PageScaffold {
            HStack {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                Spacer()
            }

            Card(padding: 0) {
                HStack(spacing: 12) {
                    Text("Model").frame(width: 300, alignment: .leading)
                    Text("Speed").frame(width: 70, alignment: .leading)
                    Text("Accuracy").frame(width: 70, alignment: .leading)
                    Text("Storage").frame(width: 84, alignment: .leading)
                    Spacer()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                RowDivider()
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider().padding(.leading, 14) }
                    ModelRow(entry: entry)
                }
            }

            remoteSpeechSettings

            SectionTitle("Refinement")
            RefinementSettings()

            SectionTitle("Memory")
            Card {
                SettingRow(title: "Unload idle speech model", subtitle: "Frees RAM when you have not dictated for a while") {
                    Picker("", selection: $settings.idleUnloadMinutes) {
                        Text("After 5 min").tag(5)
                        Text("After 10 min").tag(10)
                        Text("After 30 min").tag(30)
                        Text("Never").tag(0)
                    }
                    .labelsHidden().frame(width: 140)
                }
                RowDivider()
                SettingRow(title: "Unload LLM when quitting", subtitle: "LM Studio keeps models in memory until they are unloaded") {
                    Toggle("", isOn: $settings.unloadLLMOnQuit).labelsHidden().toggleStyle(.switch)
                }
            }

            SectionTitle("Speech options")
            Card {
                SettingRow(title: "Language", subtitle: "Blank = auto-detect") {
                    TextField("auto", text: $settings.asr.language).textFieldStyle(.roundedBorder).frame(width: 90)
                }
                RowDivider()
                SettingRow(title: "Chinese script") {
                    Picker("", selection: $settings.asr.chineseScript) {
                        ForEach(ChineseScript.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
                if settings.asr.kind == .apple {
                    RowDivider()
                    SettingRow(title: "Apple Speech locale", subtitle: "No auto language detection with this engine") {
                        TextField("zh-TW", text: $settings.asr.appleLocale).textFieldStyle(.roundedBorder).frame(width: 110)
                    }
                }
            }
        } accessory: {
            SearchField(text: $query, placeholder: "Search models")
        }
        .onAppear {
            Task { await container.models.refreshLLMStatus() }
        }
    }

    /// Key and endpoint for whichever cloud speech provider is active.
    @ViewBuilder
    private var remoteSpeechSettings: some View {
        @Bindable var settings = container.settings
        switch settings.asr.kind {
        case .openAICompatible:
            Card {
                SettingRow(title: settings.asr.baseURL.contains("groq") ? "Groq API key" : "OpenAI API key", subtitle: "Audio leaves this Mac") {
                    APIKeyField(account: settings.asr.apiKeyRef)
                }
                RowDivider()
                SettingRow(title: "Endpoint") {
                    TextField("", text: $settings.asr.baseURL).textFieldStyle(.roundedBorder).frame(width: 300)
                }
                RowDivider()
                ModelField(title: "Model", model: $settings.asr.model, baseURL: settings.asr.baseURL, apiKeyRef: settings.asr.apiKeyRef, speechOnly: true)
            }
        case .elevenLabs:
            Card {
                SettingRow(title: "ElevenLabs API key", subtitle: "Audio leaves this Mac") {
                    APIKeyField(account: EndpointPreset.elevenLabsKeyRef)
                }
                RowDivider()
                SettingRow(title: "Model") {
                    Picker("", selection: $settings.asr.elevenLabsModel) {
                        ForEach(EndpointPreset.elevenLabsModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 160)
                }
            }
        default:
            EmptyView()
        }
    }
}
