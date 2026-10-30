import Foundation
import FoundationModels

/// Apple's system model runs entirely on this Mac. Each dictation gets a new
/// session so one app's context can never carry into another dictation.
public struct AppleIntelligenceRefiner: Refiner {
    public let id = "apple-intelligence:system"
    private let timeout: TimeInterval
    private let availability: @Sendable () -> String?
    private let generate: @Sendable (String, String) async throws -> String

    public init(timeout: TimeInterval = 20) {
        self.init(timeout: timeout, availability: { Self.unavailableReason }, generate: Self.generate)
    }

    init(timeout: TimeInterval, availability: @escaping @Sendable () -> String?,
         generate: @escaping @Sendable (String, String) async throws -> String) {
        self.timeout = timeout
        self.availability = availability
        self.generate = generate
    }

    /// The system's own availability, as a value that setup can explain in plain words.
    public enum Availability: String, Sendable, CaseIterable {
        case available, requiresNewerSystem, deviceNotEligible, notEnabled, modelNotReady, unavailable
    }

    public static var availability: Availability {
        guard #available(macOS 26, *) else { return .requiresNewerSystem }
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable(.modelNotReady): return .modelNotReady
        case .unavailable: return .unavailable
        }
    }

    public static var unavailableReason: String? {
        guard #available(macOS 26, *) else { return String(localized: "Apple Intelligence requires macOS 26 or later.", bundle: .module) }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return String(localized: "This Mac does not support Apple Intelligence.", bundle: .module)
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Enable Apple Intelligence in System Settings.", bundle: .module)
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence preparing · check System Settings", bundle: .module)
        case .unavailable: return String(localized: "Unavailable · check Apple Intelligence in System Settings", bundle: .module)
        }
    }

    /// The name of the language Apple Intelligence cannot write for this setup, or
    /// nil when it can or Airdraft cannot tell. The language is the selected speech
    /// language, or the first preferred language under Auto. Refinement still runs:
    /// an unsupported language tends to come back unchanged or refused, which keeps
    /// the raw transcript, so setup says so instead of offering it as the answer.
    public static func unsupportedLanguageName(for config: ASRConfig,
                                               preferredLanguages: [String] = SystemLanguages.preferred) -> String? {
        guard #available(macOS 26, *) else { return nil }
        let supported = Set(SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier })
        return unsupportedLanguageName(for: config, preferredLanguages: preferredLanguages, supported: supported)
    }

    static func unsupportedLanguageName(for config: ASRConfig, preferredLanguages: [String],
                                        supported: Set<String>) -> String? {
        guard !supported.isEmpty else { return nil }
        let selected = config.kind == .apple ? config.effectiveAppleLocale : config.language
        let explicit = (try? SpeechLanguagePolicy.canonicalLanguage(selected)) ?? nil
        let fallback = preferredLanguages.lazy.compactMap { (try? SpeechLanguagePolicy.canonicalLanguage($0)) ?? nil }.first
        guard let code = explicit ?? fallback else { return nil }
        // Cantonese and Hong Kong speech are written in Chinese characters.
        let written = ["yue", "zh-hk"].contains(code) ? "zh" : code
        return supported.contains(written) ? nil : SpeechLanguagePolicy.languageName(code)
    }

    public func refine(_ request: RefineRequest) async throws -> RefineResult {
        if let message = availability() { throw RecordingPrerequisiteError(message) }
        let started = Date()
        let instructions = PromptBuilder.systemPrompt(for: request)
        let prompt = PromptBuilder.userMessage(for: request)
        let text = try await OperationDeadline.run(seconds: timeout) {
            try await generate(instructions, prompt)
        }
        try Task.checkCancellation()
        let cleaned = Self.droppingLoneBullet(PromptBuilder.sanitize(text))
        guard !cleaned.isEmpty else { throw RefinerError.emptyOutput }
        return RefineResult(text: cleaned, engine: id,
                            latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                            promptVersion: PromptBuilder.version)
    }

    /// A one-item "list": the system model started 3 of 24 QA-set refinements of
    /// plain prose with "- " (AD-118). A real list keeps its bullets.
    static func droppingLoneBullet(_ text: String) -> String {
        let markers = ["- ", "* ", "• "]
        guard let marker = markers.first(where: { text.hasPrefix($0) }) else { return text }
        let rest = text.components(separatedBy: "\n").dropFirst()
        guard rest.allSatisfy({ line in !markers.contains { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) } }) else {
            return text
        }
        return String(text.dropFirst(marker.count))
    }

    private static func generate(instructions: String, prompt: String) async throws -> String {
        guard #available(macOS 26, *) else {
            throw RecordingPrerequisiteError(String(localized: "Apple Intelligence requires macOS 26 or later.", bundle: .module))
        }
        let session = LanguageModelSession(model: .default, instructions: instructions)
        // No output cap: hitting a cap could silently insert half a dictation.
        // Context limits, refusals and generation errors use the raw-text fallback.
        return try await session.respond(to: prompt, options: GenerationOptions(samplingMode: .greedy)).content
    }
}
