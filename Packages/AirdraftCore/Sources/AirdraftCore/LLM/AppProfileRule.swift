import Foundation

/// Chooses a refinement profile from the destination app (AD-080). A rule
/// matches one app by bundle ID, or an `AppFamily` classified from the bundle
/// ID alone. Window titles, URLs and text are never read for this choice, so
/// it is independent of the Read app context consent.
public struct AppProfileRule: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Match: Codable, Sendable, Equatable, Hashable {
        case app(bundleID: String)
        case family(AppFamily)
    }

    public var id: UUID
    public var match: Match
    public var profileID: UUID
    /// The app's name when the rule was added, shown if the app is no longer installed.
    public var appName: String?

    public init(id: UUID = UUID(), match: Match, profileID: UUID, appName: String? = nil) {
        self.id = id
        self.match = match
        self.profileID = profileID
        self.appName = appName
    }

    /// Families a rule can name, in menu order. `.general` matches every
    /// unclassified app, which is what the chosen profile already does.
    public static let selectableFamilies: [AppFamily] = [.code, .terminal, .email, .workChat, .personalChat, .document]

    /// The rule for `bundleID`: an app's own rule wins over its family's.
    public static func rule(for bundleID: String?, in rules: [AppProfileRule]) -> AppProfileRule? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let own = rules.first(where: {
            if case .app(let id) = $0.match { return id.caseInsensitiveCompare(bundleID) == .orderedSame }
            return false
        }) { return own }
        let family = AppFamily.classify(bundleID: bundleID)
        guard family != .general else { return nil }
        return rules.first { $0.match == .family(family) }
    }
}

/// The profile a dictation into one app uses, and the rule that chose it.
public struct ProfileSelection: Sendable, Equatable {
    public let profile: RefinementProfile
    /// Nil when the manually chosen profile applies.
    public let rule: AppProfileRule?

    public init(profile: RefinementProfile, rule: AppProfileRule?) {
        self.profile = profile
        self.rule = rule
    }

    public var isAutomatic: Bool { rule != nil }
}

public extension AppFamily {
    /// Classification from the bundle ID alone; URL hosts need app context.
    static func classify(bundleID: String?) -> AppFamily {
        classify(AppContext(bundleId: bundleID))
    }

    /// The family's name in rule lists and menus.
    var ruleTitle: String {
        switch self {
        case .code: String(localized: "Code editors", bundle: .module, comment: "App family name for profile rules")
        case .terminal: String(localized: "Terminals", bundle: .module, comment: "App family name for profile rules")
        case .email: String(localized: "Email", bundle: .module, comment: "App family name for profile rules")
        case .workChat: String(localized: "Work chat", bundle: .module, comment: "App family name for profile rules")
        case .personalChat: String(localized: "Personal messages", bundle: .module, comment: "App family name for profile rules")
        case .document: String(localized: "Documents and notes", bundle: .module, comment: "App family name for profile rules")
        case .general: String(localized: "Other apps", bundle: .module, comment: "App family name for profile rules")
        }
    }

    /// Well-known members of the family, from `classify`'s bundle table. Product
    /// names are never localized.
    var ruleExamples: [String] {
        switch self {
        case .code: ["Visual Studio Code", "Cursor", "Windsurf", "Xcode", "JetBrains IDEs", "Zed", "Sublime Text"]
        case .terminal: ["Terminal", "iTerm2", "Warp", "Ghostty", "kitty", "Alacritty", "WezTerm"]
        case .email: ["Mail", "Outlook", "Spark"]
        case .workChat: ["Slack", "Microsoft Teams", "Discord", "Mattermost"]
        case .personalChat: ["Messages", "WhatsApp", "Telegram", "WeChat", "LINE", "Signal"]
        case .document: ["Notes", "Notion", "Obsidian", "Pages", "Word"]
        case .general: []
        }
    }
}

/// Decodes every readable rule and skips the rest, so a rule written by a newer
/// version (an unknown family, say) never makes the whole profile file unreadable.
/// Skipped elements are kept as raw JSON and written back unchanged after the
/// readable rules, so saving in this version never deletes a newer version's rules.
struct LossyAppProfileRules: Codable {
    var rules: [AppProfileRule]
    /// Elements this version cannot read, in file order.
    var unreadable: [RawJSON]

    init(_ rules: [AppProfileRule], unreadable: [RawJSON] = []) {
        self.rules = rules
        self.unreadable = unreadable
    }

    init(from decoder: Decoder) throws {
        rules = []
        unreadable = []
        guard var container = try? decoder.unkeyedContainer() else { return }
        while !container.isAtEnd {
            if let rule = try? container.decode(AppProfileRule.self) {
                rules.append(rule)
            } else if let raw = try? container.decode(RawJSON.self) {
                unreadable.append(raw)
            } else {
                break
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for rule in rules { try container.encode(rule) }
        for raw in unreadable { try container.encode(raw) }
    }
}

/// Any JSON value, decoded and re-encoded without interpretation. Numbers keep
/// their integer or floating-point form; object keys keep their values.
enum RawJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values: [RawJSON] = []
            while !array.isAtEnd { values.append(try array.decode(RawJSON.self)) }
            self = .array(values)
            return
        }
        if let object = try? decoder.container(keyedBy: Key.self) {
            var values: [String: RawJSON] = [:]
            for key in object.allKeys { values[key.stringValue] = try object.decode(RawJSON.self, forKey: key) }
            self = .object(values)
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let integer = try? value.decode(Int64.self) { self = .integer(integer) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .string(try value.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .array(let values):
            var array = encoder.unkeyedContainer()
            for value in values { try array.encode(value) }
        case .object(let values):
            var object = encoder.container(keyedBy: Key.self)
            for (key, value) in values { try object.encode(value, forKey: Key(key)) }
        case .null:
            var value = encoder.singleValueContainer()
            try value.encodeNil()
        case .bool(let bool):
            var value = encoder.singleValueContainer()
            try value.encode(bool)
        case .integer(let integer):
            var value = encoder.singleValueContainer()
            try value.encode(integer)
        case .number(let number):
            var value = encoder.singleValueContainer()
            try value.encode(number)
        case .string(let string):
            var value = encoder.singleValueContainer()
            try value.encode(string)
        }
    }

    /// The profile an unreadable rule names, when it names one this version can read.
    var ruleProfileID: UUID? {
        guard case .object(let values) = self, case .string(let id)? = values["profileID"] else { return nil }
        return UUID(uuidString: id)
    }

    private struct Key: CodingKey {
        let stringValue: String
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
