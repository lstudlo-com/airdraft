import Foundation

#if !os(macOS)
/// iOS builds no sherpa-onnx recognizer yet (Vendor/ has macOS slices only).
/// This namespace keeps the shared model catalogue and constants available.
public enum SherpaTranscriber {
    public static func anticipate(_ hints: TranscriptionHints) {}
}
#endif

extension SherpaTranscriber {
    /// Final transcription decodes windows of at most this length, cut at silence;
    /// live text that becomes the transcript commits at the same cuts (AD-123).
    public static let chunkSeconds: Double = 30

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
}
