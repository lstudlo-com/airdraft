import Foundation
import SherpaOnnxC

/// Offline recognizers served by sherpa-onnx (ONNX Runtime on CPU).
/// Models load from `LocalModels.sherpaFolder`; installation is explicit.
public actor SherpaTranscriber: Transcriber {
    public enum Model: String, Sendable, CaseIterable {
        case senseVoice
        case fireRed
        case parakeet

        /// Folder name under LocalModels.sherpaRoot and the release archive to fetch.
        public var folderName: String {
            switch self {
            case .senseVoice: return "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
            case .fireRed: return "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
            case .parakeet: return "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
            }
        }

        public var archiveURL: URL {
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(folderName).tar.bz2")!
        }

        public var sizeLabel: String {
            switch self {
            case .senseVoice: return "166 MB"
            case .fireRed: return "840 MB"
            case .parakeet: return "487 MB"
            }
        }

        /// Published release-asset digests, verified against the supported archive bytes.
        var archiveSHA256: String? {
            switch self {
            case .senseVoice: return "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63"
            case .fireRed: return "43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c"
            case .parakeet: return "5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf"
            }
        }

        /// ONNX files the model needs, matched by prefix inside its folder.
        var onnxPrefixes: [String] {
            switch self {
            case .senseVoice: return ["model"]
            case .fireRed: return ["encoder", "decoder"]
            case .parakeet: return ["encoder", "decoder", "joiner"]
            }
        }

        func onnxFilename(for prefix: String, in names: [String]) -> String? {
            if self == .parakeet {
                let filename = "\(prefix).int8.onnx"
                return names.contains(filename) ? filename : nil
            }
            return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".onnx") }.sorted().first
        }
    }

    /// Owns the C recognizer so it is destroyed exactly once.
    private final class Recognizer {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { SherpaOnnxDestroyOfflineRecognizer(pointer) }
    }

    public nonisolated let id: String
    private let model: Model
    private let modelDirectory: URL
    private var recognizer: Recognizer?
    private var recognizerConfiguration: RecognizerConfiguration?

    public init(model: Model) {
        self.model = model
        self.modelDirectory = LocalModels.sherpaFolder(for: model)
        self.id = "sherpa-onnx:\(model.rawValue)"
    }

    /// Isolated test fixture only. App and CLI use the public LocalModels initializer.
    init(model: Model, modelDirectory: URL) {
        self.model = model
        self.modelDirectory = modelDirectory
        self.id = "sherpa-onnx:\(model.rawValue)"
    }

    public func isReady() async -> Bool { recognizer != nil }

    public func prepare() async throws {
        try Task.checkCancellation()
        // A factory prepare precedes each transcription. Keep a warm recognizer's
        // language here; the next transcription resolves its own current hint.
        let configuration = try recognizerConfiguration ?? RecognizerConfiguration(model: model)
        _ = try loadedRecognizer(configuration: configuration)
    }

    public func unload() async {
        recognizer = nil
        recognizerConfiguration = nil
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        // Validate before inspecting files or entering the native runtime, including
        // callers that use this adapter without the pipeline's preflight.
        let configuration = try RecognizerConfiguration(model: model, hints: hints)
        let recognizer = try loadedRecognizer(configuration: configuration)
        let started = Date()
        // These are offline (whole-utterance) decoders; long recordings
        // are split at silences so memory and latency stay bounded.
        let text = try AudioChunker.transcribe(samples, maxSeconds: 30) { Self.decode($0, with: recognizer.pointer) }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        // Joint-language decoders return no detected language through this API.
        // Do not report an ignored language hint as recognition metadata.
        return Transcript(text: text, language: configuration.language, engine: id, latencyMs: ms)
    }

    private static func decode(_ samples: [Float], with recognizer: OpaquePointer) -> String {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        SherpaOnnxAcceptWaveformOffline(stream, 16_000, samples, Int32(samples.count))
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        return result.pointee.text.map { String(cString: $0) } ?? ""
    }

    private func loadedRecognizer(configuration: RecognizerConfiguration) throws -> Recognizer {
        let folder = modelDirectory
        guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent(LocalModels.incompleteMarker).path),
              LocalModels.hasSherpa(model, at: folder) else { throw TranscriberError.modelNotDownloaded }
        if let recognizer, recognizerConfiguration == configuration { return recognizer }
        // SenseVoice fixes its language when the recognizer is constructed.
        // Release the old model before rebuilding so a language change cannot
        // retain the old decoder or temporarily double its memory use.
        recognizer = nil
        recognizerConfiguration = nil
        try Task.checkCancellation()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let pointer = configuration.withCConfiguration(folder: folder, files: files) {
            SherpaOnnxCreateOfflineRecognizer(&$0)
        }
        guard let pointer else { throw TranscriberError.modelNotDownloaded }
        let created = Recognizer(pointer)
        recognizer = created
        recognizerConfiguration = configuration
        return created
    }

    /// The same value owns native configuration and cache identity. Tests inspect
    /// the C fields synchronously without loading model weights or the runtime.
    struct RecognizerConfiguration: Equatable {
        let model: Model
        let language: String?

        init(model: Model, hints: TranscriptionHints = .init()) throws {
            self.model = model
            let kind: ASRProviderKind
            switch model {
            case .senseVoice: kind = .senseVoice
            case .fireRed: kind = .fireRed
            case .parakeet: kind = .parakeet
            }
            let config = ASRConfig(kind: kind, language: hints.language ?? "")
            language = try SpeechLanguagePolicy.resolve(config).language
        }

        func withCConfiguration<Value>(folder: URL, files: [String],
                                       _ body: (inout SherpaOnnxOfflineRecognizerConfig) throws -> Value) rethrows -> Value {
            func onnx(_ prefix: String) -> String {
                model.onnxFilename(for: prefix, in: files).map { folder.appendingPathComponent($0).path } ?? ""
            }
            // sherpa-onnx copies these strings while creating the recognizer.
            // They remain valid only during this synchronous call.
            var cStrings: [UnsafeMutablePointer<CChar>] = []
            defer { cStrings.forEach { free($0) } }
            func c(_ s: String) -> UnsafePointer<CChar> {
                let p = strdup(s)!
                cStrings.append(p)
                return UnsafePointer(p)
            }

            var config = SherpaOnnxOfflineRecognizerConfig()
            config.feat_config.sample_rate = 16_000
            config.feat_config.feature_dim = 80
            config.model_config.tokens = c(folder.appendingPathComponent("tokens.txt").path)
            config.model_config.num_threads = 4
            config.model_config.provider = c("cpu")
            switch model {
            case .senseVoice:
                config.model_config.model_type = c("sense_voice")
                config.model_config.sense_voice.model = c(onnx("model"))
                config.model_config.sense_voice.language = c(language ?? "auto")
                config.model_config.sense_voice.use_itn = 1
            case .fireRed:
                config.model_config.model_type = c("fire_red_asr")
                config.model_config.fire_red_asr.encoder = c(onnx("encoder"))
                config.model_config.fire_red_asr.decoder = c(onnx("decoder"))
            case .parakeet:
                config.model_config.model_type = c("nemo_transducer")
                config.model_config.transducer.encoder = c(onnx("encoder"))
                config.model_config.transducer.decoder = c(onnx("decoder"))
                config.model_config.transducer.joiner = c(onnx("joiner"))
                config.decoding_method = c("greedy_search")
            }
            return try body(&config)
        }
    }
}
