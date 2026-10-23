import Foundation
import WhisperKit

/// Local Core ML Whisper via WhisperKit, loaded from the folders the Models
/// page downloads into. Never touches the Hugging Face Hub itself.
public actor WhisperKitTranscriber: Transcriber {
    public nonisolated let id: String
    private let variant: String
    private var pipe: WhisperKit?
    /// WhisperKit is not Sendable, so the shared load publishes into this actor
    /// instead of returning the instance across isolation domains.
    private var loading: Task<Void, Error>?

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
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(
            kind: .whisperKit, whisperModel: variant, language: hints.language ?? ""
        )).language
        var resolvedHints = hints
        resolvedHints.language = language
        let pipe = try await loadedPipe()
        let started = Date()

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.detectLanguage = language == nil
        options.temperature = 0
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        // Preserve timestamp seeking inside each bounded window.
        options.withoutTimestamps = false
        // The SDK's one-second clipping default skips sub-second speech entirely.
        options.windowClipTime = 0
        // Decode our bounded windows directly. WhisperKit's long-clip seeking
        // can lose later speech, and its VAD fan-out drops failed chunks.
        options.chunkingStrategy = nil
        if let prompt = resolvedHints.promptText, let tokenizer = pipe.tokenizer {
            // Whisper accepts roughly 224 prompt tokens; keep the tail.
            let tokens = tokenizer.encode(text: " " + prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = Array(tokens.suffix(200))
        }

        var detectedLanguage: String?
        let text = try await AudioChunker.transcribeAsync(samples, maxSeconds: 25) { chunk in
            let results = try await pipe.transcribe(audioArray: chunk, decodeOptions: options)
            if detectedLanguage == nil { detectedLanguage = results.first?.language }
            return results.map(\.text).joined(separator: " ")
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: detectedLanguage, engine: id, latencyMs: ms)
    }

    /// File jobs call this on bounded windows and checkpoint only complete windows.
    public func transcribeWords(samples: [Float], language: String?, offset: Double) async throws -> [TranscriptWord] {
        let pipe = try await loadedPipe()
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.detectLanguage = language == nil
        options.temperature = 0
        options.skipSpecialTokens = true
        options.withoutTimestamps = false
        options.wordTimestamps = true
        options.windowClipTime = 0
        options.chunkingStrategy = nil
        try Task.checkCancellation()
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        return results.flatMap { result in result.segments.flatMap { segment -> [TranscriptWord] in
            if let words = segment.words, !words.isEmpty {
                return words.map { TranscriptWord(start: offset + Double($0.start), end: offset + Double($0.end), text: $0.word) }
            }
            return [TranscriptWord(start: offset + Double(segment.start), end: offset + Double(segment.end), text: segment.text)]
        } }
    }

    /// Internal for the AD-082 output-guard hooks in WhisperKitTranscriber+Guards.swift.
    func loadedPipe() async throws -> WhisperKit {
        if let pipe { return pipe }
        let task: Task<Void, Error>
        if let loading { task = loading }
        else {
            guard LocalModels.isInstalled(ASRConfig(kind: .whisperKit, whisperModel: variant)) else { throw TranscriberError.modelNotDownloaded }
            // Unstructured: a waiter that stops waiting does not cancel the shared load.
            task = Task { try await self.load() }
            loading = task
        }
        do {
            try await task.value
        } catch {
            if loading == task { loading = nil }
            throw error
        }
        if loading == task { loading = nil }
        // unload() ran while this load finished: never publish late readiness.
        guard let pipe else { throw CancellationError() }
        return pipe
    }

    private func load() async throws {
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
        let loaded = try await WhisperKit(config)
        guard !Task.isCancelled else {
            await loaded.unloadModels()
            throw CancellationError()
        }
        pipe = loaded
    }
}
