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

    public static var unavailableReason: String? {
        guard #available(macOS 26, *) else { return "Apple Intelligence requires macOS 26 or later." }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings, or choose another refinement provider."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing its model. Try again after its download finishes in System Settings."
        case .unavailable: return "Apple Intelligence is unavailable. Check System Settings or choose another provider."
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
            throw RecordingPrerequisiteError("Apple Intelligence requires macOS 26 or later.")
        }
        let session = LanguageModelSession(model: .default, instructions: instructions)
        // No output cap: hitting a cap could silently insert half a dictation.
        // Context limits, refusals and generation errors use the raw-text fallback.
        return try await session.respond(to: prompt, options: GenerationOptions(samplingMode: .greedy)).content
    }
}
