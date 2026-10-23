import Foundation
import os
import SherpaOnnxC
import Synchronization

/// Offline recognizers served by sherpa-onnx (ONNX Runtime on CPU).
/// Models load from `LocalModels.sherpaFolder`; installation is explicit.
public actor SherpaTranscriber: Transcriber {
    public enum Model: String, Sendable, CaseIterable {
        /// The 2025-09-09 sherpa-onnx archive, converted from ASLP-lab WSYue-ASR
        /// `sensevoice_small_yue`, a Cantonese fine-tune (shown as "SenseVoice
        /// Cantonese"). Through 0.11.0 it was the only SenseVoice, so its ID keeps
        /// existing selections, profile bindings and history engine IDs exact.
        case senseVoice
        /// The original multilingual SenseVoiceSmall (FunAudioLLM, sherpa-onnx int8
        /// 2024-07-17), shown as "SenseVoice" (AD-083 follow-up).
        case senseVoiceMultilingual
        case fireRed
        case parakeet
        case orukeet

        /// Both SenseVoice artifacts share the decoder, language tokens and text normalization.
        public var isSenseVoice: Bool { self == .senseVoice || self == .senseVoiceMultilingual }

        /// Folder name under LocalModels.sherpaRoot and the release archive to fetch.
        public var folderName: String {
            switch self {
            case .senseVoice: return "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
            case .senseVoiceMultilingual: return "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
            case .fireRed: return "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
            case .orukeet: return "sherpa-onnx-orukeet-v0.1.0-int8"
            case .parakeet: return "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
            }
        }

        public var archiveURL: URL {
            if self == .orukeet {
                return URL(string: "https://huggingface.co/oruk/orukeet/resolve/55a984d46f68323301837194ce647c702f55facc/onnx/\(folderName).tar.bz2")!
            }
            return URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(folderName).tar.bz2")!
        }

        public var sizeLabel: String {
            switch self {
            case .senseVoice: return "166 MB"
            case .senseVoiceMultilingual: return "163 MB"
            case .fireRed: return "840 MB"
            case .parakeet, .orukeet: return "487 MB"
            }
        }

        /// Exact archive bytes (GitHub release asset size, or the Hub's linked size
        /// for Orukeet), checked before the digest so a truncated or different
        /// download fails with a clear size mismatch.
        var archiveBytes: Int64 {
            switch self {
            case .senseVoice: return 165_783_878
            case .senseVoiceMultilingual: return 163_002_883
            case .fireRed: return 838_589_068
            case .parakeet: return 487_170_055
            case .orukeet: return 486_807_585
            }
        }

        /// Published release-asset digests, verified against the supported archive bytes.
        var archiveSHA256: String? {
            switch self {
            case .senseVoice: return "7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63"
            case .senseVoiceMultilingual: return "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"
            case .fireRed: return "43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c"
            case .orukeet: return "f9191f30178cc9122ce2f023bf9fefafc822028307b0efa4caff645ba3fe8d0a"
            case .parakeet: return "5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf"
            }
        }

        /// ONNX files the model needs, matched by prefix inside its folder.
        var onnxPrefixes: [String] {
            switch self {
            case .senseVoice, .senseVoiceMultilingual: return ["model"]
            case .fireRed: return ["encoder", "decoder"]
            case .parakeet, .orukeet: return ["encoder", "decoder", "joiner"]
            }
        }

        /// NeMo transducers accept per-stream hotwords through sherpa-onnx's
        /// modified beam search (context graph). SenseVoice (CTC) and
        /// FireRedASR2 (AED) have no biasing input in the offline C API.
        public var supportsHotwords: Bool { self == .parakeet || self == .orukeet }

        func onnxFilename(for prefix: String, in names: [String]) -> String? {
            if self == .parakeet || self == .orukeet {
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

    static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "sherpa")
    public nonisolated let id: String
    private let model: Model
    private let modelDirectory: URL
    private var recognizer: Recognizer?
    private var recognizerConfiguration: RecognizerConfiguration?
    /// Pieces of the loaded transducer's tokens.txt, for hotword coverage.
    private var tokenVocabulary: TokenVocabulary?
    /// Whether the next transducer recognizer should use hotword decoding.
    /// `prepare()` has no hints, so recording start (and each transcription)
    /// records the captured choice here. It survives idle unloading, and a
    /// prewarm then builds the recognizer the dictation will use instead of
    /// rebuilding it after recording.
    private static let anticipatedHotwordDecoding = Mutex(false)
    /// The language the next recognizer is built for. SenseVoice fixes its
    /// language at construction, so a prewarm for Auto followed by a dictation
    /// with an explicit language rebuilt it (about 350 ms) on the first
    /// dictation after every load. Speech language is a shared setting, so one
    /// value serves every model; nil means Auto.
    private static let anticipatedLanguage = Mutex<String?>(nil)

    /// Call with the recording's captured hints before prewarming the model.
    public static func anticipate(_ hints: TranscriptionHints) {
        let wanted = !hints.onDeviceVocabulary.isEmpty
        anticipatedHotwordDecoding.withLock { $0 = wanted }
        let language = hints.language
        anticipatedLanguage.withLock { $0 = language }
    }

    static var anticipatesHotwordDecoding: Bool { anticipatedHotwordDecoding.withLock { $0 } }
    static var anticipatedLanguageHint: String? { anticipatedLanguage.withLock { $0 } }

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

    /// True when `hints` decode with the loaded recognizer as is. Live preview
    /// (AD-084) never rebuilds or reloads a recognizer for display-only text.
    func isWarm(for hints: TranscriptionHints) -> Bool {
        guard recognizer != nil, let configuration = try? RecognizerConfiguration(model: model, hints: hints) else { return false }
        return configuration == recognizerConfiguration
    }

    public func prepare() async throws {
        try Task.checkCancellation()
        // A factory prepare precedes each transcription. Keep a warm recognizer's
        // language here; the next transcription resolves its own current hint.
        let configuration = try recognizerConfiguration ?? Self.anticipatedConfiguration(for: model)
        _ = try loadedRecognizer(configuration: configuration)
    }

    public func unload() async {
        recognizer = nil
        recognizerConfiguration = nil
        tokenVocabulary = nil
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        // Validate before inspecting files or entering the native runtime, including
        // callers that use this adapter without the pipeline's preflight.
        let configuration = try RecognizerConfiguration(model: model, hints: hints)
        Self.anticipate(hints)
        let recognizer = try loadedRecognizer(configuration: configuration)
        // The loaded recognizer may have fallen back to greedy decoding.
        let hotwords = recognizerConfiguration?.hotwordDecoding == true
            ? tokenVocabulary.flatMap { Self.hotwords(hints.onDeviceVocabulary, vocabulary: $0) } : nil
        let started = Date()
        // These are offline (whole-utterance) decoders; long recordings
        // are split at silences so memory and latency stay bounded.
        var text = try AudioChunker.transcribe(samples, maxSeconds: 30) {
            Self.decode($0, with: recognizer.pointer, hotwords: hotwords)
        }
        var adjustments: [TranscriptAdjustment] = []
        if model.isSenseVoice || model == .fireRed {
            // AD-082: these decoders write English in capitals and never punctuate.
            (text, adjustments) = SpokenTextNormalizer.normalizeCapitalizedOutput(text, vocabulary: hints.vocabulary)
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        // Joint-language decoders return no detected language through this API.
        // Do not report an ignored language hint as recognition metadata.
        return Transcript(text: text, language: configuration.language, engine: id, latencyMs: ms, adjustments: adjustments)
    }

    private static func decode(_ samples: [Float], with recognizer: OpaquePointer, hotwords: String?) -> String {
        let created = hotwords.map { SherpaOnnxCreateOfflineStreamWithHotwords(recognizer, $0) } ?? SherpaOnnxCreateOfflineStream(recognizer)
        guard let stream = created else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        SherpaOnnxAcceptWaveformOffline(stream, 16_000, samples, Int32(samples.count))
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        return result.pointee.text.map { String(cString: $0) } ?? ""
    }

    private func loadedRecognizer(configuration requested: RecognizerConfiguration) throws -> Recognizer {
        let folder = modelDirectory
        guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent(LocalModels.incompleteMarker).path),
              LocalModels.hasSherpa(model, at: folder) else { throw TranscriberError.modelNotDownloaded }
        if let recognizer, recognizerConfiguration == requested { return recognizer }
        var configuration = requested
        var vocabulary: TokenVocabulary?
        var scoredVocabulary: URL?
        if requested.hotwordDecoding {
            // sherpa-onnx encodes hotword text with a scored BPE vocabulary
            // (modeling_unit "bpe"). The NeMo archives ship tokens.txt only, so
            // the scored list goes to a temporary file outside the verified
            // model folder and is deleted once the recognizer has read it.
            // Vocabulary bias is optional: an unreadable tokens.txt or an
            // unwritable temporary file falls back to greedy decoding instead
            // of failing the dictation. The log names no vocabulary text.
            do {
                let tokensURL = folder.appendingPathComponent("tokens.txt")
                let tokens = try hotwordVocabularyOverride.map { try $0(tokensURL) } ?? TokenVocabulary(contentsOf: tokensURL)
                guard !tokens.pieces.isEmpty else { throw HotwordSetupError.emptyVocabulary }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("airdraft-hotword-vocab-\(UUID().uuidString).txt")
                try tokens.scoredVocabulary().write(to: url, atomically: true, encoding: .utf8)
                vocabulary = tokens
                scoredVocabulary = url
            } catch {
                Self.log.error("engine=\(self.id, privacy: .public) hotword setup failed (\(String(describing: type(of: error)), privacy: .public)); using greedy decoding")
                configuration = requested.withoutHotwords
                if let recognizer, recognizerConfiguration == configuration { return recognizer }
            }
        }
        defer { if let scoredVocabulary { try? FileManager.default.removeItem(at: scoredVocabulary) } }
        // SenseVoice fixes its language when the recognizer is constructed.
        // Release the old model before rebuilding so a language change cannot
        // retain the old decoder or temporarily double its memory use.
        recognizer = nil
        recognizerConfiguration = nil
        tokenVocabulary = nil
        try Task.checkCancellation()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let pointer = configuration.withCConfiguration(folder: folder, files: files, bpeVocabulary: scoredVocabulary?.path) {
            SherpaOnnxCreateOfflineRecognizer(&$0)
        }
        guard let pointer else { throw TranscriberError.modelNotDownloaded }
        let created = Recognizer(pointer)
        recognizer = created
        recognizerConfiguration = configuration
        tokenVocabulary = vocabulary
        return created
    }

    private enum HotwordSetupError: Error { case emptyVocabulary }

    /// Tests inject a failing vocabulary reader; production reads the model folder.
    private var hotwordVocabularyOverride: (@Sendable (URL) throws -> TokenVocabulary)?
    func setHotwordVocabularyReader(_ reader: (@Sendable (URL) throws -> TokenVocabulary)?) { hotwordVocabularyOverride = reader }
    /// The configuration of the loaded recognizer, for tests.
    var loadedConfiguration: RecognizerConfiguration? { recognizerConfiguration }

    /// The recognizer a cold prepare builds: the captured vocabulary choice and
    /// language. A language this model cannot use (the shared setting can be
    /// stale after a model switch) falls back to Auto, so preparation never
    /// fails on it; transcription validates the real language itself.
    static func anticipatedConfiguration(for model: Model) throws -> RecognizerConfiguration {
        let hotwords = anticipatesHotwordDecoding
        if let language = anticipatedLanguageHint,
           let configuration = try? RecognizerConfiguration(model: model, language: language, hotwordDecoding: hotwords) {
            return configuration
        }
        return try RecognizerConfiguration(model: model, hotwordDecoding: hotwords)
    }

    /// sherpa-onnx boost added to each matched hotword token.
    static let hotwordScore: Float = 1.5

    /// One phrase per term, separated by "/" (sherpa-onnx's per-stream line
    /// separator). A term the model's pieces cannot spell is skipped, because
    /// sherpa-onnx would otherwise boost the spellable prefix alone.
    static func hotwords(_ terms: [String], vocabulary: TokenVocabulary) -> String? {
        let phrases = terms.filter { term in
            term.split(separator: " ").allSatisfy { vocabulary.canEncode("\u{2581}" + $0) }
        }
        return phrases.isEmpty ? nil : phrases.joined(separator: "/")
    }

    /// The same value owns native configuration and cache identity. Tests inspect
    /// the C fields synchronously without loading model weights or the runtime.
    struct RecognizerConfiguration: Equatable {
        let model: Model
        let language: String?
        /// Modified beam search with a hotword context graph. Greedy search
        /// otherwise, which is also the only method the other models accept.
        let hotwordDecoding: Bool

        init(model: Model, hints: TranscriptionHints = .init()) throws {
            try self.init(model: model, hints: hints,
                          hotwordDecoding: model.supportsHotwords && !hints.onDeviceVocabulary.isEmpty)
        }

        init(model: Model, hotwordDecoding: Bool) throws {
            try self.init(model: model, hints: .init(), hotwordDecoding: hotwordDecoding)
        }

        init(model: Model, language: String?, hotwordDecoding: Bool) throws {
            try self.init(model: model, hints: .init(language: language), hotwordDecoding: hotwordDecoding)
        }

        private init(model: Model, hints: TranscriptionHints, hotwordDecoding: Bool) throws {
            self.model = model
            self.hotwordDecoding = hotwordDecoding && model.supportsHotwords
            let kind: ASRProviderKind
            switch model {
            case .senseVoice: kind = .senseVoice
            case .senseVoiceMultilingual: kind = .senseVoiceMultilingual
            case .fireRed: kind = .fireRed
            case .parakeet: kind = .parakeet
            case .orukeet: kind = .orukeet
            }
            let config = ASRConfig(kind: kind, language: hints.language ?? "")
            language = try SpeechLanguagePolicy.resolve(config).language
        }

        /// The same recognizer with greedy decoding, for an unusable hotword setup.
        var withoutHotwords: RecognizerConfiguration {
            RecognizerConfiguration(model: model, language: language, hotwords: false)
        }

        private init(model: Model, language: String?, hotwords: Bool) {
            self.model = model
            self.language = language
            self.hotwordDecoding = hotwords
        }

        func withCConfiguration<Value>(folder: URL, files: [String], bpeVocabulary: String? = nil,
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
            case .senseVoice, .senseVoiceMultilingual:
                config.model_config.model_type = c("sense_voice")
                config.model_config.sense_voice.model = c(onnx("model"))
                config.model_config.sense_voice.language = c(language ?? "auto")
                config.model_config.sense_voice.use_itn = 1
            case .fireRed:
                config.model_config.model_type = c("fire_red_asr")
                config.model_config.fire_red_asr.encoder = c(onnx("encoder"))
                config.model_config.fire_red_asr.decoder = c(onnx("decoder"))
            case .parakeet, .orukeet:
                config.model_config.model_type = c("nemo_transducer")
                config.model_config.transducer.encoder = c(onnx("encoder"))
                config.model_config.transducer.decoder = c(onnx("decoder"))
                config.model_config.transducer.joiner = c(onnx("joiner"))
                if hotwordDecoding, let bpeVocabulary {
                    // "bpe" without a vocabulary would dereference a null encoder
                    // in sherpa-onnx, so both are set together or not at all.
                    config.decoding_method = c("modified_beam_search")
                    config.max_active_paths = 4
                    config.hotwords_score = SherpaTranscriber.hotwordScore
                    config.model_config.modeling_unit = c("bpe")
                    config.model_config.bpe_vocab = c(bpeVocabulary)
                } else {
                    config.decoding_method = c("greedy_search")
                }
            }
            return try body(&config)
        }
    }
}

extension SherpaTranscriber {
    /// The SentencePiece pieces of a transducer's tokens.txt ("piece id" lines).
    struct TokenVocabulary: Sendable, Equatable {
        /// Pieces in file order; whitespace-bearing or malformed lines are skipped.
        let pieces: [String]
        private let byteSet: Set<[UInt8]>
        private let longestPiece: Int

        init(contentsOf url: URL) throws {
            try self.init(text: String(contentsOf: url, encoding: .utf8))
        }

        init(text: String) {
            var pieces: [String] = []
            for line in text.split(whereSeparator: \.isNewline) {
                let fields = line.split(separator: " ", omittingEmptySubsequences: false)
                guard fields.count == 2, !fields[0].isEmpty, Int(fields[1]) != nil else { continue }
                pieces.append(String(fields[0]))
            }
            self.pieces = pieces
            byteSet = Set(pieces.map { Array($0.utf8) })
            longestPiece = pieces.map(\.utf8.count).max() ?? 0
        }

        /// Whether `word` (with its leading "▁") splits entirely into pieces,
        /// over UTF-8 bytes like the sherpa-onnx encoder.
        func canEncode(_ word: String) -> Bool {
            let bytes = Array(word.utf8)
            guard !bytes.isEmpty, longestPiece > 0 else { return false }
            var reachable = [Bool](repeating: false, count: bytes.count + 1)
            reachable[0] = true
            for start in 0..<bytes.count where reachable[start] {
                for end in (start + 1)...min(bytes.count, start + longestPiece) where !reachable[end] {
                    if byteSet.contains(Array(bytes[start..<end])) { reachable[end] = true }
                }
            }
            return reachable[bytes.count]
        }

        /// "piece score" lines for sherpa-onnx's bundled simple-sentencepiece,
        /// which picks the highest-scoring split. Every piece costs about 1, so
        /// the split with the fewest pieces wins, ties going to the lower
        /// (more frequent) token ID. The encoder exits the process on a
        /// malformed line, so only validated pieces are written.
        func scoredVocabulary() -> String {
            let count = Float(max(pieces.count, 1))
            return pieces.enumerated()
                .map { "\($0.element) \(-1 - Float($0.offset) / count)" }
                .joined(separator: "\n") + "\n"
        }
    }
}
