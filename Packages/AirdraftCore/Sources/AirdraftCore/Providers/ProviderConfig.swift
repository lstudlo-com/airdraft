import Foundation

public enum ASRProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case qwen3
    case fireRed
    case cohere
    case senseVoice
    case parakeet
    case whisperKit
    case fluidAudio
    case orukeet
    case transcribeCpp
    case apple
    case openAICompatible
    case openAI
    case openRouter
    case groq
    case elevenLabs
    case deepgram
    case soniox
    case assemblyAI
    case cartesia
    case speechmatics
    case xAI
    case mistral
    case gemini
    public var id: String { rawValue }
    public var isLocal: Bool {
        switch self {
        case .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini: return false
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
    /// Apple's on-device system language model (macOS 26+).
    case appleIntelligence
    /// Insert the raw transcript.
    case none

    public var id: String { rawValue }

    /// Request shape the provider speaks.
    public enum Wire: Sendable { case openAIChat, anthropicMessages, geminiGenerateContent, cli, appleIntelligence }

    public var wire: Wire {
        switch self {
        case .appleIntelligence: return .appleIntelligence
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
        case .openAICompatible: return String(localized: "Local / self-hosted", bundle: .module)
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .cerebras: return "Cerebras"
        case .groq: return "Groq"
        case .claudeCode: return "Claude Code CLI"
        case .codex: return "Codex CLI"
        case .appleIntelligence: return "Apple Intelligence"
        case .none: return String(localized: "Off", bundle: .module)
        }
    }

    /// Compact name for the menu bar.
    public var shortTitle: String {
        switch self {
        case .openAICompatible: return String(localized: "Local", bundle: .module)
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .cerebras: return "Cerebras"
        case .groq: return "Groq"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .appleIntelligence: return "Apple Intelligence"
        case .none: return String(localized: "Off", bundle: .module)
        }
    }

    public var isCloud: Bool {
        switch self {
        case .openAI, .anthropic, .gemini, .openRouter, .cerebras, .groq: return true
        case .openAICompatible, .claudeCode, .codex, .appleIntelligence, .none: return false
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
        case .appleIntelligence, .none: return ""
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
        case .appleIntelligence, .none: return ""
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
        case .appleIntelligence, .none: return ""
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
        case .openAICompatible, .claudeCode, .codex, .appleIntelligence, .none: return nil
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
        case .off: return String(localized: "Off", bundle: .module)
        case .minimal: return String(localized: "Minimal", bundle: .module)
        case .low: return String(localized: "Low", bundle: .module)
        case .medium: return String(localized: "Medium", bundle: .module)
        case .high: return String(localized: "High", bundle: .module)
        case .xhigh: return String(localized: "Extra high", bundle: .module)
        case .max: return String(localized: "Max", bundle: .module)
        case .ultra: return String(localized: "Ultra", bundle: .module)
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
        case .auto: return String(localized: "Auto", bundle: .module)
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
        case .fluidAudio: return "fluidaudio:\(model)"
        case .orukeet: return "sherpa-onnx:orukeet"
        case .transcribeCpp: return "transcribe-cpp:\(model)"
        case .whisperKit: return "whisperkit:\(whisperModel)"
        case .qwen3: return "qwen3-asr:\(qwen3Model)"
        case .cohere: return "cohere-transcribe:\(cohereModel)"
        case .fireRed: return "sherpa-onnx:fireRed"
        case .senseVoice: return "sherpa-onnx:senseVoice"
        case .parakeet: return "sherpa-onnx:parakeet"
        case .apple: return "apple-speech:\(effectiveAppleLocale)"
        case .elevenLabs: return "elevenlabs:\(speechModelID)"
        case .openAI, .openRouter, .groq, .deepgram, .soniox, .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini:
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
        case .fluidAudio: return CoreMLSpeechModelCatalog.model(model)?.title ?? "Choose a Core ML speech model"
        case .orukeet: return "Orukeet"
        case .transcribeCpp: return GGUFModelCatalog.model(model)?.title ?? "Choose a local speech model"
        case .whisperKit: return "WhisperKit · \(whisperModel)"
        case .qwen3: return "Qwen3-ASR · \((qwen3Model as NSString).lastPathComponent)"
        case .fireRed: return "FireRedASR2-AED"
        case .cohere: return "Cohere Transcribe · \((cohereModel as NSString).lastPathComponent)"
        case .senseVoice: return "SenseVoice-small"
        case .parakeet: return "Parakeet TDT v3"
        case .apple: return "Apple Speech · \(appleLocale)"
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini:
            return "\(kind.preset?.name ?? kind.rawValue) · \(selectedSpeechModel?.title ?? model)"
        case .openAICompatible: return "\(URL(string: baseURL)?.host ?? baseURL) · \(model)"
        }
    }

    /// Readable catalogue name of the selected speech model, matching the
    /// titles in Models. Unknown or custom models fall back to their raw ID.
    public var modelDisplayName: String {
        switch kind {
        case .fluidAudio: return CoreMLSpeechModelCatalog.model(model)?.title ?? model
        case .orukeet: return "Orukeet"
        case .transcribeCpp: return GGUFModelCatalog.model(model)?.title ?? model
        case .whisperKit: return WhisperModelVariant(rawValue: whisperModel)?.title ?? "Whisper \(whisperModel)"
        case .qwen3:
            switch qwen3Model {
            case "aufklarer/Qwen3-ASR-1.7B-MLX-5bit": return "Qwen3-ASR 1.7B"
            case "aufklarer/Qwen3-ASR-0.6B-MLX-4bit": return "Qwen3-ASR 0.6B"
            default: return (qwen3Model as NSString).lastPathComponent
            }
        case .fireRed: return "FireRedASR2"
        case .cohere:
            return cohereModel == "aufklarer/Cohere-Transcribe-2B-MLX-5bit"
                ? "Cohere Transcribe" : (cohereModel as NSString).lastPathComponent
        case .senseVoice: return "SenseVoice"
        case .parakeet: return "Parakeet TDT v3"
        case .apple: return "Apple Speech"
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini:
            return selectedSpeechModel?.title ?? model
        case .openAICompatible: return model.isEmpty ? String(localized: "Custom server", bundle: .module) : model
        }
    }

    /// Runtime of a local model, or who hosts a cloud model. Same-family
    /// variants (Core ML, GGUF and MLX builds) stay distinguishable with it.
    public var modelSource: String? {
        switch kind {
        case .qwen3, .cohere: return "MLX"
        case .fireRed, .senseVoice, .parakeet, .orukeet: return "ONNX"
        case .whisperKit, .fluidAudio: return "Core ML"
        case .transcribeCpp: return GGUFModelCatalog.model(model).map { "GGUF \($0.quantization)" } ?? "GGUF"
        case .apple: return nil
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini:
            return kind.preset?.name
        case .openAICompatible: return URL(string: baseURL)?.host ?? String(localized: "Custom server", bundle: .module)
        }
    }

    /// User-facing model label: readable name plus runtime or host. Raw
    /// identifiers stay in `engineLabel` for tooltips and diagnostics.
    public var displayName: String {
        guard let source = modelSource, !source.isEmpty, source != modelDisplayName else { return modelDisplayName }
        return "\(modelDisplayName) · \(source)"
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
        guard kind != .appleIntelligence && kind != .none && !kind.isCLI else { return nil }
        return URL(string: kind.isCloud ? kind.defaultBaseURL : baseURL)
    }

    /// Keychain account holding the key for the selected provider.
    public var keyRef: String { kind == .appleIntelligence || kind == .none || kind.isCLI ? "" : (kind.isCloud ? kind.keyRef : apiKeyRef) }

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
        case .appleIntelligence: return "Apple Intelligence"
        case .none: return String(localized: "Off", bundle: .module)
        case .openAICompatible: return "\(endpoint?.host ?? baseURL) · \(model)"
        case .claudeCode, .codex: return "\(kind.title) · \(model.isEmpty ? String(localized: "default model", bundle: .module) : model)"
        default: return "\(kind.title) · \(model)"
        }
    }

    /// Who serves refinement: a known local server by name, a custom
    /// server by host, otherwise the provider's compact title.
    public var providerDisplayName: String {
        guard kind == .openAICompatible else { return kind.shortTitle }
        let host = endpoint?.host ?? baseURL
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let preset = EndpointPreset.llm.first(where: {
            $0.name != "Custom" && $0.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) == normalized
        }) {
            return preset.name.replacingOccurrences(of: " (local)", with: "")
        }
        return host.isEmpty ? kind.title : host
    }

    /// Readable model name; the raw ID stays in `engineLabel`.
    public var modelDisplayName: String {
        if model.trimmingCharacters(in: .whitespaces).isEmpty { return kind.isCLI ? String(localized: "Default model", bundle: .module) : "" }
        return Self.readableModelName(model)
    }

    /// Provider plus readable model, for summaries such as Home.
    public var displayName: String {
        switch kind {
        case .appleIntelligence, .none: return kind.title
        default:
            let name = modelDisplayName
            return name.isEmpty ? providerDisplayName : "\(providerDisplayName) · \(name)"
        }
    }

    /// Turns a provider model ID into a readable name without a catalogue:
    /// `google/gemma-4-26b-a4b-qat` → `Gemma 4 26B A4B QAT`,
    /// `claude-haiku-4-5-20251001` → `Claude Haiku 4.5`. Mixed-case IDs and
    /// IDs that yield nothing readable are returned unchanged.
    public static func readableModelName(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        guard !base.isEmpty, base == base.lowercased() else { return base.isEmpty ? trimmed : base }
        var tokens = base.split(whereSeparator: { "-_: ".contains($0) }).map(String.init)
        // Release dates and floating tags identify a snapshot, not the model.
        while let last = tokens.last, tokens.count > 1,
              last == "latest" || (last.count == 8 && last.allSatisfy(\.isNumber)) {
            tokens.removeLast()
        }
        // Split major-minor versions such as `4-5` back into `4.5`.
        var merged: [String] = []
        for token in tokens {
            if let previous = merged.last, previous.count == 1, previous.allSatisfy(\.isNumber),
               token.count == 1, token.allSatisfy(\.isNumber) {
                merged[merged.count - 1] = "\(previous).\(token)"
            } else {
                merged.append(token)
            }
        }
        let acronyms: Set<String> = ["gpt", "oss", "qat", "mlx", "gguf", "awq", "it", "asr", "tts", "vl", "moe"]
        func word(_ token: String) -> String {
            if acronyms.contains(token) { return token.uppercased() }
            // Parameter counts (26b, 1.5b, 270m) and active-expert tags (a4b, e4b).
            if token.range(of: #"^(\d+(\.\d+)?|[a-z]\d+(\.\d+)?)[bmkt]$"#, options: .regularExpression) != nil {
                return token.uppercased()
            }
            if token.range(of: #"^[a-z]+\d+(\.\d+)?$"#, options: .regularExpression) != nil
                || token.range(of: #"^[a-z]+$"#, options: .regularExpression) != nil {
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            return token
        }
        var words: [String] = []
        for token in merged {
            let next = word(token)
            // GPT joins its version or variant with a hyphen: GPT-4.1, GPT-OSS.
            if words.last == "GPT" { words[words.count - 1] = "GPT-\(next)" } else { words.append(next) }
        }
        let name = words.joined(separator: " ")
        return name.isEmpty ? trimmed : name
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
        .init(name: String(localized: "LM Studio (local)", bundle: .module), baseURL: LLMProviderKind.openAICompatible.defaultBaseURL,
              defaultModel: LLMProviderKind.openAICompatible.defaultModel, keyRef: LLMProviderKind.openAICompatible.keyRef),
        .init(name: String(localized: "Ollama (local)", bundle: .module), baseURL: "http://localhost:11434/v1", defaultModel: "qwen3:8b", keyRef: "llm.ollama"),
        .init(name: String(localized: "Custom", bundle: .module), baseURL: "http://localhost:8000/v1", defaultModel: "", keyRef: "llm.custom"),
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
              detail: String(localized: "60+ languages, including Chinese and English in the same sentence.", bundle: .module), price: "~$0.10/hr",
              billingNote: String(localized: "Token-based estimate. Dictionary context can add cost. Uploaded audio and jobs are deleted after use when the API is reachable.", bundle: .module),
              consoleURL: URL(string: "https://console.soniox.com")!, pricingURL: URL(string: "https://soniox.com/pricing")!),
        .init(kind: .groq, name: "Groq", modelTitle: "Whisper v3 Turbo", baseURL: "https://api.groq.com/openai/v1",
              keyRef: "asr.groq", purpose: "Speed & lowest cost",
              detail: String(localized: "Fast inference for short dictation; trades some accuracy for speed.", bundle: .module), price: "$0.04/hr",
              billingNote: String(localized: "10-second minimum billed per request. Inference speed does not include upload or network time.", bundle: .module),
              consoleURL: URL(string: "https://console.groq.com/keys")!, pricingURL: URL(string: "https://console.groq.com/docs/speech-to-text")!),
        .init(kind: .elevenLabs, name: "ElevenLabs", modelTitle: "Scribe v2", baseURL: "https://api.elevenlabs.io/v1",
              keyRef: "asr.elevenlabs", purpose: "Broad language coverage",
              detail: String(localized: "Quality-focused transcription across 90+ languages and varied accents.", bundle: .module), price: "$0.22/hr",
              billingNote: String(localized: "Base API rate. Paid keyterm prompting and audio-event tags are off; your dictionary still applies after refinement.", bundle: .module),
              consoleURL: URL(string: "https://elevenlabs.io/app/developers/api-keys")!, pricingURL: URL(string: "https://elevenlabs.io/pricing/api")!),
        .init(kind: .openAI, name: "OpenAI", modelTitle: "GPT-Transcribe", baseURL: "https://api.openai.com/v1",
              keyRef: "asr.openai", purpose: "Names & technical vocabulary",
              detail: String(localized: "Uses your dictionary as keyword hints with the current transcription model.", bundle: .module), price: "$0.27/hr",
              billingNote: String(localized: "$0.0045 per audio minute. Replaces the older GPT-4o transcription preset.", bundle: .module),
              consoleURL: URL(string: "https://platform.openai.com/api-keys")!, pricingURL: URL(string: "https://developers.openai.com/api/docs/pricing")!),
        .init(kind: .openRouter, name: "OpenRouter", modelTitle: "Whisper 1", baseURL: "https://openrouter.ai/api/v1",
              keyRef: "llm.openrouter", purpose: "Choose a hosted speech model",
              detail: String(localized: "Transcribes audio through OpenRouter's speech endpoint with a separate speech model choice.", bundle: .module), price: String(localized: "Varies by model", bundle: .module),
              billingNote: String(localized: "Models have different billing units. Check the selected model's OpenRouter page before use.", bundle: .module),
              consoleURL: URL(string: "https://openrouter.ai/keys")!, pricingURL: URL(string: "https://openrouter.ai/models?output_modalities=transcription")!),
        .init(kind: .deepgram, name: "Deepgram", modelTitle: "Nova-3", baseURL: "https://api.deepgram.com/v1",
              keyRef: "asr.deepgram", purpose: "Noisy audio & formatting",
              detail: String(localized: "Smart punctuation, dates and numbers. Auto-detects the dominant language.", bundle: .module), price: "$0.258/hr",
              billingNote: String(localized: "Pre-recorded monolingual rate. Auto-detect chooses one language; use Soniox for code-switching. Paid keyterm prompting is off.", bundle: .module),
              consoleURL: URL(string: "https://console.deepgram.com")!, pricingURL: URL(string: "https://deepgram.com/pricing")!),
        .init(kind: .assemblyAI, name: "AssemblyAI", modelTitle: "Universal Pro", baseURL: "https://api.assemblyai.com/v2",
              keyRef: "asr.assemblyai", purpose: "Batch accuracy & vocabulary",
              detail: String(localized: "Universal-3.5 Pro and Universal-3.6 Pro batch preview.", bundle: .module), price: String(localized: "See pricing", bundle: .module),
              billingNote: String(localized: "Job deletion is attempted after use. Uploads without a job follow provider retention.", bundle: .module),
              consoleURL: URL(string: "https://www.assemblyai.com/dashboard")!, pricingURL: URL(string: "https://www.assemblyai.com/pricing")!),
        .init(kind: .cartesia, name: "Cartesia", modelTitle: "Ink-Whisper", baseURL: "https://api.cartesia.ai",
              keyRef: "asr.cartesia", purpose: "File recognition with a chosen language",
              detail: String(localized: "Broad language coverage; select a speech language before recording.", bundle: .module), price: String(localized: "See pricing", bundle: .module),
              billingNote: String(localized: "Ink-Whisper is the file model. Auto Detect and streaming Ink-2 are unavailable here.", bundle: .module),
              consoleURL: URL(string: "https://play.cartesia.ai/keys")!, pricingURL: URL(string: "https://cartesia.ai/pricing")!),
        .init(kind: .speechmatics, name: "Speechmatics", modelTitle: "Enhanced", baseURL: "https://eu1.asr.api.speechmatics.com/v2",
              keyRef: "asr.speechmatics", purpose: "Batch recognition & custom vocabulary",
              detail: String(localized: "Enhanced recognition. Auto Detect chooses one predominant language.", bundle: .module), price: String(localized: "See pricing", bundle: .module),
              billingNote: String(localized: "Uses the EU batch endpoint. Job and audio deletion are attempted after use. Auto Detect works best with at least 60 seconds of speech.", bundle: .module),
              consoleURL: URL(string: "https://portal.speechmatics.com")!, pricingURL: URL(string: "https://www.speechmatics.com/pricing")!),
        .init(kind: .xAI, name: "xAI", modelTitle: "Grok Voice Transcribe 2.0", baseURL: "https://api.x.ai/v1",
              keyRef: "asr.xai", purpose: "Multilingual speech & keyterms",
              detail: String(localized: "Native transcription with automatic language detection and dictionary hints.", bundle: .module), price: String(localized: "See pricing", bundle: .module),
              billingNote: String(localized: "Audio is sent to xAI. Check current model pricing and account limits before use.", bundle: .module),
              consoleURL: URL(string: "https://console.x.ai")!, pricingURL: URL(string: "https://docs.x.ai/developers/model-capabilities/audio/speech-to-text")!),
        .init(kind: .mistral, name: "Mistral", modelTitle: "Voxtral Mini Transcribe", baseURL: "https://api.mistral.ai/v1",
              keyRef: "asr.mistral", purpose: "Compact multilingual transcription",
              detail: String(localized: "13 languages, including Mandarin, with optional language hints.", bundle: .module), price: String(localized: "See pricing", bundle: .module),
              billingNote: String(localized: "Uses Voxtral Mini Latest. Dictionary substitutions still apply after transcription.", bundle: .module),
              consoleURL: URL(string: "https://console.mistral.ai/api-keys")!, pricingURL: URL(string: "https://mistral.ai/pricing")!),
        .init(kind: .gemini, name: "Gemini", modelTitle: "Gemini 3.5 Transcribe", baseURL: "https://generativelanguage.googleapis.com/v1beta",
              keyRef: "asr.gemini", purpose: "Verbatim speech & vocabulary hints",
              detail: String(localized: "Dedicated transcription in verbatim mode, with automatic language detection.", bundle: .module), price: String(localized: "See pricing", bundle: .module),
              billingNote: String(localized: "Uses a separate speech key. Interaction storage is off; uploaded-file deletion is attempted after use.", bundle: .module),
              consoleURL: URL(string: "https://aistudio.google.com/api-keys")!, pricingURL: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!),
    ]

    public static let elevenLabsKeyRef = "asr.elevenlabs"
}
