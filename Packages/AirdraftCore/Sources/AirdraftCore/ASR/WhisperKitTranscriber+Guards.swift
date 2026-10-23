import CoreML
import Foundation
import Synchronization
import WhisperKit

/// AD-082 hooks for `LocalASROutputGuard`. They reuse the loaded pipeline and
/// run inside the factory lease of the dictation that called them.
extension WhisperKitTranscriber: LocalASRGuardSupport {
    /// Whisper drops a window whose no-speech probability exceeds 0.6, which
    /// returned nothing for 6 of 360 audible mixed-language utterances. The retry
    /// disables that gate and the script prompt, keeping the same model, language
    /// and bounded 25-second windows.
    public func transcribeAfterEmptyResult(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        let language = try SpeechLanguagePolicy.resolve(ASRConfig(
            kind: .whisperKit, whisperModel: String(id.dropFirst("whisperkit:".count)), language: hints.language ?? ""
        )).language
        let pipe = try await loadedPipe()
        let started = Date()
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.detectLanguage = language == nil
        options.temperature = 0
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = false
        options.windowClipTime = 0
        options.chunkingStrategy = nil
        options.noSpeechThreshold = nil
        var detectedLanguage: String?
        let text = try await AudioChunker.transcribeAsync(samples, maxSeconds: 25) { chunk in
            let results = try await pipe.transcribe(audioArray: chunk, decodeOptions: options)
            if detectedLanguage == nil { detectedLanguage = results.first?.language }
            return results.map(\.text).joined(separator: " ")
        }
        return Transcript(text: text, language: detectedLanguage, engine: id,
                          latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// Whisper's language distribution for the first 30 seconds: one encoder pass
    /// and one decoder step over the language tokens, the same computation as its
    /// automatic detection, keeping every probability instead of only the winner.
    public func spokenLanguageProbabilities(samples: [Float]) async throws -> [String: Double]? {
        let pipe = try await loadedPipe()
        guard pipe.textDecoder.isModelMultilingual, let tokenizer = pipe.tokenizer else { return nil }
        try Task.checkCancellation()
        let window = pipe.featureExtractor.windowSamples ?? 480_000
        guard let audio = pipe.audioProcessor.padOrTrim(fromArray: Array(samples.prefix(window)), startAt: 0, toLength: window),
              let mel = try await pipe.featureExtractor.logMelSpectrogram(fromAudio: audio),
              let encoded = try await pipe.audioEncoder.encodeFeatures(mel) else { return nil }
        try Task.checkCancellation()
        let inputs = try pipe.textDecoder.prepareDecoderInputs(withPrompt: [tokenizer.specialTokens.startOfTranscriptToken])
        let languageTokens = tokenizer.allLanguageTokens
        let sampler = LanguageDistributionSampler(languageTokens: languageTokens, eotToken: tokenizer.specialTokens.endToken)
        _ = try await pipe.textDecoder.detectLanguage(from: encoded, using: inputs, sampler: sampler,
                                                      options: DecodingOptions(), temperature: 0)
        try Task.checkCancellation()
        var result: [String: Double] = [:]
        for (token, probability) in sampler.probabilities {
            let code = tokenizer.decode(tokens: [token])
                .trimmingCharacters(in: CharacterSet(charactersIn: "<|>").union(.whitespaces))
            if !code.isEmpty { result[code] = probability }
        }
        return result.isEmpty ? nil : result
    }
}

/// Records the softmax over Whisper's language tokens, then defers to greedy
/// sampling so the decoder's own state is unchanged.
private final class LanguageDistributionSampler: TokenSampling, Sendable {
    private let languageTokens: Set<Int>
    private let greedy: Mutex<GreedySamplerBox>
    private let recorded = Mutex<[Int: Double]>([:])

    init(languageTokens: Set<Int>, eotToken: Int) {
        self.languageTokens = languageTokens
        greedy = Mutex(GreedySamplerBox(GreedyTokenSampler(temperature: 0, eotToken: eotToken, decodingOptions: DecodingOptions())))
    }

    var probabilities: [Int: Double] { recorded.withLock { $0 } }

    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        var values: [(Int, Double)] = []
        for token in languageTokens where token < logits.count {
            let value = logits[token].doubleValue
            if value.isFinite { values.append((token, value)) }
        }
        if let maximum = values.map(\.1).max() {
            let exps = values.map { ($0.0, Foundation.exp($0.1 - maximum)) }
            let total = exps.reduce(0) { $0 + $1.1 }
            recorded.withLock { stored in for (token, value) in exps { stored[token] = value / total } }
        }
        let sampler = greedy.withLock { $0.sampler }
        return await sampler.update(tokens: tokens, logits: logits, logProbs: logProbs)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        greedy.withLock { $0.sampler }.finalize(tokens: tokens, logProbs: logProbs)
    }
}

/// GreedyTokenSampler is a non-Sendable class; this box confines it to the
/// sampler's Mutex, and the sampler is used by one decoder call at a time.
private struct GreedySamplerBox: @unchecked Sendable {
    let sampler: GreedyTokenSampler
    init(_ sampler: GreedyTokenSampler) { self.sampler = sampler }
}
