import CohereTranscribeASR
import Foundation

/// Cohere Transcribe 2B via speech-swift (MLX). Best open English model on
/// the Open ASR Leaderboard; 14 languages including Chinese, Japanese, Korean.
public actor CohereTranscriber: Transcriber {
    public nonisolated let id: String
    private let modelId: String
    private var model: CohereTranscribeModel?
    private var loading: Task<CohereTranscribeModel, Error>?

    public init(modelId: String) {
        self.modelId = modelId
        self.id = "cohere-transcribe:\(modelId)"
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
        let text = AudioChunker.transcribe(samples, maxSeconds: 25) {
            model.transcribe(audio: $0, sampleRate: 16_000, language: hints.language)
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: hints.language, engine: id, latencyMs: ms)
    }

    private func loadedModel() async throws -> CohereTranscribeModel {
        if let model { return model }
        if loading == nil {
            let modelId = self.modelId
            guard LocalModels.hasCohere(modelId) else { throw TranscriberError.modelNotDownloaded }
            loading = Task { try await CohereTranscribeModel.fromPretrained(modelId, cacheDir: LocalModels.cohereFolder(for: modelId), offlineMode: true) }
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
