import Foundation

/// A file/meeting transcript is a document, never an inserted dictation or a typing statistic.
public struct TranscriptDocument: Codable, Identifiable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable {
        case ready, transcribing, identifyingSpeakers, completed, paused, failed
        public var title: String {
            switch self {
            case .ready: return "Ready to transcribe"
            case .transcribing: return "Transcribing"
            case .identifyingSpeakers: return "Identifying speakers"
            case .completed: return "Completed"
            case .paused: return "Paused"
            case .failed: return "Needs attention"
            }
        }
    }
    public let id: String
    public let createdAt: Date
    public var recordingID: String?
    public var title: String
    public var configuration: MediaConfiguration
    public var stage: Stage = .ready
    public var completedSeconds: Double = 0
    public var transcriptionComplete = false
    public var diarizationComplete = false
    /// Saved before segment decoding; resumed jobs retain their speaker identities.
    public var speakerIntervals: [SpeakerInterval]?
    public var words: [TranscriptWord] = []
    public var turns: [TranscriptTurn] = []
    public var speakerNames: [String: String] = [:]
    public var summary: String?
    public var issue: String?
    public var remoteFileID: String?
    public var remoteJobID: String?
    public var revision = 0

    public init(recordingID: String, title: String, configuration: MediaConfiguration, createdAt: Date = Date()) {
        id = UUID().uuidString
        self.createdAt = createdAt
        self.recordingID = recordingID
        self.title = title
        self.configuration = configuration
    }
    public var originalText: String { words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) }
    public var text: String { turns.isEmpty ? originalText : turns.map(\.text).joined(separator: "\n") }
    public func speakerName(_ id: String?) -> String {
        guard let id else { return "Unknown speaker" }
        return speakerNames[id] ?? "Speaker \(id)"
    }
    public mutating func rebuildTurns() {
        turns = TranscriptTurn.group(words)
    }
}

public struct MediaConfiguration: Codable, Sendable, Equatable {
    public enum Engine: String, Codable, Sendable, CaseIterable { case local, soniox }
    public enum LocalModel: String, Codable, CaseIterable, Sendable {
        case whisperTurbo, whisperLargeV3, whisperTurboCompressed, qwenLarge, qwenSmall, cohere, senseVoice, fireRed, parakeet, apple, gguf
        public var title: String {
            switch self {
            case .whisperTurbo: return WhisperModelVariant.turbo.title
            case .whisperLargeV3: return WhisperModelVariant.largeV3.title
            case .whisperTurboCompressed: return WhisperModelVariant.turboCompressed.title
            case .qwenLarge: return "Qwen3-ASR 1.7B"
            case .qwenSmall: return "Qwen3-ASR 0.6B"
            case .cohere: return "Cohere Transcribe 2B"
            case .senseVoice: return "SenseVoice Small"
            case .fireRed: return "FireRedASR2"
            case .parakeet: return "Parakeet TDT v3"
            case .gguf: return "GGUF speech model"
            case .apple: return "Apple Speech"
            }
        }
        public var kind: ASRProviderKind {
            switch self {
            case .whisperTurbo, .whisperLargeV3, .whisperTurboCompressed: return .whisperKit
            case .qwenLarge, .qwenSmall: return .qwen3
            case .cohere: return .cohere
            case .senseVoice: return .senseVoice
            case .fireRed: return .fireRed
            case .parakeet: return .parakeet
            case .gguf: return .transcribeCpp
            case .apple: return .apple
            }
        }
    }
    public static func whisperVariant(for model: LocalModel) -> WhisperModelVariant? {
        switch model {
        case .whisperTurbo: return .turbo
        case .whisperLargeV3: return .largeV3
        case .whisperTurboCompressed: return .turboCompressed
        default: return nil
        }
    }
    public var engine: Engine
    public var whisperModel: String
    public var language: String
    public var identifySpeakers: Bool
    // Optional additions keep existing document payloads decodable without rewriting them.
    public var localModel: LocalModel?
    public var ggufModel: String?
    public var appleLocale: String?
    public var selectedLocalModel: LocalModel { localModel ?? .whisperTurbo }
    public var usesSegmentTiming: Bool { engine == .local && selectedLocalModel.kind != .whisperKit }
    public init(engine: Engine = .local, whisperModel: String? = nil, language: String = "", identifySpeakers: Bool = true,
                localModel: LocalModel? = nil, appleLocale: String? = nil, ggufModel: String? = nil) {
        self.engine = engine; self.whisperModel = whisperModel ?? Self.whisperVariant(for: localModel ?? .whisperTurbo)?.rawValue ?? Self.supportedWhisperModel
        self.language = language; self.identifySpeakers = identifySpeakers
        self.localModel = localModel; self.appleLocale = appleLocale; self.ggufModel = ggufModel
    }
    public static let supportedWhisperModel = "large-v3-v20240930_turbo"
    public mutating func selectLocalModel(_ model: LocalModel) {
        if model == .apple && selectedLocalModel != .apple {
            appleLocale = ASRConfig(kind: .apple, appleLocale: appleLocale ?? "zh-TW", language: language).effectiveAppleLocale
            language = ""
        }
        localModel = model
        if let variant = Self.whisperVariant(for: model) { whisperModel = variant.rawValue }
    }
    public struct ModelChoice: Identifiable, Sendable {
        public let id: String
        public let title: String
    }
    public static var modelChoices: [ModelChoice] {
        LocalModel.allCases.filter { $0 != .gguf }.map { .init(id: $0.rawValue, title: $0.title) }
            + GGUFModelCatalog.models.map { .init(id: "gguf:\($0.id)", title: "\($0.title) · GGUF") }
    }
    public var selectedModelID: String {
        selectedLocalModel == .gguf ? "gguf:\(ggufModel ?? "")" : selectedLocalModel.rawValue
    }
    public var selectedModelTitle: String {
        if selectedLocalModel == .gguf { return GGUFModelCatalog.model(ggufModel ?? "")?.title ?? "Unavailable speech model" }
        return selectedLocalModel.title
    }
    public mutating func selectModelChoice(_ id: String) {
        if id.hasPrefix("gguf:") {
            selectLocalModel(.gguf)
            ggufModel = String(id.dropFirst(5))
        } else if let model = LocalModel(rawValue: id), model != .gguf {
            selectLocalModel(model)
        }
    }
    public func validate() throws {
        if engine == .local, selectedLocalModel == .gguf,
           GGUFModelCatalog.model(ggufModel ?? "") == nil { throw MediaError.unsupportedModel }
        if engine == .local && selectedLocalModel.kind == .whisperKit,
           whisperModel != Self.whisperVariant(for: selectedLocalModel)?.rawValue { throw MediaError.unsupportedModel }
        _ = try SpeechLanguagePolicy.resolve(asr)
    }
    public var asr: ASRConfig {
        ASRConfig(kind: engine == .local ? selectedLocalModel.kind : .soniox, whisperModel: whisperModel,
                  qwen3Model: selectedLocalModel == .qwenSmall ? "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" : "aufklarer/Qwen3-ASR-1.7B-MLX-5bit",
                  appleLocale: appleLocale ?? "zh-TW", model: selectedLocalModel == .gguf ? ggufModel ?? "" : "gpt-transcribe", language: language)
    }
    /// Bounded v1 file contract. Diarization clusters the whole session; independent chunks must not reuse speaker IDs.
    public static let maximumDuration: Double = 2 * 60 * 60
}

public struct TranscriptWord: Codable, Sendable, Equatable {
    public enum Timing: String, Codable, Sendable { case segment }
    /// nil retains the native word timing of older documents and Whisper/Soniox.
    public var timing: Timing?
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    public var overlapping: Bool
    public init(start: Double, end: Double, text: String, speaker: String? = nil, overlapping: Bool = false, timing: Timing? = nil) {
        self.start = start; self.end = end; self.text = text; self.speaker = speaker; self.overlapping = overlapping
        self.timing = timing
    }
}

public struct TranscriptTurn: Codable, Identifiable, Sendable, Equatable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var speaker: String?
    public var originalText: String
    public var originalSpeaker: String?
    public var editedText: String?
    public var overlapping: Bool
    public var text: String { editedText ?? originalText }

    public static func group(_ words: [TranscriptWord]) -> [Self] {
        var turns: [Self] = []
        for word in words where word.start.isFinite && word.end.isFinite && word.end >= word.start {
            if let last = turns.last, last.speaker == word.speaker, word.start - last.end < 1.5,
               word.end - last.start < 30, last.overlapping == word.overlapping {
                turns[turns.count - 1].end = max(last.end, word.end)
                turns[turns.count - 1].originalText += word.text
            } else {
                turns.append(Self(id: turns.count, start: max(0, word.start), end: max(0, word.end),
                                  speaker: word.speaker, originalText: word.text, originalSpeaker: word.speaker, overlapping: word.overlapping))
            }
        }
        return turns
    }
}

public struct SpeakerInterval: Codable, Equatable, Sendable {
    public static let unassigned = "__unassigned__"
    public var start: Double
    public var end: Double
    public var speaker: String
    public init(start: Double, end: Double, speaker: String) { self.start = start; self.end = end; self.speaker = speaker }
}

public enum SpeakerReconciliation {
    /// Maximum word overlap, with unknown gaps and explicit overlap. Never infer people's real names.
    public static func align(_ words: [TranscriptWord], speakers: [SpeakerInterval]) -> [TranscriptWord] {
        let intervals = speakers.sorted { $0.start < $1.start }
        var cursor = 0
        return words.map { original in
            var word = original
            while cursor < intervals.count && intervals[cursor].end < word.start { cursor += 1 }
            var weights: [String: Double] = [:]
            var index = cursor
            while index < intervals.count, intervals[index].start <= word.end {
                let interval = intervals[index]
                let overlap = max(0, min(word.end, interval.end) - max(word.start, interval.start))
                if overlap > 0 { weights[interval.speaker, default: 0] += overlap }
                index += 1
            }
            word.speaker = weights.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
            if word.speaker == SpeakerInterval.unassigned { word.speaker = nil }
            word.overlapping = weights.values.filter { $0 > max(0.04, (word.end - word.start) * 0.25) }.count > 1
            return word
        }
    }
}

public enum MediaError: LocalizedError {
    case invalidAudio, tooLong, unavailable, conflict, busy, missingSpeakerModel, insufficientMemory, unsupportedModel, noSpeakerActivity
    public var errorDescription: String? {
        switch self {
        case .noSpeakerActivity: return "No speech regions were identified. Choose Without Speakers to transcribe the full recording."
        case .unsupportedModel: return "This saved transcription uses an unsupported model. Start a new transcription with a model listed in Meetings."
        case .invalidAudio: return "This file has no decodable audio. Try a WAV, M4A, MP3, MP4 or MOV file."
        case .tooLong: return "Media files can be up to two hours long. Split this recording before importing it."
        case .unavailable: return "The recording or document is no longer available."
        case .conflict: return "This document changed in another operation. Reopen it to load the latest version."
        case .busy: return "Finish the current recording or media job first."
        case .missingSpeakerModel: return "Download the speaker model before identifying speakers."
        case .insufficientMemory: return "There is not enough available memory to identify speakers in this recording. Close other apps and retry, or choose Without Speakers."
        }
    }
}
