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

public protocol Refiner: Sendable {
    var id: String { get }
    func refine(_ request: RefineRequest) async throws -> RefineResult
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
            return "Refinement provider returned HTTP \(status)\(detail)"
        case .invalidResponse: return "The refinement provider returned an unexpected response."
        case .incompleteOutput: return "The refinement response was incomplete. The original transcript was kept."
        case .emptyOutput: return "The refinement provider returned empty text."
        case .timeout: return "Refinement timed out."
        }
    }
}
