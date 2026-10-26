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
    /// Nil follows the app's speech selection. Older profile files omit this key.
    public var speechModel: ProfileSpeechModel?
    /// The user typed this name, so it is shown exactly as typed, even when it
    /// equals a built-in's stored English name (AD-079). Older files omit the key.
    public var nameIsCustom = false
    /// Where this profile's text goes (AD-104). Nil follows Output and automation.
    public var output: ProfileOutput?
    /// Press Return after a confirmed paste with nothing flagged: for prompts to
    /// AI chats and agents. Never in browsers, email or chat apps (AD-104).
    public var sendsAutomatically = false

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, usesLLM, task, instructions, isBuiltIn, speechModel, nameIsCustom
        case output, sendsAutomatically
    }

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "sparkles",
        usesLLM: Bool = true,
        task: String = "",
        instructions: String,
        isBuiltIn: Bool = false,
        speechModel: ProfileSpeechModel? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.usesLLM = usesLLM
        self.task = task
        self.instructions = instructions
        self.isBuiltIn = isBuiltIn
        self.speechModel = speechModel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decode(String.self, forKey: .symbol)
        usesLLM = try container.decode(Bool.self, forKey: .usesLLM)
        task = try container.decode(String.self, forKey: .task)
        instructions = try container.decode(String.self, forKey: .instructions)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        speechModel = try container.decodeIfPresent(ProfileSpeechModel.self, forKey: .speechModel)
        nameIsCustom = try container.decodeIfPresent(Bool.self, forKey: .nameIsCustom) ?? false
        // Older files omit both; an unreadable output follows the app setting.
        output = (try? container.decodeIfPresent(ProfileOutput.self, forKey: .output)) ?? nil
        sendsAutomatically = try container.decodeIfPresent(Bool.self, forKey: .sendsAutomatically) ?? false
    }

    /// True when this profile's text goes to the cursor, its own choice or the app's.
    public func deliversToCursor(appDefault: TextOutputDestination) -> Bool {
        switch output?.kind {
        case nil: appDefault == .cursor
        case .cursor: true
        case .copy, .file: false
        }
    }

    public func speechConfig(default appDefault: ASRConfig) -> ASRConfig {
        speechModel?.applying(to: appDefault) ?? appDefault
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
            instructions: "Keep the speaker's wording and length while correcting recognition errors and applying cleanup. Do not condense or otherwise rephrase.",
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

    /// The name shown in the interface. A built-in keeps its stored English name, which
    /// prompts, history and persistence use, and shows it localized until the user
    /// renames it; every other name, and any name the user typed, is shown as typed.
    public var displayName: String { displayName(localizingBuiltIn: Self.localizedBuiltInName) }

    func displayName(localizingBuiltIn localize: (UUID) -> String?) -> String {
        guard isBuiltIn, !nameIsCustom, let builtIn = Self.defaultProfile(id: id), name == builtIn.name else { return name }
        return localize(id) ?? name
    }

    /// History saves the profile's name, not its id: an unrenamed built-in's stored
    /// name is shown localized and any other saved name as written.
    public static func displayName(forSavedName name: String) -> String {
        guard let builtIn = defaults.first(where: { $0.name == name }) else { return name }
        return localizedBuiltInName(id: builtIn.id) ?? name
    }

    static func localizedBuiltInName(id: UUID) -> String? {
        switch id {
        case cleanID: String(localized: "Clean", bundle: .module, comment: "Built-in refinement profile name")
        case conciseID: String(localized: "Concise", bundle: .module, comment: "Built-in refinement profile name")
        case summaryID: String(localized: "Summary", bundle: .module, comment: "Built-in refinement profile name")
        case verbatimID: String(localized: "Verbatim", bundle: .module, comment: "Built-in refinement profile name")
        default: nil
        }
    }
}

/// A profile's own destination (AD-104). The file path may contain `{date}`,
/// `{time}` and `{app}`; nothing else, and never anything a model wrote.
public struct ProfileOutput: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case cursor, copy, file
        public var id: String { rawValue }
    }
    public var kind: Kind
    public var filePath: String

    public init(kind: Kind, filePath: String = "") {
        self.kind = kind
        self.filePath = filePath
    }

    public static let cursor = ProfileOutput(kind: .cursor)
    public static let copy = ProfileOutput(kind: .copy)
}
