import Foundation

/// A file/meeting transcript is a document, never an inserted dictation or a typing statistic.
public struct TranscriptDocument: Codable, Identifiable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable {
        case ready, transcribing, identifyingSpeakers, completed, paused, failed
        public var title: String {
            switch self {
            case .ready: return String(localized: "Ready to transcribe", bundle: .module)
            case .transcribing: return String(localized: "Transcribing", bundle: .module)
            case .identifyingSpeakers: return String(localized: "Identifying speakers", bundle: .module)
            case .completed: return String(localized: "Completed", bundle: .module)
            case .paused: return String(localized: "Paused", bundle: .module)
            case .failed: return String(localized: "Needs attention", bundle: .module)
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
    /// The template that produced `summary`; nil for summaries made before templates.
    public var summaryTemplate: MeetingSummaryTemplate?
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
        guard let id else { return Self.unknownSpeakerName }
        // A cleared name falls back to the label instead of an empty speaker.
        if let name = speakerNames[id], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        return "Speaker \(id)"
    }
    public static var unknownSpeakerName: String { String(localized: "Unknown speaker", bundle: .module) }
    /// The label offered for a new speaker in the editor.
    public static func defaultSpeakerName(_ id: String) -> String { String(localized: "Speaker \(id)", bundle: .module) }
    /// One name per speaker ID: every passage assigned to that ID shows it, in
    /// both transcript versions, because turns store the ID rather than the name.
    public mutating func setSpeakerName(_ name: String, for id: String) {
        speakerNames[id] = name
    }
    /// Names worth suggesting in later meetings: typed, single-line and not a default label.
    public var rememberableSpeakerNames: [String] {
        var seen: Set<String> = []
        return speakerNames.keys.sorted().compactMap { id in
            guard let name = SpeakerNameLibrary.rememberableName(speakerNames[id] ?? ""),
                  seen.insert(SpeakerNameLibrary.key(name)).inserted else { return nil }
            return name
        }
    }
    /// Recent names not already given to another speaker in this document.
    public func speakerNameSuggestions(_ recent: [String], for id: String) -> [String] {
        let taken = Set(speakerNames.filter { $0.key != id }.compactMap { SpeakerNameLibrary.rememberableName($0.value) }.map(SpeakerNameLibrary.key))
        return recent.filter { !taken.contains(SpeakerNameLibrary.key($0)) }
    }
    public mutating func rebuildTurns() {
        turns = TranscriptTurn.group(words)
    }
}

public struct MediaConfiguration: Codable, Sendable, Equatable {
    public enum Engine: String, Codable, Sendable, CaseIterable { case local, soniox }
    public enum LocalModel: String, Codable, CaseIterable, Sendable {
        case whisperTurbo, whisperLargeV3, whisperTurboCompressed, qwenLarge, qwenSmall, cohere, senseVoice, fireRed, parakeet, apple, orukeet, gguf, coreML, whisperDistilLargeV3, whisperDistilCompressed, whisperDistilTurbo, whisperDistilTurboCompressed
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
            case .whisperDistilLargeV3: return WhisperModelVariant.distilLargeV3.title
            case .whisperDistilCompressed: return WhisperModelVariant.distilLargeV3Compressed.title
            case .whisperDistilTurbo: return WhisperModelVariant.distilTurbo.title
            case .whisperDistilTurboCompressed: return WhisperModelVariant.distilTurboCompressed.title
            case .orukeet: return "Orukeet"
            case .coreML: return String(localized: "Core ML speech model", bundle: .module)
            case .gguf: return String(localized: "GGUF speech model", bundle: .module)
            case .apple: return "Apple Speech"
            }
        }
        public var kind: ASRProviderKind {
            switch self {
            case .whisperTurbo, .whisperLargeV3, .whisperTurboCompressed, .whisperDistilLargeV3, .whisperDistilCompressed, .whisperDistilTurbo, .whisperDistilTurboCompressed: return .whisperKit
            case .qwenLarge, .qwenSmall: return .qwen3
            case .cohere: return .cohere
            case .senseVoice: return .senseVoice
            case .fireRed: return .fireRed
            case .parakeet: return .parakeet
            case .orukeet: return .orukeet
            case .coreML: return .fluidAudio
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
        case .whisperDistilLargeV3: return .distilLargeV3
        case .whisperDistilCompressed: return .distilLargeV3Compressed
        case .whisperDistilTurbo: return .distilTurbo
        case .whisperDistilTurboCompressed: return .distilTurboCompressed
        default: return nil
        }
    }
    public var engine: Engine
    public var whisperModel: String
    public var language: String
    public var identifySpeakers: Bool
    // Optional additions keep existing document payloads decodable without rewriting them.
    public var localModel: LocalModel?
    public var coreMLModel: String?
    public var ggufModel: String?
    public var appleLocale: String?
    public var selectedLocalModel: LocalModel { localModel ?? .whisperTurbo }
    public var usesSegmentTiming: Bool { engine == .local && selectedLocalModel.kind != .whisperKit }
    public init(engine: Engine = .local, whisperModel: String? = nil, language: String = "", identifySpeakers: Bool = true,
                localModel: LocalModel? = nil, appleLocale: String? = nil, ggufModel: String? = nil, coreMLModel: String? = nil) {
        self.engine = engine; self.whisperModel = whisperModel ?? Self.whisperVariant(for: localModel ?? .whisperTurbo)?.rawValue ?? Self.supportedWhisperModel
        self.language = language; self.identifySpeakers = identifySpeakers
        self.localModel = localModel; self.appleLocale = appleLocale; self.ggufModel = ggufModel; self.coreMLModel = coreMLModel
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
        LocalModel.allCases.filter { $0 != .gguf && $0 != .coreML }.map { .init(id: $0.rawValue, title: $0.title) }
            + CoreMLSpeechModelCatalog.models.map { .init(id: "coreml:\($0.id)", title: "\($0.title) · Core ML") }
            + GGUFModelCatalog.models.map { .init(id: "gguf:\($0.id)", title: "\($0.title) · GGUF") }
    }
    public var selectedModelID: String {
        if selectedLocalModel == .coreML { return "coreml:\(coreMLModel ?? "")" }
        return selectedLocalModel == .gguf ? "gguf:\(ggufModel ?? "")" : selectedLocalModel.rawValue
    }
    public var selectedModelTitle: String {
        if selectedLocalModel == .coreML { return CoreMLSpeechModelCatalog.model(coreMLModel ?? "")?.title ?? String(localized: "Unavailable speech model", bundle: .module) }
        if selectedLocalModel == .gguf { return GGUFModelCatalog.model(ggufModel ?? "")?.title ?? String(localized: "Unavailable speech model", bundle: .module) }
        return selectedLocalModel.title
    }
    public mutating func selectModelChoice(_ id: String) {
        if id.hasPrefix("coreml:") {
            selectLocalModel(.coreML)
            coreMLModel = String(id.dropFirst(7))
        } else if id.hasPrefix("gguf:") {
            selectLocalModel(.gguf)
            ggufModel = String(id.dropFirst(5))
        } else if let model = LocalModel(rawValue: id), model != .gguf, model != .coreML {
            selectLocalModel(model)
        }
    }
    public func validate() throws {
        if engine == .local, selectedLocalModel == .coreML,
           CoreMLSpeechModelCatalog.model(coreMLModel ?? "") == nil { throw MediaError.unsupportedModel }
        if engine == .local, selectedLocalModel == .gguf,
           GGUFModelCatalog.model(ggufModel ?? "") == nil { throw MediaError.unsupportedModel }
        if engine == .local && selectedLocalModel.kind == .whisperKit,
           whisperModel != Self.whisperVariant(for: selectedLocalModel)?.rawValue { throw MediaError.unsupportedModel }
        _ = try SpeechLanguagePolicy.resolve(asr)
    }
    public var asr: ASRConfig {
        ASRConfig(kind: engine == .local ? selectedLocalModel.kind : .soniox, whisperModel: whisperModel,
                  qwen3Model: selectedLocalModel == .qwenSmall ? "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" : "aufklarer/Qwen3-ASR-1.7B-MLX-5bit",
                  appleLocale: appleLocale ?? "zh-TW", model: selectedLocalModel == .gguf ? ggufModel ?? "" : selectedLocalModel == .coreML ? coreMLModel ?? "" : "gpt-transcribe", language: language)
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
    case invalidAudio, tooLong, unavailable, conflict, busy, missingSpeakerModel, insufficientMemory, unsupportedModel, noSpeakerActivity, emptySummary
    public var errorDescription: String? {
        switch self {
        case .emptySummary: return String(localized: "The refinement provider returned an empty summary. Try again or choose another template.", bundle: .module)
        case .noSpeakerActivity: return String(localized: "No speech regions were identified. Choose Without Speakers to transcribe the full recording.", bundle: .module)
        case .unsupportedModel: return String(localized: "This saved transcription uses an unsupported model. Start a new transcription with a model listed in Meetings.", bundle: .module)
        case .invalidAudio: return String(localized: "This file has no decodable audio. Try a WAV, M4A, MP3, MP4 or MOV file.", bundle: .module)
        case .tooLong: return String(localized: "Media files can be up to two hours long. Split this recording before importing it.", bundle: .module)
        case .unavailable: return String(localized: "The recording or document is no longer available.", bundle: .module)
        case .conflict: return String(localized: "This document changed in another operation. Reopen it to load the latest version.", bundle: .module)
        case .busy: return String(localized: "Finish the current recording or media job first.", bundle: .module)
        case .missingSpeakerModel: return String(localized: "Download the speaker model before identifying speakers.", bundle: .module)
        case .insufficientMemory: return String(localized: "There is not enough available memory to identify speakers in this recording. Close other apps and retry, or choose Without Speakers.", bundle: .module)
        }
    }
}
