import Foundation
import os

/// Optional engine hooks for the output guards. Engines without them still get
/// the generic checks (language retry with an explicit language, loop trimming).
public protocol LocalASRGuardSupport: Transcriber {
    /// One more decode after an empty result on audible input, with the engine's
    /// no-speech gate relaxed. The guard never calls it for silent audio.
    func transcribeAfterEmptyResult(samples: [Float], hints: TranscriptionHints) async throws -> Transcript
    /// Spoken-language probabilities (0...1, keyed by ISO 639-1 code) for the
    /// first 30 seconds, or nil when the engine cannot measure them.
    func spokenLanguageProbabilities(samples: [Float]) async throws -> [String: Double]?
}

/// Per-chunk decoding budgets that scale with audio duration (AD-082).
public enum LocalASRDecodeBudget {
    /// Fast Mandarin or English dictation stays below about 9 output tokens per
    /// second in Airdraft's mixed-language measurement; this allows ~1.8x that.
    static let qwenTokensPerSecond = 16.0
    static let qwenTokenFloor = 48
    static let qwenTokenCeiling = 1024

    /// Qwen3-ASR's decoder cap for a chunk of `sampleCount` 16 kHz samples. A
    /// decoder loop stops here instead of running to 1,024 tokens, which took
    /// 24 s and an 18.5 GB peak footprint on a 3 s clip.
    public static func qwenMaxTokens(sampleCount: Int, sampleRate: Int = 16_000) -> Int {
        let seconds = Double(sampleCount) / Double(max(1, sampleRate))
        let budget = Int((seconds * qwenTokensPerSecond).rounded(.up)) + qwenTokenFloor
        return min(qwenTokenCeiling, max(qwenTokenFloor, budget))
    }
}

/// Checks local speech output before refinement (AD-082):
///  1. an empty result on audible audio gets one relaxed retry (engines that support it);
///  2. under Auto, a result in a script none of the user's languages use, or
///     a probable English translation of Chinese speech (Whisper), is decoded
///     once more with the best explicit language the same model supports;
///  3. decoder loops are cut to one occurrence.
/// Retries reuse the same engine and lease; models are never switched. Retry
/// failures keep the first result. Every action is recorded on the transcript.
public enum LocalASROutputGuard {
    public struct Policy: Sendable {
        /// The user's languages in preference order (canonical codes).
        public var expectedLanguages: [String]
        /// Minimum spoken probability of an expected non-Latin language before a
        /// Latin-only Auto result is decoded again in that language. Measured with
        /// Whisper Large v3 Turbo: pure English speech scored at most 0.0002 for
        /// Mandarin; English translations of code-switched Mandarin scored 0.14-0.85.
        public var translationProbability: Double
        /// Retries run only when the first decode took at most this long.
        public var retryBudget: @Sendable (_ audioSeconds: Double) -> Double

        public init(expectedLanguages: [String], translationProbability: Double = 0.1,
                    retryBudget: @escaping @Sendable (Double) -> Double = { max(8, $0 * 1.5) }) {
            self.expectedLanguages = expectedLanguages
            self.translationProbability = translationProbability
            self.retryBudget = retryBudget
        }

        /// The system's preferred languages plus English, which dictation mixes in everywhere.
        public static var current: Policy {
            Policy(expectedLanguages: LocalASROutputGuard.expectedLanguages(preferred: Locale.preferredLanguages))
        }
    }

    static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "asr-guard")

    /// Canonical, ordered, de-duplicated languages; zh-HK expands to Cantonese and Mandarin.
    public static func expectedLanguages(preferred: [String]) -> [String] {
        var result: [String] = []
        func add(_ code: String) { if !result.contains(code) { result.append(code) } }
        for identifier in preferred {
            guard let code = try? SpeechLanguagePolicy.canonicalLanguage(identifier) else { continue }
            if code == "zh-hk" { add("yue"); add("zh") } else { add(code) }
        }
        add("en")
        return result
    }

    public static func transcribe(engine: any Transcriber, samples: [Float], hints: TranscriptionHints,
                                  config: ASRConfig, policy: Policy = .current) async throws -> Transcript {
        let first = try await engine.transcribe(samples: samples, hints: hints)
        guard config.kind.isLocal else { return first }
        let started = ProcessInfo.processInfo.systemUptime
        let firstSeconds = Double(first.latencyMs) / 1000
        let audioSeconds = Double(samples.count) / 16_000
        // A retry costs about one more decode; skip it when the first was already slow.
        let mayRetry = firstSeconds <= policy.retryBudget(audioSeconds)
        let support = engine as? LocalASRGuardSupport
        let expected = Set(policy.expectedLanguages)
        var result = first

        // 1. Empty output on audible input.
        if result.isEmpty, mayRetry, let support, AudioActivity.isAudible(samples) {
            if let retry = try await attempt({ try await support.transcribeAfterEmptyResult(samples: samples, hints: hints) }),
               !retry.isEmpty, !KnownHallucination.matches(retry.text) {
                result = retry.adding(first.adjustments + [.emptyRetried])
            }
            note(.emptyRetried, engine: engine.id, applied: result.adjustments.contains(.emptyRetried), audioSeconds: audioSeconds)
        }

        // 2. Language sanity under Auto.
        let resolved = try SpeechLanguagePolicy.resolve(config)
        if resolved.language == nil, hints.language == nil, resolved.isAutomatic, !result.isEmpty, mayRetry {
            let profile = ScriptProfile(result.text)
            if profile.isImplausible(expected: expected),
               let language = explicitLanguage(for: config, candidates: policy.expectedLanguages) {
                var retryHints = hints
                retryHints.language = language
                if let retry = try await attempt({ try await engine.transcribe(samples: samples, hints: retryHints) }),
                   !retry.isEmpty,
                   ScriptProfile(retry.text).plausibility(expected: expected) > profile.plausibility(expected: expected) {
                    result = retry.adding(result.adjustments + [.languageRetried])
                }
                note(.languageRetried, engine: engine.id, applied: result.adjustments.contains(.languageRetried), audioSeconds: audioSeconds)
            } else if profile.isLatinOnly, let support {
                let candidates = policy.expectedLanguages.filter { code in
                    nonLatinScript(of: code) != nil && explicitLanguage(for: config, candidates: [code]) != nil
                }
                if !candidates.isEmpty,
                   let probabilities = try await attempt({ try await support.spokenLanguageProbabilities(samples: samples) }) ?? nil,
                   let language = candidates.max(by: { (probabilities[$0] ?? 0) < (probabilities[$1] ?? 0) }),
                   logProbe(engine: engine.id, language: language, probability: probabilities[language] ?? 0),
                   (probabilities[language] ?? 0) >= policy.translationProbability,
                   let script = nonLatinScript(of: language) {
                    var retryHints = hints
                    retryHints.language = language
                    if let retry = try await attempt({ try await engine.transcribe(samples: samples, hints: retryHints) }),
                       ScriptProfile(retry.text).fraction(script) >= 0.2 {
                        result = retry.adding(result.adjustments + [.languageRetried])
                    }
                    note(.languageRetried, engine: engine.id, applied: result.adjustments.contains(.languageRetried), audioSeconds: audioSeconds)
                }
            }
        }

        // 3. Decoder loops.
        if let trimmed = TranscriptRepetition.trimmed(result.text) {
            result.text = trimmed
            result.adjustments.append(.repetitionTrimmed)
            note(.repetitionTrimmed, engine: engine.id, applied: true, audioSeconds: audioSeconds)
        }
        if result.adjustments != first.adjustments {
            let guardMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            result.latencyMs = first.latencyMs + guardMs
        }
        return result
    }

    /// Best explicit language the model accepts, preferring the user's non-English
    /// languages: a forced English decode would drop Chinese from mixed speech.
    static func explicitLanguage(for config: ASRConfig, candidates: [String]) -> String? {
        let ordered = candidates.filter { $0 != "en" } + candidates.filter { $0 == "en" }
        for code in ordered {
            var explicit = config
            explicit.language = code
            guard let resolved = try? SpeechLanguagePolicy.resolve(explicit), let language = resolved.language,
                  [.forced, .hint].contains(resolved.capabilities.manualControl) else { continue }
            return language
        }
        return nil
    }

    static func nonLatinScript(of language: String) -> WritingScript? {
        switch language {
        case "zh", "yue": return .han
        case "ja": return .kana
        case "ko": return .hangul
        default: return nil
        }
    }

    /// Retries are best effort: cancellation propagates, other failures keep the first result.
    private static func attempt<Value>(_ body: () async throws -> Value) async throws -> Value? {
        try Task.checkCancellation()
        do { return try await body() } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            log.notice("retry failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    /// Logs the measured spoken-language probability (no text). Always true.
    private static func logProbe(engine: String, language: String, probability: Double) -> Bool {
        log.notice("engine=\(engine, privacy: .public) probe=\(language, privacy: .public) probability=\(probability)")
        return true
    }

    private static func note(_ action: TranscriptAdjustment, engine: String, applied: Bool, audioSeconds: Double) {
        log.notice("engine=\(engine, privacy: .public) action=\(action.rawValue, privacy: .public) applied=\(applied) audioSeconds=\(audioSeconds)")
    }
}

private extension Transcript {
    func adding(_ earlier: [TranscriptAdjustment]) -> Transcript {
        var copy = self
        var merged = earlier
        for adjustment in adjustments where !merged.contains(adjustment) { merged.append(adjustment) }
        copy.adjustments = merged
        return copy
    }
}
