import Foundation
import Qwen3ASR

/// Qwen3-ASR via speech-swift (MLX). Best open model for Chinese, Chinese
/// dialects, and Chinese/English code-switching.
public actor Qwen3ASRTranscriber: Transcriber {
    public nonisolated let id: String
    private let modelId: String
    private var model: Qwen3ASRModel?
    /// Qwen3ASRModel is not Sendable, so the shared load publishes into this actor
    /// instead of returning the instance across isolation domains.
    private var loading: Task<Void, Error>?

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
        let resolved = try SpeechLanguagePolicy.resolve(ASRConfig(
            kind: .qwen3, qwen3Model: modelId, language: hints.language ?? ""
        ))
        let language = resolved.language
        var resolvedHints = hints
        resolvedHints.language = language
        let options = try Self.decodingOptions(for: resolvedHints,
            allowUnverifiedLanguage: resolved.capabilities.manualControl == .unknown)
        let terms = resolvedHints.onDeviceVocabulary
        var plainHints = resolvedHints
        plainHints.biasOnDeviceSpeech = false
        let fallback = plainHints.contextText
        let model = try await loadedModel()
        let started = Date()
        let text = try AudioChunker.transcribe(samples, maxSeconds: 25) { chunk in
            // AD-082: a decoder loop stops at a duration-scaled cap, not 1,024 tokens.
            var chunkOptions = options
            chunkOptions.maxTokens = LocalASRDecodeBudget.qwenMaxTokens(sampleCount: chunk.count)
            return Self.decodeGuardingVocabulary(chunk, options: chunkOptions, fallbackContext: fallback, terms: terms) {
                model.transcribe(audio: $0, sampleRate: 16_000, options: $1)
            }
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: language, engine: id, latencyMs: ms)
    }

    /// The pinned Swift runtime inserts this value into `language {name}`.
    /// Qwen's inference contract uses full language names, not ISO codes:
    /// https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/utils.py
    static func decodingOptions(for hints: TranscriptionHints, allowUnverifiedLanguage: Bool = false) throws -> Qwen3DecodingOptions {
        let names = [
            "zh": "Chinese", "en": "English", "yue": "Cantonese", "ar": "Arabic",
            "de": "German", "fr": "French", "es": "Spanish", "pt": "Portuguese",
            "id": "Indonesian", "it": "Italian", "ko": "Korean", "ru": "Russian",
            "th": "Thai", "vi": "Vietnamese", "ja": "Japanese", "tr": "Turkish",
            "hi": "Hindi", "ms": "Malay", "nl": "Dutch", "sv": "Swedish",
            "da": "Danish", "fi": "Finnish", "pl": "Polish", "cs": "Czech",
            "fil": "Filipino", "fa": "Persian", "el": "Greek", "hu": "Hungarian",
            "mk": "Macedonian", "ro": "Romanian"
        ]
        var options = Qwen3DecodingOptions()
        if let language = try SpeechLanguagePolicy.canonicalLanguage(hints.language ?? "") {
            let unverifiedName = allowUnverifiedLanguage ? Locale(identifier: "en").localizedString(forLanguageCode: language)?.capitalized : nil
            guard let name = names[language == "tl" ? "fil" : language] ?? unverifiedName else {
                throw RecordingPrerequisiteError(String(localized: "Qwen3-ASR does not support \(SpeechLanguagePolicy.languageName(language)). Choose a supported language in Models.", bundle: .module))
            }
            options.language = name
        }
        options.context = hints.contextText
        // Upper bound only; transcribe() lowers it per chunk with the chunk's duration.
        options.maxTokens = LocalASRDecodeBudget.qwenTokenCeiling
        return options
    }

    /// AD-081: the vocabulary is decoder context, which Qwen can return as the
    /// transcript when a chunk holds no speech. Near-silent chunks decode
    /// without it, and an output that only lists vocabulary terms is decoded
    /// once more without it. `fallbackContext` keeps the script sentence.
    static func decodeGuardingVocabulary(_ chunk: [Float], options: Qwen3DecodingOptions, fallbackContext: String?,
                                         terms: [String], decode: ([Float], Qwen3DecodingOptions) -> String) -> String {
        guard !terms.isEmpty else { return decode(chunk, options) }
        var plain = options
        plain.context = fallbackContext
        if SpeechVocabulary.isNearSilent(chunk) { return decode(chunk, plain) }
        let text = decode(chunk, options)
        return SpeechVocabulary.echoesTerms(text, terms: terms) ? decode(chunk, plain) : text
    }

    private func loadedModel() async throws -> Qwen3ASRModel {
        if let model { return model }
        let task: Task<Void, Error>
        if let loading { task = loading }
        else {
            guard LocalModels.hasQwen3(modelId) else { throw TranscriberError.modelNotDownloaded }
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
        guard let model else { throw CancellationError() }
        return model
    }

    private func load() async throws {
        let loaded = try await Qwen3ASRModel.fromPretrained(modelId: modelId, cacheDir: LocalModels.qwen3Folder(for: modelId), offlineMode: true)
        try Task.checkCancellation()
        model = loaded
    }
}
