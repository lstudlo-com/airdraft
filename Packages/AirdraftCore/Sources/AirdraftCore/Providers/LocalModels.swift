import Foundation

/// Where the app keeps the speech models it downloads:
/// `~/Library/Application Support/Transcribar/Models/`. Local engines load only from here.
public enum LocalModels {
    /// True when the engine `config` selects can run now: its files are on disk,
    /// or it needs none (remote APIs, Apple Speech on macOS 26).
    public static func isInstalled(_ config: ASRConfig) -> Bool {
        if let folder = folder(for: config),
           FileManager.default.fileExists(atPath: folder.appendingPathComponent(incompleteMarker).path) { return false }
        return hasFiles(config)
    }

    static let incompleteMarker = ".airdraft-download-incomplete"

    static func hasFiles(_ config: ASRConfig) -> Bool {
        switch config.kind {
        case .whisperKit: return hasWhisper(config.whisperModel) && hasWhisperTokenizer
        case .qwen3: return hasQwen3(config.qwen3Model)
        case .cohere: return hasCohere(config.cohereModel)
        case .fireRed: return hasSherpa(.fireRed)
        case .senseVoice: return hasSherpa(.senseVoice)
        case .apple: return AppleSpeechTranscriber.isAvailable
        case .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox: return true
        }
    }

    /// Download folder of the model `config` selects; nil for engines with nothing to download.
    public static func folder(for config: ASRConfig) -> URL? {
        switch config.kind {
        case .whisperKit: return whisperFolder(for: config.whisperModel)
        case .qwen3: return qwen3Folder(for: config.qwen3Model)
        case .cohere: return cohereFolder(for: config.cohereModel)
        case .fireRed: return sherpaFolder(for: .fireRed)
        case .senseVoice: return sherpaFolder(for: .senseVoice)
        case .apple, .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox: return nil
        }
    }

    /// Deletes the downloaded files of the model `config` selects. Model ids come
    /// from saved settings, so the folder must resolve inside `root`.
    public static func remove(_ config: ASRConfig) throws {
        guard let folder = folder(for: config) else { return }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard folder.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(rootPath) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: folder.path])
        }
        try FileManager.default.removeItem(at: folder)
    }

    public static var root: URL { AppSettings.supportDirectory.appendingPathComponent("Models", isDirectory: true) }
    public static var whisperKitRoot: URL { root.appendingPathComponent("whisperkit-coreml", isDirectory: true) }
    public static var whisperTokenizerFolder: URL { root.appendingPathComponent("tokenizer/whisper-large-v3", isDirectory: true) }

    public static func whisperFolder(for variant: String) -> URL {
        whisperKitRoot.appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
    }

    /// True when the Core ML bundles for this variant are present.
    public static func hasWhisper(_ variant: String) -> Bool {
        let folder = whisperFolder(for: variant)
        let required = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        return required.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    public static var hasWhisperTokenizer: Bool {
        hasWhisperTokenizer(at: whisperTokenizerFolder)
    }

    static let whisperTokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "vocab.json", "merges.txt", "added_tokens.json", "normalizer.json", "config.json", "generation_config.json"]

    static func hasWhisperTokenizer(at folder: URL) -> Bool {
        whisperTokenizerFiles.allSatisfy { name in
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            return (attributes?[.size] as? Int64 ?? 0) > 0
        }
    }

    // MARK: Qwen3-ASR (speech-swift layout: <root>/qwen3-asr/<org>/<model>)

    public static var qwen3Root: URL { root.appendingPathComponent("qwen3-asr", isDirectory: true) }

    public static func qwen3Folder(for modelId: String) -> URL {
        qwen3Root.appendingPathComponent(modelId, isDirectory: true)
    }

    /// Weights plus tokenizer present.
    public static func hasQwen3(_ modelId: String) -> Bool {
        let folder = qwen3Folder(for: modelId)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        let hasWeights = names.contains { $0.hasSuffix(".safetensors") }
        return hasWeights && names.contains("vocab.json") && names.contains("merges.txt")
    }

    // MARK: Cohere Transcribe (speech-swift layout)

    public static var cohereRoot: URL { root.appendingPathComponent("cohere-transcribe", isDirectory: true) }
    public static func cohereFolder(for modelId: String) -> URL { cohereRoot.appendingPathComponent(modelId, isDirectory: true) }
    public static func hasCohere(_ modelId: String) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cohereFolder(for: modelId).path)) ?? []
        return names.contains { $0.hasSuffix(".safetensors") } && names.contains { $0.hasPrefix("tokenizer") }
    }

    // MARK: sherpa-onnx models (SenseVoice, FireRedASR2)

    public static var sherpaRoot: URL { root.appendingPathComponent("sherpa-onnx", isDirectory: true) }
    public static func sherpaFolder(for model: SherpaTranscriber.Model) -> URL {
        sherpaRoot.appendingPathComponent(model.folderName, isDirectory: true)
    }
    public static func hasSherpa(_ model: SherpaTranscriber.Model) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sherpaFolder(for: model).path)) ?? []
        return names.contains("tokens.txt") && model.onnxPrefixes.allSatisfy { prefix in
            names.contains { $0.hasPrefix(prefix) && $0.hasSuffix(".onnx") }
        }
    }
}
