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
    /// Server-side instance id that answered (LM Studio reports it in `model`).
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
    case emptyOutput
    case timeout

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "LLM API returned HTTP \(status): \(body.prefix(300))"
        case .invalidResponse: return "LLM API returned an unexpected response."
        case .emptyOutput: return "LLM returned empty text."
        case .timeout: return "LLM call timed out."
        }
    }
}
