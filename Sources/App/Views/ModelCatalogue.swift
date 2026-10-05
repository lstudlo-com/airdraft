import AirdraftCore
import SwiftUI

/// One downloadable or built-in speech model.
/// Everything else (installed, loaded, download, delete) derives from `select`.
struct ModelEntry: Identifiable {
    enum Storage { case download(sizeLabel: String), builtIn }
    let id: String
    let title: String
    let vendor: String
    let provider: String
    let brand: ModelBrand
    let tags: [String]
    let speed: Int      // 1...5 relative rating; 0 means unrated
    let accuracy: Int   // 1...5 relative rating; 0 means unrated
    let storage: Storage
    let note: String
    /// Points a speech config at this model.
    let select: (inout ASRConfig) -> Void

    func config(from base: ASRConfig) -> ASRConfig {
        var config = base
        select(&config)
        return config
    }

    func isSelected(_ current: ASRConfig) -> Bool {
        let mine = config(from: current)
        guard mine.kind == current.kind else { return false }
        return mine.engineID == current.engineID
    }

    var isDownloadable: Bool { if case .download = storage { return true } else { return false } }
}

enum ModelCatalogue {
    static let entries: [ModelEntry] = [
        ModelEntry(
            id: "qwen3:1.7b", title: "Qwen3-ASR 1.7B", vendor: "Alibaba · MLX", provider: "Alibaba", brand: .qwen,
            tags: ["ZH", "EN", "+28"], speed: 4, accuracy: 5, storage: .download(sizeLabel: "2.3 GB"),
            note: "Best for mixed Chinese and English."
        ) { $0.kind = .qwen3; $0.qwen3Model = "aufklarer/Qwen3-ASR-1.7B-MLX-5bit" },
        ModelEntry(
            id: "qwen3:0.6b", title: "Qwen3-ASR 0.6B", vendor: "Alibaba · MLX", provider: "Alibaba", brand: .qwen,
            tags: ["ZH", "EN", "+28"], speed: 5, accuracy: 3, storage: .download(sizeLabel: "680 MB"),
            note: "Low memory, very fast."
        ) { $0.kind = .qwen3; $0.qwen3Model = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" },
        ModelEntry(
            id: "sherpa:fireRed", title: "FireRedASR2", vendor: "FireRed · ONNX", provider: "FireRed", brand: .fireRed,
            tags: ["ZH", "EN"], speed: 3, accuracy: 5, storage: .download(sizeLabel: SherpaTranscriber.Model.fireRed.sizeLabel),
            note: "Best Mandarin accuracy, 20+ dialects."
        ) { $0.kind = .fireRed },
        ModelEntry(
            id: "cohere", title: "Cohere Transcribe", vendor: "Cohere · MLX", provider: "Cohere", brand: .cohere,
            tags: ["EN", "ZH", "+12"], speed: 4, accuracy: 5, storage: .download(sizeLabel: "1.6 GB"),
            note: "Best open English model."
        ) { $0.kind = .cohere; $0.cohereModel = "aufklarer/Cohere-Transcribe-2B-MLX-5bit" },
        ModelEntry(
            id: "sherpa:senseVoice", title: "SenseVoice", vendor: "FunAudioLLM · ONNX", provider: "Alibaba", brand: .alibaba,
            tags: ["ZH", "YUE", "EN", "JA", "KO"], speed: 5, accuracy: 3, storage: .download(sizeLabel: SherpaTranscriber.Model.senseVoice.sizeLabel),
            note: "Fastest."
        ) { $0.kind = .senseVoice },
        ModelEntry(
            id: "sherpa:parakeet", title: "Parakeet TDT v3", vendor: "NVIDIA · ONNX", provider: "NVIDIA", brand: .nvidia,
            tags: ["EN", "+24"], speed: 0, accuracy: 0, storage: .download(sizeLabel: SherpaTranscriber.Model.parakeet.sizeLabel),
            note: "25 European languages. Does not support Chinese."
        ) { $0.kind = .parakeet },
        ModelEntry(
            id: "whisper:turbo", title: "Whisper v3 Turbo", vendor: "OpenAI · Core ML", provider: "OpenAI", brand: .openAI,
            tags: ["100 languages"], speed: 3, accuracy: 3, storage: .download(sizeLabel: "1.5 GB"),
            note: "Runs on the Neural Engine."
        ) { $0.kind = .whisperKit; $0.whisperModel = "large-v3-v20240930_turbo" },
        ModelEntry(
            id: "apple", title: "Apple Speech", vendor: "macOS 26 · Neural Engine", provider: "Apple", brand: .apple,
            tags: ["ZH-TW", "EN"], speed: 5, accuracy: 3, storage: .builtIn,
            note: "macOS manages language assets."
        ) { $0.kind = .apple },
    ]
}

/// Shared column geometry keeps both tables aligned, including at the minimum window width.
struct ModelComparisonColumns<Identity: View, Speed: View, Accuracy: View, Cost: View, Accessory: View>: View {
    @ViewBuilder var identity: Identity
    @ViewBuilder var speed: Speed
    @ViewBuilder var accuracy: Accuracy
    @ViewBuilder var cost: Cost
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: Theme.controlSpacing) {
            identity.frame(maxWidth: .infinity, alignment: .leading)
            speed.frame(width: 56, alignment: .leading)
            accuracy.frame(width: 64, alignment: .leading)
            cost.frame(width: 76, alignment: .leading)
            accessory.frame(width: 20)
        }
    }
}

/// Keep headings visible while the measured row content scrolls within one cap.
/// Short and empty results use only the space they need.
struct ModelTable<Rows: View>: View {
    let cost: String
    @ViewBuilder var rows: Rows
    @State private var contentHeight = Theme.modelTableMaxHeight

    var body: some View {
        Card(padding: 0) {
            ModelTableHeader(cost: cost)
            RowDivider()
            ScrollView(.vertical) {
                VStack(spacing: 0) { rows }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, Theme.modelTableMaxHeight))
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct ModelTableHeader: View {
    let cost: String
    var body: some View {
        ModelComparisonColumns {
            Text("Model")
        } speed: {
            Text("Speed")
        } accuracy: {
            Text("Accuracy")
        } cost: {
            Text(cost)
        } accessory: {
            Color.clear.frame(height: 1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(Theme.cardPadding)
    }
}

struct ModelMetric: View {
    let title: String
    let fraction: Double?
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SegmentMeter(fraction: fraction)
            Text(label).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(label). \(detail)")
    }
}

struct CloudModelRow: View {
    @Environment(AppContainer.self) private var container
    let preset: EndpointPreset.Speech
    let model: SpeechModelInfo
    @State private var hovering = false

    var body: some View {
        let selected = container.settings.asr.kind == preset.kind && container.settings.asr.model == model.id
        Button {
            container.settings.asr.select(preset.kind)
            container.settings.asr.selectModel(model.id)
        } label: {
            ModelComparisonColumns {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    ModelBrandIcon(brand: .speech(model, hostedBy: preset.kind))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title).font(.system(size: 13, weight: .medium))
                        Text(preset.name).supportingText()
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } speed: {
                ModelMetric(title: "Speed", fraction: speedFraction,
                            label: model.realtimeSpeedFactor.map { "\($0.formatted())×" } ?? "Not rated",
                            detail: model.speedDetail)
            } accuracy: {
                ModelMetric(title: "Accuracy", fraction: model.wordErrorRate.map { 1 - $0 / 100 },
                            label: model.wordErrorRate.map { "\($0.formatted())% WER" } ?? "Not rated",
                            detail: model.qualityDetail + (model.wordErrorRate == nil ? " No numeric rating is available." : " WER is word error rate; lower is better."))
            } cost: {
                Text(model.price).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    .help(model.billing)
            } accessory: {
                Color.clear.frame(height: 1)
            }
            .padding(Theme.cardPadding)
            .background(selected ? Color.primary.opacity(0.06) : (hovering ? Color.primary.opacity(0.03) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(model.title), hosted by \(preset.name), \(model.quality), speed: \(model.speed), \(model.price)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .help(model.qualityDetail + " " + model.speedDetail)
    }

    private var speedFraction: Double? {
        guard let factor = model.realtimeSpeedFactor,
              let fastest = SpeechModelInfo.models(for: preset.kind).compactMap(\.realtimeSpeedFactor).max(),
              fastest > 0 else { return nil }
        return factor / fastest
    }
}

struct ModelRow: View {
    @Environment(AppContainer.self) private var container
    let entry: ModelEntry
    @State private var error: String?
    @State private var installed = false
    @State private var hovering = false
    @State private var confirmDelete = false

    private var progress: ModelDownloader.Progress? { container.downloads.jobs[entryConfig.engineID]?.progress }
    private var downloadError: String? { container.downloads.jobs[entryConfig.engineID]?.error }

    private var entryConfig: ASRConfig { entry.config(from: container.settings.asr) }
    private var isSelectedForUse: Bool {
        entry.isSelected(container.settings.asr) || entry.isSelected(container.speechConfig)
    }

    var body: some View {
        @Bindable var settings = container.settings
        let selected = entry.isSelected(settings.asr)
        VStack(alignment: .leading, spacing: 6) {
            ModelComparisonColumns {
                Button {
                    guard installed else { return }
                    entry.select(&settings.asr)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(installed ? 0.6 : 0.3))
                        ModelBrandIcon(brand: entry.brand)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.system(size: 13, weight: .medium))
                            Text(entry.tags.joined(separator: " · ")).supportingText()
                            loadStateLabel
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(entry.title), \(entry.provider), \(entry.tags.joined(separator: ", "))")
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .help("\(entry.vendor). \(entry.note) \(installed ? "Use this model" : "Download first")")
            } speed: {
                ModelMetric(title: "Speed", fraction: entry.speed > 0 ? Double(entry.speed) / 5 : nil, label: entry.speed > 0 ? "\(entry.speed) / 5" : "Not rated",
                            detail: entry.speed > 0 ? "Airdraft's relative guidance for local models. Actual speed depends on your Mac." : "Not benchmarked in Airdraft.")
            } accuracy: {
                ModelMetric(title: "Accuracy", fraction: entry.accuracy > 0 ? Double(entry.accuracy) / 5 : nil, label: entry.accuracy > 0 ? "\(entry.accuracy) / 5" : "Not rated",
                            detail: (entry.accuracy > 0 ? "Airdraft's relative guidance for local models. " : "Not benchmarked in Airdraft. ") + entry.note)
            } cost: {
                storageLabel
            } accessory: {
                actions
            }
            if let progress {
                ModelDownloadProgress(progress: progress).padding(.leading, 56)
            }
            if let error = error ?? downloadError {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.orange).padding(.leading, 56)
            }
        }
        .padding(Theme.cardPadding)
        .background(selected ? Color.primary.opacity(0.06) : (hovering ? Color.primary.opacity(0.03) : .clear))
        .onHover { hovering = $0 }
        .help(entry.note)
        .onAppear { installed = LocalModels.isInstalled(entryConfig) }
        .onChange(of: progress != nil) { _, _ in installed = LocalModels.isInstalled(entryConfig) }
    }

    @ViewBuilder
    private var loadStateLabel: some View {
        if entry.isDownloadable, installed {
            switch container.engineStatus.state(for: entryConfig.engineID) {
            case .ready:
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("In memory").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .help(container.settings.idleUnloadMinutes == 0
                    ? "Loaded in RAM. Stays loaded until you unload it, switch models, or quit the app."
                    : "Loaded in RAM. Unloads after \(container.settings.idleUnloadMinutes) idle minutes, when you switch models, or when the app quits.")
            case .loading:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text("Load failed").font(.system(size: 11.5)).foregroundStyle(.orange).help(message)
            case .notLoaded:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var storageLabel: some View {
        switch entry.storage {
        case .download(let size):
            Text(size).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        case .builtIn:
            Text("Built in").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if progress != nil {
            Button { container.downloads.cancel(entryConfig) } label: {
                Image(systemName: "xmark.circle").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Cancel download")
            .accessibilityLabel("Cancel download of \(entry.title)")
        } else if !installed, entry.isDownloadable {
            Button { download() } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Download")
            .accessibilityLabel("Download \(entry.title)")
        } else if installed, LocalModels.folder(for: entryConfig) != nil {
            Button { confirmDelete = true } label: { Image(systemName: "trash").font(.system(size: 13)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(isSelectedForUse ? "Choose another model in Models or the active profile before deleting this one" : "Delete downloaded files")
            .accessibilityLabel("Delete \(entry.title)")
            .disabled(isSelectedForUse || container.pipeline.isBusy || container.engineStatus.state(for: entryConfig.engineID) == .loading)
            .confirmationDialog("Delete \(entry.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteFiles() }
            } message: {
                Text(storageMessage)
            }
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private var storageMessage: String {
        if case .download(let size) = entry.storage { return "Frees \(size). You can download it again later." }
        return "You can download it again later."
    }

    private func deleteFiles() {
        guard !isSelectedForUse, !container.pipeline.isBusy,
              container.engineStatus.state(for: entryConfig.engineID) != .loading else { return }
        do {
            try LocalModels.remove(entryConfig)
            error = nil
        } catch {
            self.error = "Could not delete the model files: \(error.localizedDescription)"
        }
        installed = LocalModels.isInstalled(entryConfig)
    }

    private func download() {
        let config = entryConfig
        let originalSelection = container.settings.asr
        let followedAppDefault = container.profiles.activeProfile.speechModel == nil
        error = nil
        container.downloads.start(config) {
            // Completing a background download must not override a newer choice.
            if followedAppDefault, container.profiles.activeProfile.speechModel == nil,
               container.settings.asr == originalSelection {
                entry.select(&container.settings.asr)
            }
            if container.speechConfig.engineID == config.engineID {
                container.models.loadSpeechModel()
            }
        }
    }
}
