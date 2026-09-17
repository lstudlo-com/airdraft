import Foundation
import SherpaOnnxC

/// Offline recognizers served by sherpa-onnx (ONNX Runtime on CPU). Two models
/// use it: SenseVoice-small (fastest, zh/yue/en/ja/ko) and FireRedASR2-AED
/// (best Mandarin). Models live in `LocalModels.sherpaFolder`.
public actor SherpaTranscriber: Transcriber {
    public enum Model: String, Sendable, CaseIterable {
        case senseVoice
        case fireRed

        /// Folder name under LocalModels.sherpaRoot and the release archive to fetch.
        public var folderName: String {
            switch self {
            case .senseVoice: return "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
            case .fireRed: return "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
            }
        }

        public var archiveURL: URL {
            URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(folderName).tar.bz2")!
        }

        public var sizeLabel: String {
            switch self {
            case .senseVoice: return "166 MB"
            case .fireRed: return "840 MB"
            }
        }

        /// ONNX files the model needs, matched by prefix inside its folder.
        var onnxPrefixes: [String] {
            switch self {
            case .senseVoice: return ["model"]
            case .fireRed: return ["encoder", "decoder"]
            }
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
    private var recognizer: Recognizer?

    public init(model: Model) {
        self.model = model
        self.id = "sherpa-onnx:\(model.rawValue)"
    }

    public func isReady() async -> Bool { recognizer != nil }

    public func prepare() async throws {
        _ = try loadedRecognizer()
    }

    public func unload() async {
        recognizer = nil
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let recognizer = try loadedRecognizer()
        let started = Date()
        // Both models are offline (whole-utterance) decoders; long recordings
        // are split at silences so memory and latency stay bounded.
        let text = AudioChunker.transcribe(samples, maxSeconds: 30) { Self.decode($0, with: recognizer.pointer) }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Transcript(text: text, language: hints.language, engine: id, latencyMs: ms)
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

    private func loadedRecognizer() throws -> Recognizer {
        if let recognizer { return recognizer }
        guard LocalModels.hasSherpa(model) else { throw TranscriberError.modelNotDownloaded }
        let folder = LocalModels.sherpaFolder(for: model)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        func onnx(_ prefix: String) -> String {
            files.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".onnx") }.sorted().first.map { folder.appendingPathComponent($0).path } ?? ""
        }

        // The C API copies every string while creating the recognizer, so the
        // strdup'd paths only need to outlive that call. Zeroed fields take
        // sherpa-onnx's defaults (greedy search, cjkchar units, no LM).
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
            config.model_config.sense_voice.language = c("auto")
            config.model_config.sense_voice.use_itn = 1
        case .fireRed:
            config.model_config.model_type = c("fire_red_asr")
            config.model_config.fire_red_asr.encoder = c(onnx("encoder"))
            config.model_config.fire_red_asr.decoder = c(onnx("decoder"))
        }
        guard let pointer = SherpaOnnxCreateOfflineRecognizer(&config) else { throw TranscriberError.modelNotDownloaded }
        let created = Recognizer(pointer)
        recognizer = created
        return created
    }
}
