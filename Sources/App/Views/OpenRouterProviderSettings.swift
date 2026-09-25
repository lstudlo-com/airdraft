import AirdraftCore
import SwiftUI

private struct OpenRouterPreviewEndpointsKey: EnvironmentKey {
    static let defaultValue: [OpenRouterEndpoint]? = nil
}

extension EnvironmentValues {
    var openRouterPreviewEndpoints: [OpenRouterEndpoint]? {
        get { self[OpenRouterPreviewEndpointsKey.self] }
        set { self[OpenRouterPreviewEndpointsKey.self] = newValue }
    }
}

/// Additional rows inside the existing refinement SettingsCard.
@MainActor
struct OpenRouterProviderSettings: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openRouterPreviewEndpoints) private var previewEndpoints
    @State private var endpoints: [OpenRouterEndpoint] = []
    @State private var loadedModel = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var refreshedAt: Date?
    @State private var refreshID = UUID()
    @State private var collapsedVariants = Set<String>()

    private var model: String { container.settings.llm.model }
    private var routing: OpenRouterRouting { container.settings.llm.openRouterRouting }
    private var taskKey: String { "\(model)|\(refreshID)" }
    private var listedEndpoints: [OpenRouterEndpoint] {
        previewEndpoints ?? (loadedModel == model ? endpoints : [])
    }
    private var selectedEndpoint: OpenRouterEndpoint? {
        listedEndpoints.first { $0.id == routing.providerID }
    }
    private var relatedEndpoints: [OpenRouterEndpoint] {
        OpenRouterCatalog.relatedEndpoints(providerID: routing.providerID, in: listedEndpoints)
    }

    private func providerTitle(_ endpoint: OpenRouterEndpoint) -> String {
        OpenRouterCatalog.relatedEndpoints(providerID: endpoint.id, in: listedEndpoints).count > 1
            ? "\(endpoint.title) · provider-wide" : endpoint.title
    }

    var body: some View {
        @Bindable var settings = container.settings
        Group {
            SettingRow(title: "Inference provider", subtitle: "Saved separately for each model") {
                HStack(spacing: Theme.sectionTitleSpacing) {
                    Picker("Inference provider", selection: $settings.llm.openRouterRouting.providerID) {
                        Text("Automatic").tag("")
                        ForEach(listedEndpoints) { endpoint in
                            Text(providerTitle(endpoint)).tag(endpoint.id)
                        }
                        if !routing.providerID.isEmpty, selectedEndpoint == nil {
                            Text("\(routing.providerID) (saved)").tag(routing.providerID)
                        }
                    }
                    .settingsPicker(width: 240)
                    RefreshButton(loading: loading, help: "Reload providers and their current performance and prices",
                                  disabled: model.isEmpty) { refreshID = UUID() }
                }
            }

            if !routing.providerID.isEmpty {
                SettingRow(title: "Allow other providers as fallback",
                           subtitle: routing.allowFallbacks
                            ? "Other hosts may have different speed and pricing"
                            : "If this host fails, insert the original transcript") {
                    Toggle("Allow other providers as fallback", isOn: $settings.llm.openRouterRouting.allowFallbacks)
                        .labelsHidden().toggleStyle(.switch)
                }
                if model.hasSuffix(":nitro") || model.hasSuffix(":floor") {
                    Text("Choosing a provider overrides this model variant's speed or price sorting. Select Automatic to use that sorting.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else if loading {
                Text("Loading providers and performance…").font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else if routing.providerID.isEmpty {
                Text("OpenRouter chooses the host. Select one to see its speed, pricing and limits.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else if relatedEndpoints.isEmpty {
                Text("This saved provider is not currently listed for this model. Choose another provider or refresh. Your routing preference is preserved.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }

            if relatedEndpoints.count > 1 {
                RowDivider()
                EmptyNote("This provider has several endpoints. Choose one and turn off fallback to restrict routing.")
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Listed default-tier endpoints are shown separately for comparison. Flex and Priority endpoints require an explicit choice; Automatic routing can also use model variants.")
                ForEach(relatedEndpoints) { endpoint in
                    DisclosureGroup(isExpanded: Binding(
                        get: { !collapsedVariants.contains(endpoint.id) },
                        set: { expanded in
                            if expanded { collapsedVariants.remove(endpoint.id) }
                            else { collapsedVariants.insert(endpoint.id) }
                        }
                    )) {
                        endpointDetails(endpoint)
                            .padding(.top, Theme.controlSpacing)
                    } label: {
                        HStack {
                            Text(endpoint.title)
                            Spacer()
                            Text(measurement(endpoint.throughput, unit: "tokens/s"))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12.5))
                    }
                }
            } else if let endpoint = relatedEndpoints.first {
                RowDivider()
                endpointDetails(endpoint)
            }

            HStack(spacing: Theme.sectionTitleSpacing) {
                if let url = try? OpenRouterCatalog.endpointsURL(model: model) {
                    Link(destination: url) { Label("Provider data", systemImage: "arrow.up.right") }
                }
                Spacer()
                if previewEndpoints != nil {
                    Text("Preview data")
                } else if let refreshedAt, loadedModel == model {
                    Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .task(id: taskKey) { await refresh() }
    }

    private func endpointDetails(_ endpoint: OpenRouterEndpoint) -> some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            if let status = endpoint.status, status != 0 {
                Text("OpenRouter reports this endpoint as unavailable. Refresh or choose another host.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                      alignment: .leading, spacing: Theme.controlSpacing) {
                metric(endpoint.throughput?.isMedian == true ? "Output speed · median" : "Output speed",
                       value: measurement(endpoint.throughput, unit: "tokens/s"),
                       help: "Output tokens per second reported by OpenRouter over the last 30 minutes. This is generation speed, not total dictation time. Missing measurements are not estimates.")
                metric(endpoint.latency?.isMedian == true ? "Latency · median" : "Latency",
                       value: measurement(endpoint.latency, unit: "s"),
                       help: "Endpoint latency reported by OpenRouter over the last 30 minutes.")
                metric("Uptime · 30 min", value: endpoint.uptime.map { String(format: "%.2f%%", $0) } ?? "Not reported",
                       help: "Recent endpoint uptime reported by OpenRouter.")
                metric("Input · USD / 1M tokens", value: price(endpoint.pricing?.prompt))
                metric("Output · USD / 1M tokens", value: price(endpoint.pricing?.completion))
                metric("Cached input · USD / 1M", value: price(endpoint.pricing?.cachedInput))
                metric("Context window", value: tokens(endpoint.contextLength))
                metric("Maximum output", value: tokens(endpoint.maxCompletionTokens))
                metric("Precision", value: endpoint.quantization?.uppercased() ?? "Not reported")
            }
        }
    }

    /// Value above label, as in the other metric displays.
    private func metric(_ label: String, value: String, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help(help)
    }

    private func measurement(_ value: OpenRouterEndpoint.Measurement?, unit: String) -> String {
        guard let number = value?.value else { return "Not reported" }
        return number.formatted(.number.precision(.fractionLength(0...2))) + " " + unit
    }

    private func price(_ value: Double?) -> String {
        guard let value else { return "Not reported" }
        return (value * 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(2...4)))
    }

    private func tokens(_ value: Int?) -> String {
        value.map { "\($0.formatted()) tokens" } ?? "Not reported"
    }

    private func refresh() async {
        guard !RenderMode.isActive else { return }
        let key = taskKey
        let requestedModel = model
        endpoints = []
        loadedModel = ""
        refreshedAt = nil
        errorMessage = nil
        loading = true
        defer { if key == taskKey, !Task.isCancelled { loading = false } }
        do {
            // Debounce custom model typing. Cancellation also prevents an old model's
            // response from replacing the newly selected model's details.
            try await Task.sleep(for: .milliseconds(250))
            let result = try await OpenRouterCatalog.fetch(model: requestedModel)
            guard key == taskKey, !Task.isCancelled else { return }
            endpoints = result
            loadedModel = requestedModel
            refreshedAt = Date()
            if result.isEmpty { errorMessage = "No providers are currently listed for this model. Choose another model or refresh." }
        } catch {
            guard key == taskKey, !Task.isCancelled else { return }
            if case RefinerError.http(let status, _) = error, status == 404 {
                errorMessage = "No provider data found for this model. Check the model ID or choose a listed model."
            } else {
                errorMessage = "Could not load provider data. Refresh to try again. Your routing preference is preserved."
            }
        }
    }
}
