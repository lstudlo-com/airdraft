import Foundation
import Qwen3ASR

/// Qwen3-ASR via speech-swift (MLX). Best open model for Chinese, Chinese
/// dialects, and Chinese/English code-switching.
public actor Qwen3ASRTranscriber: Transcriber {
    public nonisolated let id: String
    private let modelId: String
    private var model: Qwen3ASRModel?
    private var loading: Task<Qwen3ASRModel, Error>?

    public init(modelId: String) {
        self.modelId = modelId
        self.id = "qwen3-asr:\(modelId)"
    }

    public func isReady() async -> Bool { model != nil }

    public func prepare() async throws {
        _ = try await loadedModel()
    }

    public func unload() async {
        loading?.cancel()
        loading = nil
        model = nil
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let model = try await loadedModel()
        let started = Date()
        var options = Qwen3DecodingOptions()
        options.language = hints.language
        options.context = hints.promptText
        // 448 tokens per chunk can cut fast or English-heavy speech mid-sentence.
        options.maxTokens = 1024
        let text = AudioChunker.transcribe(samples, maxSeconds: 25) {
            model.transcribe(audio: $0, sampleRate: 16_000, options: options)
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: hints.language, engine: id, latencyMs: ms)
    }

    private func loadedModel() async throws -> Qwen3ASRModel {
        if let model { return model }
        if loading == nil {
            let modelId = self.modelId
            guard LocalModels.hasQwen3(modelId) else { throw TranscriberError.modelNotDownloaded }
            loading = Task { try await Qwen3ASRModel.fromPretrained(modelId: modelId, cacheDir: LocalModels.qwen3Folder(for: modelId), offlineMode: true) }
        }
        do {
            let loaded = try await loading!.value
            model = loaded
            loading = nil
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }
}
