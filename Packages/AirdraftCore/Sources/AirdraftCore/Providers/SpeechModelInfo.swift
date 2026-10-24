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
        let unpublished = String(localized: "The provider does not publish comparable file-transcription latency. Upload and network time also affect your wait.", bundle: .module)
        switch provider {
        case .openRouter:
            return [
                .init(id: "openai/whisper-1", title: "Whisper 1", price: String(localized: "See pricing", bundle: .module),
                      billing: String(localized: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.", bundle: .module),
                      quality: String(localized: "General speech", bundle: .module), qualityDetail: String(localized: "The model used in OpenRouter's transcription API example.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/openai/whisper-1")!),
                .init(id: "openai/whisper-large-v3-turbo", title: "Whisper Large v3 Turbo", price: String(localized: "See pricing", bundle: .module),
                      billing: String(localized: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.", bundle: .module),
                      quality: String(localized: "General speech", bundle: .module), qualityDetail: String(localized: "A hosted Whisper Large v3 Turbo option for comparing recognition on your own audio.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/openai/whisper-large-v3-turbo")!),
                .init(id: "openai/gpt-transcribe", title: "GPT-Transcribe", price: String(localized: "See pricing", bundle: .module),
                      billing: String(localized: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.", bundle: .module),
                      quality: String(localized: "General speech", bundle: .module), qualityDetail: String(localized: "A hosted GPT-Transcribe option for comparing recognition on your own audio.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/openai/gpt-transcribe")!),
                .init(id: "qwen/qwen3-asr-1.7b", title: "Qwen3-ASR 1.7B", price: String(localized: "See pricing", bundle: .module),
                      billing: String(localized: "OpenRouter lists this model's current price on its model page. Check the billing unit before use.", bundle: .module),
                      quality: String(localized: "Multilingual", bundle: .module), qualityDetail: String(localized: "The model page lists 30 languages and 22 Chinese dialects.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://openrouter.ai/qwen/qwen3-asr-1.7b")!)
            ]
        case .openAI:
            return [
                .init(id: "gpt-transcribe", title: "GPT-Transcribe", price: "$0.27/hr",
                      billing: String(localized: "$0.0045 per audio minute.", bundle: .module), quality: String(localized: "High accuracy", bundle: .module),
                      qualityDetail: String(localized: "Keyword hints from your dictionary and mixed-language recognition.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://developers.openai.com/api/docs/models/gpt-transcribe")!),
                .init(id: "gpt-4o-mini-transcribe", title: "GPT-4o Mini Transcribe", price: "≈$0.18/hr",
                      billing: String(localized: "Token-based estimate of $0.003 per minute; actual cost varies with audio and output.", bundle: .module),
                      quality: String(localized: "Improved vs Whisper", bundle: .module), qualityDetail: String(localized: "OpenAI reports improved word error rate and language recognition over original Whisper models, at a lower price than GPT-4o Transcribe.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://developers.openai.com/api/docs/models/gpt-4o-mini-transcribe")!),
                .init(id: "gpt-4o-transcribe", title: "GPT-4o Transcribe", price: "≈$0.36/hr",
                      billing: String(localized: "Token-based estimate of $0.006 per minute; actual cost varies with audio and output.", bundle: .module),
                      quality: String(localized: "Improved vs Whisper", bundle: .module), qualityDetail: String(localized: "Improved recognition over original Whisper; accepts dictionary context as a text prompt.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                      documentationURL: URL(string: "https://developers.openai.com/api/docs/models/gpt-4o-transcribe")!)
            ]
        case .groq:
            let docs = URL(string: "https://console.groq.com/docs/speech-to-text")!
            let billing = String(localized: "10-second minimum billed per request. USD per audio hour.", bundle: .module)
            let benchmark = String(localized: "Groq's published inference benchmark; excludes upload and network time. Results vary with audio.", bundle: .module)
            return [
                .init(id: "whisper-large-v3-turbo", title: "Whisper Large v3 Turbo", price: "$0.04/hr", billing: billing,
                      quality: String(localized: "12% word error", bundle: .module), qualityDetail: String(localized: "Groq's benchmark. Faster and cheaper than Large v3, with a higher error rate.", bundle: .module),
                      speed: String(localized: "216× real time", bundle: .module), speedDetail: benchmark, documentationURL: docs,
                      realtimeSpeedFactor: 216, wordErrorRate: 12),
                .init(id: "whisper-large-v3", title: "Whisper Large v3", price: "$0.111/hr", billing: billing,
                      quality: String(localized: "10.3% word error", bundle: .module), qualityDetail: String(localized: "Groq's benchmark. Lower error rate than Turbo; costs more per hour.", bundle: .module),
                      speed: String(localized: "189× real time", bundle: .module), speedDetail: benchmark, documentationURL: docs,
                      realtimeSpeedFactor: 189, wordErrorRate: 10.3)
            ]
        case .elevenLabs:
            let docs = URL(string: "https://elevenlabs.io/docs/overview/models")!
            let billing = String(localized: "Published base API rate. Paid keyterm and entity-detection add-ons are off.", bundle: .module)
            return [
                .init(id: "scribe_v2", title: "Scribe v2", price: "$0.22/hr", billing: billing,
                      quality: String(localized: "90+ languages", bundle: .module), qualityDetail: String(localized: "General speech recognition across varied languages and accents.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished, documentationURL: docs),
                .init(id: "scribe_v2_medical", title: "Scribe v2 Medical", price: "$0.22/hr", billing: billing,
                      quality: String(localized: "Clinical vocabulary", bundle: .module), qualityDetail: String(localized: "Specialized for clinical terms, medication names and medical dictation.", bundle: .module),
                      speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished, documentationURL: docs)
            ]
        case .deepgram:
            let docs = URL(string: "https://developers.deepgram.com/docs/models-languages-overview")!
            let speed = String(localized: "Deepgram states its non-Whisper models return results faster than its Whisper models. No comparable latency is published.", bundle: .module)
            return [
                .init(id: "nova-3", title: "Nova-3 · Single language", price: "$0.258/hr",
                      billing: String(localized: "Pre-recorded pay-as-you-go: $0.0043 per minute. Optional add-ons are off.", bundle: .module),
                      quality: String(localized: "Noisy audio", bundle: .module), qualityDetail: String(localized: "Designed for noisy and far-field speech. Auto-detects one language.", bundle: .module),
                      speed: String(localized: "Faster than Whisper", bundle: .module), speedDetail: speed, documentationURL: docs),
                .init(id: "nova-3-multilingual", title: "Nova-3 · Multilingual", price: "$0.312/hr",
                      billing: String(localized: "Pre-recorded pay-as-you-go: $0.0052 per minute. This is Nova-3 with multilingual mode enabled.", bundle: .module),
                      quality: String(localized: "Mixed languages", bundle: .module), qualityDetail: String(localized: "Switches between EN, ES, FR, DE, HI, RU, PT, JA, IT and NL; the Language setting is ignored.", bundle: .module),
                      speed: String(localized: "Faster than Whisper", bundle: .module), speedDetail: speed, documentationURL: docs),
                .init(id: "whisper-large", title: "Whisper Large", price: "$0.288/hr",
                      billing: String(localized: "Pre-recorded pay-as-you-go: $0.0048 per minute. Deepgram hosts Whisper Large v2.", bundle: .module),
                      quality: String(localized: "Broad language support", bundle: .module), qualityDetail: String(localized: "An alternative recognition model to compare against Nova-3 for your recordings.", bundle: .module),
                      speed: String(localized: "Slower than Nova-3", bundle: .module), speedDetail: speed, documentationURL: docs)
            ]
        case .soniox:
            return [.init(id: "stt-async-v5", title: "Soniox v5", price: "≈$0.10/hr",
                          billing: String(localized: "Token-based estimate. Dictionary context can add cost. Audio and jobs are deleted after use when the API is reachable.", bundle: .module),
                          quality: String(localized: "Mixed languages", bundle: .module), qualityDetail: String(localized: "Recognizes language switches within speech.", bundle: .module),
                          speed: String(localized: "Not published", bundle: .module), speedDetail: String(localized: "Asynchronous processing adds job scheduling and polling.", bundle: .module) + " " + unpublished,
                          documentationURL: URL(string: "https://soniox.com/docs/stt/models")!)]
        case .assemblyAI:
            return [.init(id: "universal-3-5-pro", title: "Universal-3.5 Pro", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://www.assemblyai.com/dashboard", quality: String(localized: "18 languages", bundle: .module),
                          qualityDetail: String(localized: "Includes Mandarin and English code-switching; uses dictionary keyterms.", bundle: .module), speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://www.assemblyai.com/docs/pre-recorded-audio/select-the-speech-model")!),
                    .init(id: "universal-3-6-pro-preview", title: "Universal-3.6 Pro (Preview)", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://www.assemblyai.com/dashboard", quality: String(localized: "Batch preview", bundle: .module),
                          qualityDetail: String(localized: "Pre-recorded preview. Language coverage and accuracy have not been verified.", bundle: .module),
                          speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://www.assemblyai.com/roadmap")!)]
        case .cartesia:
            return [.init(id: "ink-whisper", title: "Ink-Whisper", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://play.cartesia.ai/keys", quality: String(localized: "Broad language coverage", bundle: .module),
                          qualityDetail: String(localized: "File recognition with an explicit language. Streaming-only models are separate.", bundle: .module), speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://docs.cartesia.ai/api-reference/stt/transcribe")!)]
        case .speechmatics:
            return [.init(id: "enhanced", title: "Enhanced", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://portal.speechmatics.com", quality: String(localized: "Custom vocabulary", bundle: .module),
                          qualityDetail: String(localized: "Batch recognition with dictionary terms. Automatic detection selects the predominant language.", bundle: .module), speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://docs.speechmatics.com/speech-to-text/batch/quickstart")!)]
        case .xAI:
            return [.init(id: "grok-voice-transcribe-2.0", title: "Grok Voice Transcribe 2.0", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://console.x.ai", quality: String(localized: "Multilingual", bundle: .module),
                          qualityDetail: String(localized: "Automatic language detection and native keyterm hints.", bundle: .module), speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://docs.x.ai/developers/model-capabilities/audio/speech-to-text")!)]
        case .mistral:
            return [.init(id: "voxtral-mini-latest", title: "Voxtral Mini Transcribe", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://console.mistral.ai/api-keys", quality: String(localized: "13 languages", bundle: .module),
                          qualityDetail: String(localized: "Voxtral Mini transcription with an optional language hint.", bundle: .module), speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription")!)]
        case .gemini:
            return [.init(id: "gemini-3.5-transcribe", title: "Gemini 3.5 Transcribe", price: String(localized: "See pricing", bundle: .module),
                          billing: "https://aistudio.google.com/api-keys", quality: String(localized: "Verbatim & multilingual", bundle: .module),
                          qualityDetail: String(localized: "Preserves fillers and repetitions; supports native custom vocabulary. Refinement remains independent.", bundle: .module), speed: String(localized: "Not published", bundle: .module), speedDetail: unpublished,
                          documentationURL: URL(string: "https://ai.google.dev/gemini-api/docs/transcribe")!)]
        default: return []
        }
    }
}
