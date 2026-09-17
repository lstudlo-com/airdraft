import Foundation
import WhisperKit

/// Local Core ML Whisper via WhisperKit, loaded from the folders the Models
/// page downloads into. Never touches the Hugging Face Hub itself.
public actor WhisperKitTranscriber: Transcriber {
    public nonisolated let id: String
    private let variant: String
    private var pipe: WhisperKit?
    private var loading: Task<WhisperKit, Error>?

    /// - Parameter variant: WhisperKit variant name, e.g. `large-v3-v20240930_turbo`.
    public init(variant: String) {
        self.variant = variant
        self.id = "whisperkit:\(variant)"
    }

    public func isReady() async -> Bool { pipe != nil }

    public func prepare() async throws {
        _ = try await loadedPipe()
    }

    public func unload() async {
        loading?.cancel()
        loading = nil
        if let pipe { await pipe.unloadModels() }
        pipe = nil
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let pipe = try await loadedPipe()
        let started = Date()

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = hints.language
        options.detectLanguage = hints.language == nil
        options.temperature = 0
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        // Timestamps must stay on: Whisper uses them to seek past the first
        // 30 s window. Without them long recordings silently stop at ~30 s.
        options.withoutTimestamps = false
        options.chunkingStrategy = .vad
        options.concurrentWorkerCount = 4
        if let prompt = hints.promptText, let tokenizer = pipe.tokenizer {
            // Whisper accepts roughly 224 prompt tokens; keep the tail.
            let tokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = Array(tokens.suffix(200))
        }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: results.first?.language, engine: id, latencyMs: ms)
    }

    private func loadedPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        if loading == nil {
            guard LocalModels.hasWhisper(variant), LocalModels.hasWhisperTokenizer else { throw TranscriberError.modelNotDownloaded }
            let config = WhisperKitConfig(
                model: variant,
                modelFolder: LocalModels.whisperFolder(for: variant).path,
                tokenizerFolder: LocalModels.whisperTokenizerFolder,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            loading = Task { try await WhisperKit(config) }
        }
        do {
            let loaded = try await loading!.value
            pipe = loaded
            loading = nil
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }
}
