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
            return "Enable Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence preparing · check System Settings", bundle: .module)
        case .unavailable: return String(localized: "Unavailable · check Apple Intelligence in System Settings", bundle: .module)
        }
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
        let cleaned = PromptBuilder.sanitize(text)
        guard !cleaned.isEmpty else { throw RefinerError.emptyOutput }
        return RefineResult(text: cleaned, engine: id,
                            latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                            promptVersion: PromptBuilder.version)
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
