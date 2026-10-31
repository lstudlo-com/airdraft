import AirdraftCore
import SwiftUI

/// Refinement providers that work on an iPhone: Apple Intelligence on device,
/// or a cloud provider with the user's own key. Refinement is best effort:
/// any failure keeps the original transcript.
struct RefinementSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelError: String?

    static let providers: [LLMProviderKind] = [.none, .appleIntelligence, .openAI, .anthropic, .gemini,
                                              .openRouter, .groq, .cerebras, .openAICompatible]

    var body: some View {
        @Bindable var settings = settings
        SoftPage {
            SoftSection(title: "Provider") {
                ForEach(Array(Self.providers.enumerated()), id: \.element) { index, kind in
                    if index > 0 { RowDivider() }
                    Button {
                        settings.llm.select(kind)
                        models = []
                        modelError = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind == .none ? String(localized: "Off") : kind.title)
                                    .foregroundStyle(.primary)
                                if let detail = detail(for: kind) {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer()
                            if settings.llm.kind == kind {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: MobileTheme.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.llm.kind == kind ? .isSelected : [])
                }
            }
            if settings.llm.kind.isCloud || settings.llm.kind == .openAICompatible {
                SoftSection(title: "Connection") {
                    if settings.llm.kind == .openAICompatible {
                        TextField("Server URL", text: $settings.llm.baseURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(minHeight: MobileTheme.touchTarget)
                            .background { NeumorphicSurface(shape: MobileTheme.controlShape, inset: true, depth: 1.5) }
                        RowDivider()
                    }
                    APIKeyField(account: settings.llm.keyRef)
                    RowDivider()
                    TextField("Model", text: $settings.llm.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(minHeight: MobileTheme.touchTarget)
                        .background { NeumorphicSurface(shape: MobileTheme.controlShape, inset: true, depth: 1.5) }
                    HStack(spacing: 12) {
                        Button(loadingModels ? "Loading…" : "Load Models") { Task { await loadModels() } }
                            .buttonStyle(.soft)
                            .disabled(loadingModels)
                        if !models.isEmpty {
                            Menu {
                                ForEach(models, id: \.self) { model in
                                    Button(model) { settings.llm.model = model }
                                }
                            } label: {
                                Label("Choose", systemImage: "chevron.up.chevron.down")
                                    .frame(maxWidth: .infinity, minHeight: MobileTheme.touchTarget)
                            }
                            .background { MobileRaisedSurface(shape: MobileTheme.controlShape) }
                        }
                    }
                    if let modelError {
                        Text(modelError).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Text("The provider receives each transcript it refines and bills your account.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Refinement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(for kind: LLMProviderKind) -> String? {
        switch kind {
        case .none: return String(localized: "Insert exactly what speech recognition heard.")
        case .appleIntelligence:
            return AppleIntelligenceRefiner.unavailableReason ?? String(localized: "On this iPhone. Nothing leaves the device.")
        case .openAICompatible: return String(localized: "A server you run, such as LM Studio on your network.")
        default: return nil
        }
    }

    private func loadModels() async {
        loadingModels = true
        defer { loadingModels = false }
        do {
            models = try await ModelCatalog.refinementModels(for: settings.llm, timeout: 10)
            modelError = models.isEmpty ? String(localized: "The provider listed no models.") : nil
        } catch {
            modelError = error.localizedDescription
        }
    }
}
