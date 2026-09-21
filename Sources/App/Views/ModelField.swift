import AirdraftCore
import SwiftUI

/// Lists the models an OpenAI-compatible endpoint reports so nobody has to type
/// an id. Used by the remote speech provider rows.
struct ModelField: View {
    let title: String
    @Binding var model: String
    let baseURL: String
    let apiKeyRef: String
    var speechOnly = false

    @State private var models: [String] = []
    @State private var status = ""
    @State private var loading = false
    @State private var requestID = UUID()
    @State private var refreshID = UUID()

    var body: some View {
        SettingRow(title: title, subtitle: status.isEmpty ? nil : status) {
            HStack(spacing: 6) {
                if models.isEmpty {
                    TextField("model id", text: $model).textFieldStyle(.roundedBorder).frame(width: 240)
                } else {
                    Picker("", selection: $model) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                        if !model.isEmpty, !models.contains(model) { Text("\(model) (not listed)").tag(model) }
                    }
                    .labelsHidden().frame(width: 240)
                }
                Button { refreshID = UUID() } label: {
                    if loading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(SoftButtonStyle())
                .help("Reload the model list from the endpoint")
            }
        }
        .task(id: "\(baseURL)|\(apiKeyRef)|\(refreshID)") { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { note in
            if note.object as? String == apiKeyRef { refreshID = UUID() }
        }
    }

    private func refresh() async {
        guard !ProcessInfo.processInfo.arguments.contains("--render-window") else { return }
        let token = UUID()
        requestID = token
        models = []
        guard let url = URL(string: baseURL), url.host != nil else {
            models = []
            status = "Enter a valid base URL."
            return
        }
        loading = true
        defer { if requestID == token { loading = false } }
        do {
            let account = apiKeyRef
            let key = try await Task.detached { try Keychain.read(account) }.value
            guard requestID == token, !Task.isCancelled else { return }
            var ids = try await ModelCatalog.fetch(baseURL: url, apiKey: key)
            guard requestID == token, !Task.isCancelled else { return }
            if speechOnly { ids = ModelCatalog.speechModels(in: ids) }
            models = ids
            status = ids.isEmpty ? "Endpoint lists no models." : "\(ids.count) models available"
            if model.isEmpty, let first = ids.first { model = first }
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            models = []
            status = "Could not list models; type the id. \(error.localizedDescription)"
        }
    }
}
