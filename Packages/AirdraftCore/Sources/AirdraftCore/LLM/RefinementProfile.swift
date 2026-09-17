import Foundation

/// One way of turning a transcript into text: a name, whether it calls the
/// LLM, an optional TASK line that leads the prompt, and the instructions
/// that follow the shared base rules. Built-ins can be edited and reset;
/// user profiles can be added and deleted.
public struct RefinementProfile: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    /// SF Symbol shown in menus.
    public var symbol: String
    public var usesLLM: Bool
    /// Leads the system prompt when the output is not a cleaned transcript
    /// (summaries, translations). Empty for plain cleanup profiles.
    public var task: String
    /// Profile-specific rules, appended after the shared base rules.
    public var instructions: String
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "sparkles",
        usesLLM: Bool = true,
        task: String = "",
        instructions: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.usesLLM = usesLLM
        self.task = task
        self.instructions = instructions
        self.isBuiltIn = isBuiltIn
    }

    // Stable ids so the active selection survives resets and upgrades.
    public static let cleanID = UUID(uuidString: "6B1F0C1E-0000-4000-8000-000000000001")!
    public static let conciseID = UUID(uuidString: "6B1F0C1E-0000-4000-8000-000000000002")!
    public static let summaryID = UUID(uuidString: "6B1F0C1E-0000-4000-8000-000000000003")!
    public static let verbatimID = UUID(uuidString: "6B1F0C1E-0000-4000-8000-000000000004")!

    public static let defaults: [RefinementProfile] = [
        RefinementProfile(
            id: cleanID,
            name: "Clean",
            symbol: "sparkles",
            instructions: "Keep the speaker's wording and length. Do not condense or rephrase beyond what the cleanup rules require.",
            isBuiltIn: true
        ),
        RefinementProfile(
            id: conciseID,
            name: "Concise",
            symbol: "text.line.first.and.arrowtriangle.forward",
            instructions: "Keep every point but tighten the wording; aim for roughly two-thirds of the original length. Remove hedging, redundancy, and repeated ideas. Never drop names, numbers, decisions, action items, or the closing question or request.",
            isBuiltIn: true
        ),
        RefinementProfile(
            id: summaryID,
            name: "Summary",
            symbol: "list.bullet",
            task: "Summarize the transcript as bullet points; the cleaned transcript itself must not appear in the output.",
            instructions: "Output ONLY a bullet-point summary of what was said (3 to 7 bullets, each one complete idea). Preserve decisions, numbers, names, and action items. No heading, no preamble, no closing line; the bullets are the entire output.",
            isBuiltIn: true
        ),
        RefinementProfile(
            id: verbatimID,
            name: "Verbatim",
            symbol: "text.quote",
            usesLLM: false,
            instructions: "",
            isBuiltIn: true
        ),
    ]

    public static func defaultProfile(id: UUID) -> RefinementProfile? {
        defaults.first { $0.id == id }
    }
}
