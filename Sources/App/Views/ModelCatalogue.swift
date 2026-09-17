import AirdraftCore
import SwiftUI

/// One row of the models table: local engines and remote providers share it.
/// Everything else (installed, loaded, download, delete) derives from `select`.
struct ModelEntry: Identifiable {
    enum Storage { case download(sizeLabel: String), builtIn, cloud }
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
        // Remote rows stay selected when the user picks another model on the same endpoint.
        if current.kind == .openAICompatible { return URL(string: mine.baseURL)?.host == URL(string: current.baseURL)?.host }
        return mine.engineID == current.engineID
    }

    var isDownloadable: Bool { if case .download = storage { return true } else { return false } }
    var isCloud: Bool { if case .cloud = storage { return true } else { return false } }
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
        ModelEntry(
            id: "openai", title: "gpt-4o-transcribe", vendor: "OpenAI · API", color: .green, symbol: "cloud",
            tags: ["EN", "ZH"], speed: 3, accuracy: 4, storage: .cloud,
            note: "Cloud accuracy ceiling for English and clean Chinese."
        ) { apply(EndpointPreset.asr[0], to: &$0) },
        ModelEntry(
            id: "groq", title: "Whisper v3 Turbo", vendor: "Groq · API", color: .orange, symbol: "cloud",
            tags: ["99 languages"], speed: 4, accuracy: 3, storage: .cloud,
            note: "Cheapest, fastest cloud fallback."
        ) { apply(EndpointPreset.asr[1], to: &$0) },
        ModelEntry(
            id: "elevenlabs", title: "Scribe v2", vendor: "ElevenLabs · API", color: .indigo, symbol: "cloud",
            tags: ["90 languages"], speed: 3, accuracy: 5, storage: .cloud,
            note: "Strongest commercial multilingual model."
        ) { $0.kind = .elevenLabs; $0.elevenLabsModel = "scribe_v2" },
    ]

    private static func apply(_ preset: EndpointPreset, to config: inout ASRConfig) {
        config.kind = .openAICompatible
        config.baseURL = preset.baseURL
        config.model = preset.defaultModel
        config.apiKeyRef = preset.keyRef
    }
}

struct ModelRow: View {
    @Environment(AppContainer.self) private var container
    let entry: ModelEntry
    @State private var progress: ModelDownloader.Progress?
    @State private var error: String?
    @State private var installed = false
    @State private var hovering = false

    private var entryConfig: ASRConfig { entry.config(from: container.settings.asr) }

    var body: some View {
        @Bindable var settings = container.settings
        let selected = entry.isSelected(settings.asr)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        guard installed else { return }
                        entry.select(&settings.asr)
                    } label: {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(installed ? 0.6 : 0.3))
                    }
                    .buttonStyle(.plain)
                    .help(installed ? "Use this model" : "Download first")
                    IconBadge(symbol: entry.symbol, color: entry.color, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(entry.title).font(.system(size: 14, weight: .medium))
                            ForEach(entry.tags, id: \.self) { PillTag(text: $0) }
                        }
                        Text(entry.vendor).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 300, alignment: .leading)
                SegmentMeter(value: entry.speed).frame(width: 70, alignment: .leading)
                SegmentMeter(value: entry.accuracy).frame(width: 70, alignment: .leading)
                storageLabel.frame(width: 84, alignment: .leading)
                loadStateLabel
                Spacer()
                actions
            }
            if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress.fraction).frame(width: 220)
                    Text("\(Int(progress.fraction * 100))% \(progress.currentFile)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, 56)
            }
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.orange).padding(.leading, 56)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
        .help(entry.note)
        .onAppear { installed = LocalModels.isInstalled(entryConfig) }
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
        case .cloud:
            Image(systemName: "cloud").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if progress != nil {
            ProgressView().controlSize(.small)
        } else if !installed, entry.isDownloadable {
            Button { Task { await download() } } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Download")
        } else if installed, let folder = LocalModels.folder(for: entryConfig) {
            Button {
                try? FileManager.default.removeItem(at: folder)
                installed = LocalModels.isInstalled(entryConfig)
            } label: { Image(systemName: "trash").font(.system(size: 13)) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0.35)
            .help("Delete downloaded files")
            .disabled(entry.isSelected(container.settings.asr))
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private func download() async {
        let config = entryConfig
        error = nil
        progress = ModelDownloader.Progress(fraction: 0, currentFile: "")
        do {
            try await ModelDownloader.shared.download(config) { p in Task { @MainActor in progress = p } }
            installed = LocalModels.isInstalled(config)
            entry.select(&container.settings.asr)
            container.models.loadSpeechModel()
        } catch {
            self.error = error.localizedDescription
        }
        progress = nil
    }
}
