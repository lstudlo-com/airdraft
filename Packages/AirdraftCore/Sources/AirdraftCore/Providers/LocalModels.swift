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
        case .fluidAudio: return hasCoreMLSpeech(config.model)
        case .orukeet: return hasSherpa(.orukeet)
        case .transcribeCpp: return hasGGUF(config.model)
        case .whisperKit: return hasWhisper(config.whisperModel) && hasWhisperTokenizer
        case .qwen3: return hasQwen3(config.qwen3Model)
        case .cohere: return hasCohere(config.cohereModel)
        case .fireRed: return hasSherpa(.fireRed)
        case .senseVoice: return hasSherpa(.senseVoice)
        case .parakeet: return hasSherpa(.parakeet)
        case .apple: return AppleSpeechTranscriber.isAvailable
        case .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini: return true
        }
    }

    /// Download folder of the model `config` selects; nil for engines with nothing to download.
    public static func folder(for config: ASRConfig) -> URL? {
        switch config.kind {
        case .fluidAudio: return coreMLSpeechFolder(for: config.model)
        case .orukeet: return sherpaFolder(for: .orukeet)
        case .transcribeCpp: return ggufFolder(for: config.model)
        case .whisperKit: return whisperFolder(for: config.whisperModel)
        case .qwen3: return qwen3Folder(for: config.qwen3Model)
        case .cohere: return cohereFolder(for: config.cohereModel)
        case .fireRed: return sherpaFolder(for: .fireRed)
        case .senseVoice: return sherpaFolder(for: .senseVoice)
        case .parakeet: return sherpaFolder(for: .parakeet)
        case .apple, .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini: return nil
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

    public static var root: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["AIRDRAFT_E2E_MODEL_ROOT"],
           path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return AppSettings.supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }
    public static var whisperKitRoot: URL { root.appendingPathComponent("whisperkit-coreml", isDirectory: true) }
    public static var whisperTokenizerFolder: URL { root.appendingPathComponent("tokenizer/whisper-large-v3", isDirectory: true) }

    public static func whisperFolder(for variant: String) -> URL {
        whisperKitRoot.appendingPathComponent(WhisperModelVariant(rawValue: variant)?.directoryName ?? "openai_whisper-\(variant)", isDirectory: true)
    }

    /// True when the Core ML bundles for this variant are present, including every
    /// file of its pinned revision.
    public static func hasWhisper(_ variant: String) -> Bool {
        hasWhisper(variant, at: whisperFolder(for: variant))
    }

    static func hasWhisper(_ variant: String, at folder: URL) -> Bool {
        let required = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc", "config.json"]
        guard required.allSatisfy({ FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }) else { return false }
        let artifact = WhisperModelVariant(rawValue: variant).flatMap(PinnedHubModelCatalog.whisper)
        return artifact.map { hasPinnedFiles($0, at: folder) } ?? true
    }

    /// AD-074: pinned files download one at a time in manifest order, so an
    /// interrupted download can leave the loader's key files in place while later
    /// ones (generation_config.json, tokenizer_config.json, weight shards) are
    /// missing. Each transfer moves a verified file into place, so a missing file,
    /// not a truncated one, is what an interruption leaves; require every manifest
    /// path as a nonempty regular file. Sizes are not compared, so installs from an
    /// earlier revision stay usable; downloading again replaces mismatched files.
    static func hasPinnedFiles(_ artifact: PinnedHubArtifact, at folder: URL) -> Bool {
        artifact.files.allSatisfy { file in
            let values = try? folder.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
        }
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

    public static func coreMLSpeechFolder(for modelID: String) -> URL? {
        guard CoreMLSpeechModelCatalog.model(modelID) != nil else { return nil }
        return root.appendingPathComponent("coreml-speech/\(modelID)", isDirectory: true)
    }
    static func hasCoreMLSpeech(_ modelID: String) -> Bool {
        guard let entry = CoreMLSpeechModelCatalog.model(modelID), let folder = coreMLSpeechFolder(for: modelID) else { return false }
        return entry.files.allSatisfy { file in
            let values = try? folder.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return values?.isRegularFile == true && Int64(values?.fileSize ?? 0) == file.bytes
        }
    }

    // MARK: GGUF (one verified artifact per catalogue choice)

    public static func ggufFolder(for modelID: String) -> URL? {
        guard GGUFModelCatalog.model(modelID) != nil else { return nil }
        return root.appendingPathComponent("gguf/\(modelID)", isDirectory: true)
    }
    public static func ggufFile(for modelID: String) -> URL? {
        guard let entry = GGUFModelCatalog.model(modelID) else { return nil }
        return ggufFolder(for: modelID)?.appendingPathComponent(entry.filename)
    }
    static func hasGGUF(_ modelID: String) -> Bool {
        guard let entry = GGUFModelCatalog.model(modelID), let file = ggufFile(for: modelID),
              let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) else { return false }
        return values.isRegularFile == true && Int64(values.fileSize ?? 0) == entry.bytes
    }

    // MARK: Qwen3-ASR (speech-swift layout: <root>/qwen3-asr/<org>/<model>)

    public static var qwen3Root: URL { root.appendingPathComponent("qwen3-asr", isDirectory: true) }

    public static func qwen3Folder(for modelId: String) -> URL {
        qwen3Root.appendingPathComponent(modelId, isDirectory: true)
    }

    /// Weights plus tokenizer present, and every file of a pinned choice.
    public static func hasQwen3(_ modelId: String) -> Bool {
        hasQwen3(modelId, at: qwen3Folder(for: modelId))
    }

    static func hasQwen3(_ modelId: String, at folder: URL) -> Bool {
        hasQwen3(at: folder) && (PinnedHubModelCatalog.qwen3(modelId).map { hasPinnedFiles($0, at: folder) } ?? true)
    }

    static func hasQwen3(at folder: URL) -> Bool {
        hasMLXFiles(at: folder, required: ["vocab.json", "merges.txt"])
    }

    // MARK: Cohere Transcribe (speech-swift layout)

    public static var cohereRoot: URL { root.appendingPathComponent("cohere-transcribe", isDirectory: true) }
    public static func cohereFolder(for modelId: String) -> URL { cohereRoot.appendingPathComponent(modelId, isDirectory: true) }
    public static func hasCohere(_ modelId: String) -> Bool {
        hasCohere(at: cohereFolder(for: modelId))
    }

    static func hasCohere(at folder: URL) -> Bool {
        hasMLXFiles(at: folder, required: ["config.json", "tokenizer.model", "tokenizer_config.json"])
    }

    private static func hasMLXFiles(at folder: URL, required: [String]) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        let weights = names.filter { $0.hasSuffix(".safetensors") }
        guard !weights.isEmpty else { return false }
        return (weights + required).allSatisfy { name in
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            return attributes?[.type] as? FileAttributeType == .typeRegular && (attributes?[.size] as? Int64 ?? 0) > 0
        }
    }

    // MARK: sherpa-onnx models (SenseVoice, FireRedASR2, Parakeet)

    public static var sherpaRoot: URL { root.appendingPathComponent("sherpa-onnx", isDirectory: true) }
    public static func sherpaFolder(for model: SherpaTranscriber.Model) -> URL {
        sherpaRoot.appendingPathComponent(model.folderName, isDirectory: true)
    }
    public static func hasSherpa(_ model: SherpaTranscriber.Model) -> Bool {
        hasSherpa(model, at: sherpaFolder(for: model))
    }

    /// Asset completeness only: the downloader checks this before removing its transaction marker.
    static func hasSherpa(_ model: SherpaTranscriber.Model, at folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        func isNonemptyFile(_ name: String) -> Bool {
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            return attributes?[.type] as? FileAttributeType == .typeRegular && (attributes?[.size] as? Int64 ?? 0) > 0
        }
        return isNonemptyFile("tokens.txt") && model.onnxPrefixes.allSatisfy { prefix in
            guard let name = model.onnxFilename(for: prefix, in: names) else { return false }
            return isNonemptyFile(name)
        }
    }
}
