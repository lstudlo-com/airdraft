import Foundation
import FluidAudio
import CoreML

/// Offline Core ML Parakeet and compatible post-trained weights.
public actor FluidAudioTranscriber: Transcriber {
    public nonisolated let id: String
    private let modelID: String
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private var generation = 0

    public init(modelID: String) {
        self.modelID = modelID
        id = "fluidaudio:\(modelID)"
    }
    public func isReady() async -> Bool { manager != nil }
    public func prepare() async throws { _ = try await loadedManager() }
    public func unload() async {
        // In-flight transcriptions retain their actor and models. Do not call
        // cleanup while it is decoding; ARC releases it after the last borrower.
        generation += 1
        loading?.cancel()
        loading = nil
        manager = nil
    }
    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        guard let entry = CoreMLSpeechModelCatalog.model(modelID) else { throw TranscriberError.modelNotDownloaded }
        var config = entry.config
        config.language = hints.language ?? ""
        _ = try SpeechLanguagePolicy.resolve(config)
        let manager = try await loadedManager()
        let started = Date()
        let text = try await AudioChunker.transcribeAsync(samples, maxSeconds: 15) { chunk in
            guard chunk.contains(where: { $0 != 0 }) else { return "" }
            var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            return try await manager.transcribe(chunk, decoderState: &state).text
        }
        return Transcript(text: text, language: entry.languages.count == 1 ? entry.languages[0] : nil,
                          engine: id, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }

    private func loadedManager() async throws -> AsrManager {
        try Task.checkCancellation()
        guard let entry = CoreMLSpeechModelCatalog.model(modelID), LocalModels.isInstalled(entry.config),
              let folder = LocalModels.coreMLSpeechFolder(for: modelID) else { throw TranscriberError.modelNotDownloaded }
        if let manager { return manager }
        let current = generation
        let task: Task<AsrManager, Error>
        if let loading { task = loading }
        else {
            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let version: AsrModelVersion
                switch entry.version {
                case "v2": version = .v2
                case "v3": version = .v3
                case "ultra": version = .ultra
                case "redux": version = .redux
                case "phonon2": version = .phonon2
                case "tdtCtc110m": version = .tdtCtc110m
                case "tdtJa": version = .tdtJa
                default: throw TranscriberError.modelNotDownloaded
                }
                // Redux's ternary encoder takes several minutes to compile on
                // ANE. Its upstream macOS GPU path loads the same weights
                // directly; other encoders retain their ANE-oriented defaults.
                let models = try AsrModels.loadLocal(from: folder, version: version,
                                                    encoderPrecision: entry.precision == "int4" ? .int4 : .int8,
                                                    encoderComputeUnits: version == .redux ? .cpuAndGPU : nil)
                try Task.checkCancellation()
                return AsrManager(models: models)
            }
            loading = task
        }
        do {
            let value = try await withTaskCancellationHandler {
                let loaded = try await task.value
                try Task.checkCancellation()
                return loaded
            } onCancel: { task.cancel() }
            guard current == generation else { throw CancellationError() }
            manager = value
            loading = nil
            return value
        } catch {
            if current == generation { loading = nil }
            throw error
        }
    }
}
