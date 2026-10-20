import Foundation

public struct RefineRequest: Sendable {
    public var transcript: String
    public var profile: RefinementProfile
    public var baseRules: String
    public var context: AppContext
    public var family: AppFamily
    public var dictionary: [DictionaryEntry]
    public var chineseScript: ChineseScript

    public init(
        transcript: String,
        profile: RefinementProfile,
        baseRules: String = PromptBuilder.defaultBaseRules,
        context: AppContext,
        family: AppFamily,
        dictionary: [DictionaryEntry],
        chineseScript: ChineseScript = .auto
    ) {
        self.transcript = transcript
        self.profile = profile
        self.baseRules = baseRules
        self.context = context
        self.family = family
        self.dictionary = dictionary
        self.chineseScript = chineseScript
    }
}

public struct RefineResult: Sendable, Equatable {
    public var text: String
    public var engine: String
    public var latencyMs: Int
    public var promptVersion: String
    /// Server-side instance id, or the host selected by OpenRouter when reported.
    public var servedBy: String?

    public init(text: String, engine: String, latencyMs: Int, promptVersion: String, servedBy: String? = nil) {
        self.text = text
        self.engine = engine
        self.latencyMs = latencyMs
        self.promptVersion = promptVersion
        self.servedBy = servedBy
    }
}

/// A fresh model-lifecycle probe determines whether speculative local work is
/// supported. A generic/cloud endpoint must never receive an extra inference.
public enum RefinementPreparationBackend: Sendable, Equatable {
    case unmanaged
    case lmStudio
}

public protocol Refiner: Sendable {
    var id: String { get }
    func prepare(_ request: RefineRequest, backend: RefinementPreparationBackend, owner: UUID) async throws -> any Refiner
    func prewarmPrompt(_ request: RefineRequest, backend: RefinementPreparationBackend) async throws
    func refine(_ request: RefineRequest) async throws -> RefineResult
}

extension Refiner {
    public func prepare(_ request: RefineRequest, backend: RefinementPreparationBackend, owner: UUID) async throws -> any Refiner {
        try Task.checkCancellation()
        return self
    }

    /// Optional work has its own task; callers can cancel it when final speech
    /// arrives without spending the refinement deadline waiting for prefill.
    public func prewarmPrompt(_ request: RefineRequest, backend: RefinementPreparationBackend) async throws {
        try Task.checkCancellation()
    }
}

public enum RefinerError: Error, LocalizedError {
    case http(status: Int, body: String)
    case invalidResponse
    case incompleteOutput
    case emptyOutput
    case timeout

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            let detail = ProviderErrorBody.summary(body).map { ": \($0)" } ?? "."
            return String(localized: "Refinement provider returned HTTP \(status)\(detail)", bundle: .module)
        case .invalidResponse: return String(localized: "The refinement provider returned an unexpected response.", bundle: .module)
        case .incompleteOutput: return String(localized: "The refinement response was incomplete. The original transcript was kept.", bundle: .module)
        case .emptyOutput: return String(localized: "The refinement provider returned empty text.", bundle: .module)
        case .timeout: return String(localized: "Refinement timed out.", bundle: .module)
        }
    }
}
