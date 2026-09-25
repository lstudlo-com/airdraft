import AirdraftCore
import SwiftUI

/// One downloadable or built-in speech model.
/// Everything else (installed, loaded, download, delete) derives from `select`.
struct ModelEntry: Identifiable {
    enum Storage { case download(sizeLabel: String), builtIn }
    let id: String
    let title: String
    let vendor: String
    let color: Color
    let symbol: String
    let tags: [String]
    let speed: Int      // 0...5
    let accuracy: Int   // 0...5
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
            id: "qwen3:1.7b", title: "Qwen3-ASR 1.7B", vendor: "Alibaba · MLX", color: .purple, symbol: "waveform",
            tags: ["ZH", "EN", "+28"], speed: 4, accuracy: 5, storage: .download(sizeLabel: "2.3 GB"),
            note: "Best for mixed Chinese and English."
        ) { $0.kind = .qwen3; $0.qwen3Model = "aufklarer/Qwen3-ASR-1.7B-MLX-5bit" },
        ModelEntry(
            id: "qwen3:0.6b", title: "Qwen3-ASR 0.6B", vendor: "Alibaba · MLX", color: .purple, symbol: "waveform",
            tags: ["ZH", "EN", "+28"], speed: 5, accuracy: 3, storage: .download(sizeLabel: "680 MB"),
            note: "Low memory, very fast."
        ) { $0.kind = .qwen3; $0.qwen3Model = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" },
        ModelEntry(
            id: "sherpa:fireRed", title: "FireRedASR2", vendor: "FireRed · ONNX", color: .red, symbol: "waveform",
            tags: ["ZH", "EN"], speed: 3, accuracy: 5, storage: .download(sizeLabel: SherpaTranscriber.Model.fireRed.sizeLabel),
            note: "Best Mandarin accuracy, 20+ dialects."
        ) { $0.kind = .fireRed },
        ModelEntry(
            id: "cohere", title: "Cohere Transcribe", vendor: "Cohere · MLX", color: .green, symbol: "waveform",
            tags: ["EN", "ZH", "+12"], speed: 4, accuracy: 5, storage: .download(sizeLabel: "1.6 GB"),
            note: "Best open English model."
        ) { $0.kind = .cohere; $0.cohereModel = "aufklarer/Cohere-Transcribe-2B-MLX-5bit" },
        ModelEntry(
            id: "sherpa:senseVoice", title: "SenseVoice", vendor: "FunAudioLLM · ONNX", color: .teal, symbol: "waveform",
            tags: ["ZH", "YUE", "EN", "JA", "KO"], speed: 5, accuracy: 3, storage: .download(sizeLabel: SherpaTranscriber.Model.senseVoice.sizeLabel),
            note: "Fastest."
        ) { $0.kind = .senseVoice },
        ModelEntry(
            id: "whisper:turbo", title: "Whisper v3 Turbo", vendor: "OpenAI · Core ML", color: .gray, symbol: "waveform",
            tags: ["99 languages"], speed: 3, accuracy: 3, storage: .download(sizeLabel: "1.5 GB"),
            note: "Runs on the Neural Engine."
        ) { $0.kind = .whisperKit; $0.whisperModel = "large-v3-v20240930_turbo" },
        ModelEntry(
            id: "apple", title: "Apple Speech", vendor: "macOS 26 · Neural Engine", color: .gray, symbol: "apple.logo",
            tags: ["ZH-TW", "EN"], speed: 5, accuracy: 3, storage: .builtIn,
            note: "Built in, no download."
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
        HStack(alignment: .center, spacing: 12) {
            identity.frame(maxWidth: .infinity, alignment: .leading)
            speed.frame(width: 72, alignment: .leading)
            accuracy.frame(width: 72, alignment: .leading)
            cost.frame(width: 88, alignment: .leading)
            accessory.frame(width: 20)
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
                HStack(spacing: 10) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.title).font(.system(size: 14, weight: .medium))
                        Text(model.quality).font(.system(size: 11.5)).foregroundStyle(.secondary)
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
        .accessibilityLabel("\(model.title), \(model.quality), speed: \(model.speed), \(model.price)")
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

    var body: some View {
        @Bindable var settings = container.settings
        let selected = entry.isSelected(settings.asr)
        VStack(alignment: .leading, spacing: 6) {
            ModelComparisonColumns {
                Button {
                    guard installed else { return }
                    entry.select(&settings.asr)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(installed ? 0.6 : 0.3))
                        IconBadge(symbol: entry.symbol, color: entry.color, size: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.system(size: 14, weight: .medium))
                            Text(entry.vendor).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                ForEach(entry.tags, id: \.self) { PillTag(text: $0) }
                            }
                            loadStateLabel
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(entry.title)")
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .help(installed ? "Use this model" : "Download first")
            } speed: {
                ModelMetric(title: "Speed", fraction: Double(entry.speed) / 5, label: "\(entry.speed) / 5",
                            detail: "Airdraft's relative guidance for local models. Actual speed depends on your Mac.")
            } accuracy: {
                ModelMetric(title: "Accuracy", fraction: Double(entry.accuracy) / 5, label: "\(entry.accuracy) / 5",
                            detail: "Airdraft's relative guidance for local models. " + entry.note)
            } cost: {
                storageLabel
            } accessory: {
                actions
            }
            if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress.fraction).frame(width: 220)
                    Text("\(Int(progress.fraction * 100))% \(progress.currentFile)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, 56)
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
        .onChange(of: container.downloads.jobs[entryConfig.engineID]) { _, _ in installed = LocalModels.isInstalled(entryConfig) }
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
                .help("Loaded in RAM. Unloads after \(container.settings.idleUnloadMinutes) idle minutes, when you switch models, or when the app quits.")
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
            Text(installed ? size : "—").font(.system(size: 12.5)).foregroundStyle(.secondary).monospacedDigit()
        case .builtIn:
            Text("built in").font(.system(size: 12.5)).foregroundStyle(.secondary)
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
            .help(entry.isSelected(container.settings.asr) ? "Choose another model before deleting this one" : "Delete downloaded files")
            .accessibilityLabel("Delete \(entry.title)")
            .disabled(entry.isSelected(container.settings.asr) || container.pipeline.isBusy || container.engineStatus.state(for: entryConfig.engineID) == .loading)
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
        error = nil
        container.downloads.start(config) {
            // Completing a background download must not override a newer choice.
            if container.settings.asr == originalSelection {
                entry.select(&container.settings.asr)
                container.models.loadSpeechModel()
            }
        }
    }
}
