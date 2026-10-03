import Foundation

/// A profile remembers only its speech engine selection. Language, script and
/// credentials remain shared; a custom server retains its endpoint and key reference.
public struct ProfileSpeechModel: Codable, Sendable, Equatable, Hashable {
    public let kind: ASRProviderKind
    public let model: String
    public let baseURL: String?
    public let apiKeyRef: String?

    public init(config: ASRConfig) {
        kind = config.kind
        switch kind {
        case .qwen3: model = config.qwen3Model
        case .cohere: model = config.cohereModel
        case .whisperKit: model = config.whisperModel
        case .apple, .parakeet, .fireRed, .senseVoice: model = ""
        default: model = config.model
        }
        baseURL = kind == .openAICompatible ? config.baseURL : nil
        apiKeyRef = kind == .openAICompatible ? config.apiKeyRef : nil
    }

    public func applying(to appDefault: ASRConfig) -> ASRConfig {
        var config = appDefault
        config.select(kind)
        switch kind {
        case .qwen3: config.qwen3Model = model
        case .cohere: config.cohereModel = model
        case .whisperKit: config.whisperModel = model
        case .apple, .parakeet, .fireRed, .senseVoice: break
        default:
            config.model = model
            if kind == .elevenLabs { config.elevenLabsModel = model }
        }
        if kind == .openAICompatible {
            config.baseURL = baseURL ?? appDefault.baseURL
            config.apiKeyRef = apiKeyRef ?? appDefault.apiKeyRef
        }
        return config
    }

    /// Never silently substitute a catalogue default for a retired binding.
    public var unavailableReason: String? {
        guard kind.preset != nil, kind != .openRouter,
              !SpeechModelInfo.models(for: kind).contains(where: { $0.id == model }) else { return nil }
        return "This profile's speech model is no longer available. Choose another model or Use App Default in Profiles."
    }
}
