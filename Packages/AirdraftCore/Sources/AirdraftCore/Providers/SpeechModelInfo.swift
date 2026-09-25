import Foundation

/// Curated file-transcription choices from provider documentation.
/// Quality/speed describe published evidence, not a cross-provider benchmark.
public struct SpeechModelInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let price: String
    public let billing: String
    public let quality: String
    public let qualityDetail: String
    public let speed: String
    public let speedDetail: String
    public let documentationURL: URL
    public var realtimeSpeedFactor: Double? = nil
    public var wordErrorRate: Double? = nil

    public static func models(for provider: ASRProviderKind) -> [Self] {
        let unpublished = "The provider does not publish comparable file-transcription latency. Upload and network time also affect your wait."
        switch provider {
        case .openRouter:
            return [
                .init(id: "openai/whisper-1", title: "Whisper 1", price: "See pricing",
                      billing: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.",
                      quality: "General speech", qualityDetail: "The model used in OpenRouter's transcription API example.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/openai/whisper-1")!),
                .init(id: "openai/whisper-large-v3-turbo", title: "Whisper Large v3 Turbo", price: "See pricing",
                      billing: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.",
                      quality: "General speech", qualityDetail: "A hosted Whisper Large v3 Turbo option for comparing recognition on your own audio.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/openai/whisper-large-v3-turbo")!),
                .init(id: "openai/gpt-transcribe", title: "GPT-Transcribe", price: "See pricing",
                      billing: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.",
                      quality: "General speech", qualityDetail: "A hosted GPT-Transcribe option for comparing recognition on your own audio.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/openai/gpt-transcribe")!),
                .init(id: "qwen/qwen3-asr-1.7b", title: "Qwen3-ASR 1.7B", price: "See pricing",
                      billing: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.",
                      quality: "Multilingual", qualityDetail: "The model page lists 30 languages and 22 Chinese dialects.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/qwen/qwen3-asr-1.7b")!)
            ]
        case .openAI:
            return [
                .init(id: "gpt-transcribe", title: "GPT-Transcribe", price: "$0.27/hr",
                      billing: "$0.0045 per audio minute.", quality: "High accuracy",
                      qualityDetail: "Keyword hints from your dictionary and mixed-language recognition.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://developers.openai.com/api/docs/models/gpt-transcribe")!),
                .init(id: "gpt-4o-mini-transcribe", title: "GPT-4o Mini Transcribe", price: "≈$0.18/hr",
                      billing: "Token-based estimate of $0.003 per minute; actual cost varies with audio and output.",
                      quality: "Improved vs Whisper", qualityDetail: "OpenAI reports improved word error rate and language recognition over original Whisper models, at a lower price than GPT-4o Transcribe.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://developers.openai.com/api/docs/models/gpt-4o-mini-transcribe")!),
                .init(id: "gpt-4o-transcribe", title: "GPT-4o Transcribe", price: "≈$0.36/hr",
                      billing: "Token-based estimate of $0.006 per minute; actual cost varies with audio and output.",
                      quality: "Improved vs Whisper", qualityDetail: "Improved recognition over original Whisper; accepts dictionary context as a text prompt.",
                      speed: "Not published", speedDetail: unpublished,
                      documentationURL: URL(string: "https://developers.openai.com/api/docs/models/gpt-4o-transcribe")!)
            ]
        case .groq:
            let docs = URL(string: "https://console.groq.com/docs/speech-to-text")!
            let billing = "10-second minimum billed per request. USD per audio hour."
            let benchmark = "Groq's published inference benchmark; excludes upload and network time. Results vary with audio."
            return [
                .init(id: "whisper-large-v3-turbo", title: "Whisper Large v3 Turbo", price: "$0.04/hr", billing: billing,
                      quality: "12% word error", qualityDetail: "Groq's benchmark. Faster and cheaper than Large v3, with a higher error rate.",
                      speed: "216× real time", speedDetail: benchmark, documentationURL: docs,
                      realtimeSpeedFactor: 216, wordErrorRate: 12),
                .init(id: "whisper-large-v3", title: "Whisper Large v3", price: "$0.111/hr", billing: billing,
                      quality: "10.3% word error", qualityDetail: "Groq's benchmark. Lower error rate than Turbo; costs more per hour.",
                      speed: "189× real time", speedDetail: benchmark, documentationURL: docs,
                      realtimeSpeedFactor: 189, wordErrorRate: 10.3)
            ]
        case .elevenLabs:
            let docs = URL(string: "https://elevenlabs.io/docs/overview/models")!
            let billing = "Published base API rate. Paid keyterm and entity-detection add-ons are off."
            return [
                .init(id: "scribe_v2", title: "Scribe v2", price: "$0.22/hr", billing: billing,
                      quality: "90+ languages", qualityDetail: "General speech recognition across varied languages and accents.",
                      speed: "Not published", speedDetail: unpublished, documentationURL: docs),
                .init(id: "scribe_v2_medical", title: "Scribe v2 Medical", price: "$0.22/hr", billing: billing,
                      quality: "Clinical vocabulary", qualityDetail: "Specialized for clinical terms, medication names and medical dictation.",
                      speed: "Not published", speedDetail: unpublished, documentationURL: docs)
            ]
        case .deepgram:
            let docs = URL(string: "https://developers.deepgram.com/docs/models-languages-overview")!
            let speed = "Deepgram states its non-Whisper models return results faster than its Whisper models. No comparable latency is published."
            return [
                .init(id: "nova-3", title: "Nova-3 · Single language", price: "$0.258/hr",
                      billing: "Pre-recorded pay-as-you-go: $0.0043 per minute. Optional add-ons are off.",
                      quality: "Noisy audio", qualityDetail: "Designed for noisy and far-field speech. Auto-detects one language; supports Mandarin.",
                      speed: "Faster than Whisper", speedDetail: speed, documentationURL: docs),
                .init(id: "nova-3-multilingual", title: "Nova-3 · Multilingual", price: "$0.312/hr",
                      billing: "Pre-recorded pay-as-you-go: $0.0052 per minute. This is Nova-3 with multilingual mode enabled.",
                      quality: "Mixed languages", qualityDetail: "Switches between EN, ES, FR, DE, HI, RU, PT, JA, IT and NL. Mandarin is not supported in this mode; the Language setting is ignored.",
                      speed: "Faster than Whisper", speedDetail: speed, documentationURL: docs),
                .init(id: "whisper-large", title: "Whisper Large", price: "$0.288/hr",
                      billing: "Pre-recorded pay-as-you-go: $0.0048 per minute. Deepgram hosts Whisper Large v2.",
                      quality: "Broad language support", qualityDetail: "An alternative recognition model to compare against Nova-3 for your recordings.",
                      speed: "Slower than Nova-3", speedDetail: speed, documentationURL: docs)
            ]
        case .soniox:
            return [.init(id: "stt-async-v5", title: "Soniox v5", price: "≈$0.10/hr",
                          billing: "Token-based estimate. Dictionary context can add cost. Audio and jobs are deleted after use when the API is reachable.",
                          quality: "Mixed languages", qualityDetail: "Recognizes language switches within speech, including Chinese and English.",
                          speed: "Not published", speedDetail: "Asynchronous processing adds job scheduling and polling. " + unpublished,
                          documentationURL: URL(string: "https://soniox.com/docs/stt/models")!)]
        default: return []
        }
    }
}
