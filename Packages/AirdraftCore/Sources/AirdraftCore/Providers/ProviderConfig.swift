import Foundation

public enum ASRProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case qwen3
    case fireRed
    case cohere
    case senseVoice
    case whisperKit
    case apple
    case openAICompatible
    case openAI
    case openRouter
    case groq
    case elevenLabs
    case deepgram
    case soniox
    public var id: String { rawValue }
    public var isLocal: Bool {
        switch self {
        case .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox: return false
        default: return true
        }
    }
    public var preset: EndpointPreset.Speech? { EndpointPreset.asr.first { $0.kind == self } }
}

/// Where refinement runs. Cloud providers are native: each speaks its own API
/// with its own key, so nothing depends on a compatibility shim.
public enum LLMProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Any OpenAI-compatible server you host: LM Studio, Ollama, vLLM, custom.
    case openAICompatible
    case openAI
    case anthropic
    case gemini
    case openRouter
    case cerebras
    case groq
    /// A coding-agent CLI already installed and logged in on this Mac; the
    /// user's own subscription pays for it, so there is no API key.
    case claudeCode
    case codex
    /// Insert the raw transcript.
    case none

    public var id: String { rawValue }

    /// Request shape the provider speaks.
    public enum Wire: Sendable { case openAIChat, anthropicMessages, geminiGenerateContent, cli }

    public var wire: Wire {
        switch self {
        case .anthropic: return .anthropicMessages
        case .gemini: return .geminiGenerateContent
        case .claudeCode, .codex: return .cli
        default: return .openAIChat
        }
    }

    /// The CLI this provider drives, if any.
    public var cliTool: CLIRefiner.Tool? {
        switch self {
        case .claudeCode: return .claudeCode
        case .codex: return .codex
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .openAICompatible: return "Local / self-hosted"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .cerebras: return "Cerebras"
        case .groq: return "Groq"
        case .claudeCode: return "Claude Code CLI"
        case .codex: return "Codex CLI"
        case .none: return "Off"
        }
    }

    /// Compact name for the menu bar.
    public var shortTitle: String {
        switch self {
        case .openAICompatible: return "Local"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .cerebras: return "Cerebras"
        case .groq: return "Groq"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .none: return "Off"
        }
    }

    public var isCloud: Bool {
        switch self {
        case .openAI, .anthropic, .gemini, .openRouter, .cerebras, .groq: return true
        case .openAICompatible, .claudeCode, .codex, .none: return false
        }
    }

    /// Runs a local CLI instead of talking to an endpoint.
    public var isCLI: Bool { cliTool != nil }

    public var defaultBaseURL: String {
        switch self {
        case .openAICompatible: return "http://localhost:1234/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .claudeCode, .codex: return ""
        case .none: return ""
        }
    }

    /// Starting point only; the model picker lists what the endpoint actually serves.
    public var defaultModel: String {
        switch self {
        case .openAICompatible: return "google/gemma-4-26b-a4b-qat"
        case .openAI: return "gpt-4.1-mini"
        case .anthropic: return "claude-haiku-4-5-20251001"
        case .gemini: return "gemini-2.5-flash"
        case .openRouter: return "google/gemini-2.5-flash"
        case .cerebras: return "qwen-3.8-27b"
        case .groq: return "openai/gpt-oss-20b"
        // Empty means "whatever the CLI itself is set to".
        case .claudeCode: return "sonnet"
        case .codex: return "gpt-6-astra"
        case .none: return ""
        }
    }

    /// Keychain account holding this provider's key.
    public var keyRef: String {
        switch self {
        case .openAICompatible: return "llm.lmstudio"
        case .openAI: return "llm.openai"
        case .anthropic: return "llm.anthropic"
        case .gemini: return "llm.gemini"
        case .openRouter: return "llm.openrouter"
        case .cerebras: return "llm.cerebras"
        case .groq: return "llm.groq"
        case .claudeCode, .codex: return ""
        case .none: return ""
        }
    }

    /// Where the user creates a key, linked from the key field.
    public var keyConsoleURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .cerebras: return URL(string: "https://cloud.cerebras.ai")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .openAICompatible, .claudeCode, .codex, .none: return nil
        }
    }

    /// Cloud keys are required; a local server usually needs none.
    public var requiresKey: Bool { isCloud }
}

/// How much the model may think before answering. Dictation cleanup is a simple
/// task, so the default is the cheapest setting the provider offers; the models
/// that default to deep reasoning are otherwise seconds slower per dictation.
public enum ThinkingEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra high"
        case .max: return "Max"
        case .ultra: return "Ultra"
        }
    }

    /// Level name for providers that take one; `off` has no level of its own.
    var levelName: String { self == .off ? "low" : rawValue }

    /// Existing HTTP providers keep their original controls. CLI capabilities
    /// come from the installed CLI's model catalogue instead.
    public static let standard: [Self] = [.off, .low, .medium, .high]

    static func cliValue(_ value: String) -> Self? {
        value == "none" ? .off : Self(rawValue: value)
    }

    /// Preserve the request when supported; otherwise use the closest lower
    /// level, or the model's minimum when thinking cannot be disabled.
    public func supported(in levels: [Self]) -> Self? {
        let ordered = Self.allCases.filter { levels.contains($0) }
        guard !ordered.isEmpty else { return nil }
        let rank = Self.allCases.firstIndex(of: self)!
        return ordered.last { Self.allCases.firstIndex(of: $0)! <= rank } ?? ordered.first
    }
}

public enum ChineseScript: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Leave whatever the engines produce.
    case auto
    /// Bias ASR and LLM toward Traditional Chinese and convert any leftovers.
    case traditional
    /// Same, toward Simplified Chinese.
    case simplified
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .traditional: return "繁體中文"
        case .simplified: return "简体中文"
        }
    }
}

public struct ASRConfig: Codable, Sendable, Equatable {
    public var kind: ASRProviderKind
    /// WhisperKit variant name.
    public var whisperModel: String
    /// Hugging Face id of the Qwen3-ASR MLX weights.
    public var qwen3Model: String
    /// Hugging Face id of the Cohere Transcribe MLX weights.
    public var cohereModel: String
    /// BCP-47 locale for Apple speech recognition.
    public var appleLocale: String
    /// Kept for compatibility with older Scribe settings.
    public var elevenLabsModel: String
    public var baseURL: String
    public var model: String
    /// Last selected file-transcription model for each cloud provider.
    public var modelByProvider: [String: String]
    /// ISO 639-1 or empty for auto-detect.
    public var language: String
    public var chineseScript: ChineseScript
    /// Keychain account name holding the API key.
    public var apiKeyRef: String

    public init(
        kind: ASRProviderKind = .whisperKit,
        whisperModel: String = "large-v3-v20240930_turbo",
        qwen3Model: String = "aufklarer/Qwen3-ASR-1.7B-MLX-5bit",
        cohereModel: String = "aufklarer/Cohere-Transcribe-2B-MLX-5bit",
        appleLocale: String = "zh-TW",
        elevenLabsModel: String = "scribe_v2",
        baseURL: String = "https://api.openai.com/v1",
        model: String = "gpt-transcribe",
        modelByProvider: [String: String] = [:],
        language: String = "",
        chineseScript: ChineseScript = .traditional,
        apiKeyRef: String = "asr.openai"
    ) {
        self.kind = kind
        self.whisperModel = whisperModel
        self.qwen3Model = qwen3Model
        self.cohereModel = cohereModel
        self.appleLocale = appleLocale
        self.elevenLabsModel = elevenLabsModel
        self.baseURL = baseURL
        self.model = model
        self.modelByProvider = modelByProvider
        self.language = language
        self.chineseScript = chineseScript
        self.apiKeyRef = apiKeyRef
    }

    // Older settings blobs lack the new keys; decode them leniently.
    private enum CodingKeys: String, CodingKey {
        case kind, whisperModel, qwen3Model, cohereModel, appleLocale, elevenLabsModel, baseURL, model, modelByProvider, language, chineseScript, apiKeyRef
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ASRConfig()
        kind = try c.decodeIfPresent(ASRProviderKind.self, forKey: .kind) ?? defaults.kind
        whisperModel = try c.decodeIfPresent(String.self, forKey: .whisperModel) ?? defaults.whisperModel
        qwen3Model = try c.decodeIfPresent(String.self, forKey: .qwen3Model) ?? defaults.qwen3Model
        cohereModel = try c.decodeIfPresent(String.self, forKey: .cohereModel) ?? defaults.cohereModel
        appleLocale = try c.decodeIfPresent(String.self, forKey: .appleLocale) ?? defaults.appleLocale
        elevenLabsModel = try c.decodeIfPresent(String.self, forKey: .elevenLabsModel) ?? defaults.elevenLabsModel
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        modelByProvider = try c.decodeIfPresent([String: String].self, forKey: .modelByProvider) ?? [:]
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        chineseScript = try c.decodeIfPresent(ChineseScript.self, forKey: .chineseScript) ?? defaults.chineseScript
        apiKeyRef = try c.decodeIfPresent(String.self, forKey: .apiKeyRef) ?? defaults.apiKeyRef
        // Migrate only the exact built-in endpoints and credentials. A custom
        // server or key reference must never be redirected to a different service.
        if kind == .openAICompatible {
            let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if endpoint == "https://api.openai.com/v1", apiKeyRef == "asr.openai" {
                kind = .openAI
            } else if endpoint == "https://api.groq.com/openai/v1", apiKeyRef == "asr.groq" {
                kind = .groq
            }
        }
        if kind == .elevenLabs, !ModelCatalog.transcriptionModels(for: kind).contains(model) {
            model = elevenLabsModel
        }
        if kind.preset != nil, let current = selectedSpeechModel { selectModel(current.id) }
    }

    /// Identity of the engine this config selects. Equal to the `id` of the
    /// transcriber EngineFactory builds for it, so the UI can look up load state.
    public var effectiveAppleLocale: String {
        AppleSpeechTranscriber.locale(forLanguage: language) ?? appleLocale
    }

    public var engineID: String {
        switch kind {
        case .whisperKit: return "whisperkit:\(whisperModel)"
        case .qwen3: return "qwen3-asr:\(qwen3Model)"
        case .cohere: return "cohere-transcribe:\(cohereModel)"
        case .fireRed: return "sherpa-onnx:fireRed"
        case .senseVoice: return "sherpa-onnx:senseVoice"
        case .apple: return "apple-speech:\(effectiveAppleLocale)"
        case .elevenLabs: return "elevenlabs:\(speechModelID)"
        case .openAI, .openRouter, .groq, .deepgram, .soniox:
            return "\(kind.rawValue):\(speechModelID)"
        case .openAICompatible: return "openai-compatible:\(URL(string: baseURL)?.host ?? "?")/\(model)"
        }
    }

    /// Built-in providers always use their own credential and endpoint.
    public var keyRef: String { kind.preset?.keyRef ?? apiKeyRef }

    /// The selected cloud model's id, falling back to the stored id if the catalogue no longer lists it.
    public var speechModelID: String { selectedSpeechModel?.id ?? model }

    public var selectedSpeechModel: SpeechModelInfo? {
        let choices = SpeechModelInfo.models(for: kind)
        if let choice = choices.first(where: { $0.id == model }) { return choice }
        if kind == .openRouter, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return OpenRouterSpeechCatalog.placeholder(id: model)
        }
        return choices.first
    }

    public mutating func selectModel(_ id: String) {
        if kind == .openRouter {
            let selected = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else { return }
            model = selected
            modelByProvider[kind.rawValue] = selected
            return
        }
        guard let choice = SpeechModelInfo.models(for: kind).first(where: { $0.id == id }) else { return }
        model = choice.id
        modelByProvider[kind.rawValue] = choice.id
        if kind == .elevenLabs { elevenLabsModel = choice.id }
    }

    public mutating func select(_ provider: ASRProviderKind) {
        if let current = selectedSpeechModel { modelByProvider[kind.rawValue] = current.id }
        kind = provider
        if let preset = provider.preset {
            baseURL = preset.baseURL
            model = modelByProvider[provider.rawValue] ?? preset.defaultModel
            apiKeyRef = preset.keyRef
            selectModel(speechModelID)
        }
    }

    public var engineLabel: String {
        switch kind {
        case .whisperKit: return "WhisperKit · \(whisperModel)"
        case .qwen3: return "Qwen3-ASR · \((qwen3Model as NSString).lastPathComponent)"
        case .fireRed: return "FireRedASR2-AED"
        case .cohere: return "Cohere Transcribe · \((cohereModel as NSString).lastPathComponent)"
        case .senseVoice: return "SenseVoice-small"
        case .apple: return "Apple Speech · \(appleLocale)"
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox:
            return "\(kind.preset?.name ?? kind.rawValue) · \(selectedSpeechModel?.title ?? model)"
        case .openAICompatible: return "\(URL(string: baseURL)?.host ?? baseURL) · \(model)"
        }
    }
}

public struct LLMConfig: Codable, Sendable, Equatable {
    public var kind: LLMProviderKind
    /// Endpoint of the local / self-hosted server. Cloud providers use their own.
    public var baseURL: String
    public var model: String
    /// Last model used per provider, so switching providers back and forth keeps each choice.
    public var modelByProvider: [String: String]
    /// Resolved executable path per CLI provider, so a non-standard install is only found once.
    public var cliPaths: [String: String]
    /// Keychain account for the local / self-hosted server (cloud keys come from the provider).
    public var apiKeyRef: String
    public var temperature: Double
    public var timeoutSeconds: Double
    /// Utterances shorter than this skip the LLM entirely.
    public var minWordsForLLM: Int
    public var thinkingEffort: ThinkingEffort
    public var effortByProvider: [String: ThinkingEffort]
    public var openRouterRoutingByModel: [String: OpenRouterRouting]

    public var openRouterRouting: OpenRouterRouting {
        get { openRouterRoutingByModel[model] ?? OpenRouterRouting() }
        set { openRouterRoutingByModel[model] = newValue }
    }

    public init(
        kind: LLMProviderKind = .openAICompatible,
        baseURL: String = LLMProviderKind.openAICompatible.defaultBaseURL,
        model: String = LLMProviderKind.openAICompatible.defaultModel,
        modelByProvider: [String: String] = [:],
        cliPaths: [String: String] = [:],
        apiKeyRef: String = LLMProviderKind.openAICompatible.keyRef,
        temperature: Double = 0.2,
        timeoutSeconds: Double = 20,
        minWordsForLLM: Int = 3,
        thinkingEffort: ThinkingEffort = .off,
        effortByProvider: [String: ThinkingEffort] = [:],
        openRouterRoutingByModel: [String: OpenRouterRouting] = [:]
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.modelByProvider = modelByProvider
        self.cliPaths = cliPaths
        self.apiKeyRef = apiKeyRef
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.minWordsForLLM = minWordsForLLM
        self.thinkingEffort = thinkingEffort
        self.effortByProvider = effortByProvider
        self.openRouterRoutingByModel = openRouterRoutingByModel
    }

    private enum CodingKeys: String, CodingKey {
        case kind, baseURL, model, modelByProvider, cliPaths, apiKeyRef, temperature, timeoutSeconds, minWordsForLLM, thinkingEffort, effortByProvider
        case openRouterRoutingByModel
        /// Removed setting, still read from older stored configs.
        case disableThinking
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LLMConfig()
        kind = try c.decodeIfPresent(LLMProviderKind.self, forKey: .kind) ?? d.kind
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        modelByProvider = try c.decodeIfPresent([String: String].self, forKey: .modelByProvider) ?? d.modelByProvider
        cliPaths = try c.decodeIfPresent([String: String].self, forKey: .cliPaths) ?? d.cliPaths
        apiKeyRef = try c.decodeIfPresent(String.self, forKey: .apiKeyRef) ?? d.apiKeyRef
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? d.temperature
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds
        minWordsForLLM = try c.decodeIfPresent(Int.self, forKey: .minWordsForLLM) ?? d.minWordsForLLM
        effortByProvider = try c.decodeIfPresent([String: ThinkingEffort].self, forKey: .effortByProvider) ?? [:]
        openRouterRoutingByModel = try c.decodeIfPresent([String: OpenRouterRouting].self, forKey: .openRouterRoutingByModel) ?? [:]
        // Migrates the old on/off switch: thinking disabled becomes effort off.
        if let effort = try c.decodeIfPresent(ThinkingEffort.self, forKey: .thinkingEffort) {
            thinkingEffort = effort
        } else if let disabled = try c.decodeIfPresent(Bool.self, forKey: .disableThinking) {
            thinkingEffort = disabled ? .off : .high
        } else {
            thinkingEffort = d.thinkingEffort
        }
        // Only the exact former built-in Groq preset is migrated. Custom URLs
        // and credential references remain untouched.
        if kind == .openAICompatible, baseURL == LLMProviderKind.groq.defaultBaseURL,
           apiKeyRef == LLMProviderKind.groq.keyRef {
            kind = .groq
            baseURL = LLMProviderKind.openAICompatible.defaultBaseURL
            apiKeyRef = LLMProviderKind.openAICompatible.keyRef
        }
    }

    /// Endpoint actually used: the editable one for a local server, the provider's own for cloud.
    public var endpoint: URL? {
        URL(string: kind.isCloud ? kind.defaultBaseURL : baseURL)
    }

    /// Keychain account holding the key for the selected provider.
    public var keyRef: String { kind.isCloud ? kind.keyRef : apiKeyRef }

    /// Executable for the selected CLI provider: the stored path, else wherever it is installed.
    public var cliExecutable: String? {
        guard let tool = kind.cliTool else { return nil }
        if let stored = cliPaths[kind.rawValue], FileManager.default.isExecutableFile(atPath: stored) { return stored }
        return tool.locate()
    }

    /// Switches provider, remembering the model chosen for the one being left.
    public mutating func select(_ newKind: LLMProviderKind) {
        guard newKind != kind else { return }
        modelByProvider[kind.rawValue] = model
        effortByProvider[kind.rawValue] = thinkingEffort
        kind = newKind
        model = modelByProvider[newKind.rawValue] ?? newKind.defaultModel
        thinkingEffort = effortByProvider[newKind.rawValue] ?? .off
        if newKind == .openAICompatible, baseURL.isEmpty { baseURL = newKind.defaultBaseURL }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(model, forKey: .model)
        try c.encode(modelByProvider, forKey: .modelByProvider)
        try c.encode(cliPaths, forKey: .cliPaths)
        try c.encode(apiKeyRef, forKey: .apiKeyRef)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try c.encode(minWordsForLLM, forKey: .minWordsForLLM)
        try c.encode(thinkingEffort, forKey: .thinkingEffort)
        try c.encode(effortByProvider, forKey: .effortByProvider)
        try c.encode(openRouterRoutingByModel, forKey: .openRouterRoutingByModel)
    }

    public var engineLabel: String {
        switch kind {
        case .none: return "Off"
        case .openAICompatible: return "\(endpoint?.host ?? baseURL) · \(model)"
        case .claudeCode, .codex: return "\(kind.title) · \(model.isEmpty ? "default model" : model)"
        default: return "\(kind.title) · \(model)"
        }
    }
}

/// One-click endpoint presets shown in Settings. Keys are never stored here.
public struct EndpointPreset: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let baseURL: String
    public let defaultModel: String
    public let keyRef: String

    /// Local / self-hosted servers for the OpenAI-compatible kind.
    public static let llm: [EndpointPreset] = [
        .init(name: "LM Studio (local)", baseURL: LLMProviderKind.openAICompatible.defaultBaseURL,
              defaultModel: LLMProviderKind.openAICompatible.defaultModel, keyRef: LLMProviderKind.openAICompatible.keyRef),
        .init(name: "Ollama (local)", baseURL: "http://localhost:11434/v1", defaultModel: "qwen3:8b", keyRef: "llm.ollama"),
        .init(name: "Custom", baseURL: "http://localhost:8000/v1", defaultModel: "", keyRef: "llm.custom"),
    ]

    /// Curated file-transcription APIs. OpenRouter rates vary by model and
    /// billing unit; its preset deliberately does not quote an hourly price.
    public struct Speech: Identifiable, Sendable, Equatable {
        public var id: String { kind.rawValue }
        public let kind: ASRProviderKind
        public let name: String
        public let modelTitle: String
        public let baseURL: String
        public var defaultModel: String { ModelCatalog.transcriptionModels(for: kind)[0] }
        public let keyRef: String
        public let purpose: String
        public let detail: String
        public let price: String
        public let billingNote: String
        public let consoleURL: URL
        public let pricingURL: URL
    }

    public static let asr: [Speech] = [
        .init(kind: .soniox, name: "Soniox", modelTitle: "v5", baseURL: "https://api.soniox.com/v1",
              keyRef: "asr.soniox", purpose: "Value & mixed languages",
              detail: "60+ languages, including Chinese and English in the same sentence.", price: "~$0.10/hr",
              billingNote: "Token-based estimate. Dictionary context can add cost. Uploaded audio and jobs are deleted after use when the API is reachable.",
              consoleURL: URL(string: "https://console.soniox.com")!, pricingURL: URL(string: "https://soniox.com/pricing")!),
        .init(kind: .groq, name: "Groq", modelTitle: "Whisper v3 Turbo", baseURL: "https://api.groq.com/openai/v1",
              keyRef: "asr.groq", purpose: "Speed & lowest cost",
              detail: "Fast inference for short dictation; trades some accuracy for speed.", price: "$0.04/hr",
              billingNote: "10-second minimum billed per request. Inference speed does not include upload or network time.",
              consoleURL: URL(string: "https://console.groq.com/keys")!, pricingURL: URL(string: "https://console.groq.com/docs/speech-to-text")!),
        .init(kind: .elevenLabs, name: "ElevenLabs", modelTitle: "Scribe v2", baseURL: "https://api.elevenlabs.io/v1",
              keyRef: "asr.elevenlabs", purpose: "Broad language coverage",
              detail: "Quality-focused transcription across 90+ languages and varied accents.", price: "$0.22/hr",
              billingNote: "Base API rate. Paid keyterm prompting and audio-event tags are off; your dictionary still applies after refinement.",
              consoleURL: URL(string: "https://elevenlabs.io/app/developers/api-keys")!, pricingURL: URL(string: "https://elevenlabs.io/pricing/api")!),
        .init(kind: .openAI, name: "OpenAI", modelTitle: "GPT-Transcribe", baseURL: "https://api.openai.com/v1",
              keyRef: "asr.openai", purpose: "Names & technical vocabulary",
              detail: "Uses your dictionary as keyword hints with the current transcription model.", price: "$0.27/hr",
              billingNote: "$0.0045 per audio minute. Replaces the older GPT-4o transcription preset.",
              consoleURL: URL(string: "https://platform.openai.com/api-keys")!, pricingURL: URL(string: "https://developers.openai.com/api/docs/pricing")!),
        .init(kind: .openRouter, name: "OpenRouter", modelTitle: "Whisper 1", baseURL: "https://openrouter.ai/api/v1",
              keyRef: "llm.openrouter", purpose: "Choose a hosted speech model",
              detail: "Transcribes audio through OpenRouter's speech endpoint with a separate speech model choice.", price: "Varies by model",
              billingNote: "Models have different billing units. Check the selected model's OpenRouter page before use.",
              consoleURL: URL(string: "https://openrouter.ai/keys")!, pricingURL: URL(string: "https://openrouter.ai/models?output_modalities=transcription")!),
        .init(kind: .deepgram, name: "Deepgram", modelTitle: "Nova-3", baseURL: "https://api.deepgram.com/v1",
              keyRef: "asr.deepgram", purpose: "Noisy audio & formatting",
              detail: "Smart punctuation, dates and numbers. Auto-detects the dominant language.", price: "$0.258/hr",
              billingNote: "Pre-recorded monolingual rate. Auto-detect chooses one language; use Soniox for code-switching. Paid keyterm prompting is off.",
              consoleURL: URL(string: "https://console.deepgram.com")!, pricingURL: URL(string: "https://deepgram.com/pricing")!),
    ]

    public static let elevenLabsKeyRef = "asr.elevenlabs"
}
