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
        let resolved = try SpeechLanguagePolicy.resolve(ASRConfig(
            kind: .qwen3, qwen3Model: modelId, language: hints.language ?? ""
        ))
        let language = resolved.language
        var resolvedHints = hints
        resolvedHints.language = language
        let options = try Self.decodingOptions(for: resolvedHints,
            allowUnverifiedLanguage: resolved.capabilities.manualControl == .unknown)
        let model = try await loadedModel()
        let started = Date()
        let text = try AudioChunker.transcribe(samples, maxSeconds: 25) {
            model.transcribe(audio: $0, sampleRate: 16_000, options: options)
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
                throw RecordingPrerequisiteError("Qwen3-ASR does not support \(SpeechLanguagePolicy.languageName(language)). Choose a supported language in Models.")
            }
            options.language = name
        }
        options.context = hints.contextText
        // 448 tokens per chunk can cut fast or English-heavy speech mid-sentence.
        options.maxTokens = 1024
        return options
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
