import Foundation
import Observation

/// JSON-backed profile list plus the shared base rules and the active
/// selection. Built-in profiles are always present; a reset restores
/// their default text without touching user-created profiles unless
/// `resetAll` is used.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [RefinementProfile] = RefinementProfile.defaults
    public private(set) var baseRules: String = PromptBuilder.defaultBaseRules
    public private(set) var activeProfileID: UUID = RefinementProfile.cleanID
    /// Choose profile by app (AD-080). Off by default; rules are kept while off.
    public private(set) var choosesProfileByApp = false
    /// At most one rule per app or family, in the order they were added.
    public private(set) var appRules: [AppProfileRule] = []
    /// Rules a newer version wrote that this one cannot read, kept unchanged so
    /// saving here never deletes them. Deleting their profile or Reset All drops them.
    private var unreadableAppRules: [RawJSON] = []

    public private(set) var persistenceError: String?
    private var unreadableOriginal = false
    private let fileURL: URL

    private struct Persisted: Codable {
        var version: Int
        var baseRules: String
        var profiles: [RefinementProfile]
        var activeProfileID: UUID
        // Added in 0.12; older files omit both and older versions ignore them.
        var choosesProfileByApp: Bool?
        var appRules: LossyAppProfileRules?
    }

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    public var activeProfile: RefinementProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles.first ?? RefinementProfile.defaults[0]
    }

    /// The profile a dictation into `bundleID` uses: an app's own rule, then its
    /// family's rule, then the manually chosen profile. Only the bundle ID is used.
    public func selection(forApp bundleID: String?) -> ProfileSelection {
        guard choosesProfileByApp,
              let rule = AppProfileRule.rule(for: bundleID, in: appRules),
              let profile = profiles.first(where: { $0.id == rule.profileID }) else {
            return ProfileSelection(profile: activeProfile, rule: nil)
        }
        return ProfileSelection(profile: profile, rule: rule)
    }

    public var baseRulesAreDefault: Bool { baseRules == PromptBuilder.defaultBaseRules }

    public func isDefault(_ profile: RefinementProfile) -> Bool {
        guard let d = RefinementProfile.defaultProfile(id: profile.id) else { return false }
        return d == profile
    }

    // MARK: - Mutations

    public func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        save()
    }

    // MARK: - App rules

    public func setChoosesProfileByApp(_ enabled: Bool) {
        guard choosesProfileByApp != enabled else { return }
        choosesProfileByApp = enabled
        save()
    }

    /// Adds a rule, or points an existing rule for the same app or family at `profileID`.
    @discardableResult
    public func addAppRule(_ match: AppProfileRule.Match, profileID: UUID, appName: String? = nil) -> AppProfileRule? {
        guard profiles.contains(where: { $0.id == profileID }) else { return nil }
        if case .family(.general) = match { return nil }
        if let index = appRules.firstIndex(where: { $0.match == match }) {
            appRules[index].profileID = profileID
            if let appName { appRules[index].appName = appName }
            save()
            return appRules[index]
        }
        let rule = AppProfileRule(match: match, profileID: profileID, appName: appName)
        appRules.append(rule)
        save()
        return rule
    }

    public func setProfile(_ profileID: UUID, forRule id: UUID) {
        guard profiles.contains(where: { $0.id == profileID }),
              let index = appRules.firstIndex(where: { $0.id == id }),
              appRules[index].profileID != profileID else { return }
        appRules[index].profileID = profileID
        save()
    }

    public func removeAppRule(id: UUID) {
        guard appRules.contains(where: { $0.id == id }) else { return }
        appRules.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    public func add(_ profile: RefinementProfile) -> RefinementProfile {
        var p = profile
        p.isBuiltIn = false
        profiles.append(p)
        save()
        return p
    }

    @discardableResult
    public func addNew() -> RefinementProfile {
        let base = activeProfile
        let name = uniqueName(base.usesLLM ? Self.copyName(base) : String(localized: "New profile", bundle: .module))
        return add(RefinementProfile(
            name: name,
            symbol: base.symbol,
            usesLLM: true,
            task: base.task,
            instructions: base.instructions,
            speechModel: base.speechModel
        ))
    }

    /// Copy the selected profile, including raw-transcript behavior, without activating it.
    @discardableResult
    public func duplicate(id: UUID) -> RefinementProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        return add(RefinementProfile(
            name: uniqueName(Self.copyName(source)), symbol: source.symbol,
            usesLLM: source.usesLLM, task: source.task, instructions: source.instructions,
            speechModel: source.speechModel
        ))
    }

    public func update(_ profile: RefinementProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var p = profile
        p.isBuiltIn = profiles[idx].isBuiltIn
        profiles[idx] = p
        save()
    }

    public enum RenameResult: Equatable {
        case renamed, unchanged, empty
        /// Another profile already shows or stores this name (its display name).
        case duplicate(String)
    }

    /// Renames to what the user typed, shown as typed from now on (AD-079). A name
    /// another profile already shows or stores is refused, so two profiles never
    /// look the same, in either interface language.
    @discardableResult
    public func rename(id: UUID, to typed: String) -> RenameResult {
        rename(id: id, to: typed, localizingBuiltIn: RefinementProfile.localizedBuiltInName)
    }

    func rename(id: UUID, to typed: String, localizingBuiltIn localize: (UUID) -> String?) -> RenameResult {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return .unchanged }
        guard !name.isEmpty else { return .empty }
        guard name != profiles[index].displayName(localizingBuiltIn: localize) else { return .unchanged }
        if let other = profile(named: name, except: id, localizingBuiltIn: localize) {
            return .duplicate(other.displayName(localizingBuiltIn: localize))
        }
        profiles[index].name = name
        profiles[index].nameIsCustom = true
        save()
        return .renamed
    }

    /// Case-, width- and diacritic-insensitive match against stored and shown names.
    private func profile(named name: String, except id: UUID?,
                         localizingBuiltIn localize: (UUID) -> String? = RefinementProfile.localizedBuiltInName) -> RefinementProfile? {
        let key = Self.nameKey(name)
        return profiles.first { $0.id != id && (Self.nameKey($0.name) == key || Self.nameKey($0.displayName(localizingBuiltIn: localize)) == key) }
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Built-ins cannot be removed; use `resetProfile` instead.
    public func remove(id: UUID) {
        guard let p = profiles.first(where: { $0.id == id }), !p.isBuiltIn else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = RefinementProfile.cleanID }
        // A rule never falls back to another profile silently; it is removed.
        appRules.removeAll { $0.profileID == id }
        unreadableAppRules.removeAll { $0.ruleProfileID == id }
        save()
    }

    public func resetProfile(id: UUID) {
        guard let d = RefinementProfile.defaultProfile(id: id),
              let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx] = d
        save()
    }

    public func setBaseRules(_ text: String) {
        baseRules = text
        save()
    }

    public func resetBaseRules() {
        baseRules = PromptBuilder.defaultBaseRules
        save()
    }

    /// Restores every built-in profile and the base rules, and removes user profiles
    /// and app rules.
    public func resetAll() {
        profiles = RefinementProfile.defaults
        baseRules = PromptBuilder.defaultBaseRules
        activeProfileID = RefinementProfile.cleanID
        choosesProfileByApp = false
        appRules = []
        unreadableAppRules = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let p: Persisted
        do { p = try JSONDecoder().decode(Persisted.self, from: Data(contentsOf: fileURL)) }
        catch {
            if let backup = UnreadableFile.setAside(fileURL) {
                persistenceError = String(localized: "Profiles could not be read. The original is preserved as \(backup.lastPathComponent) in the data folder. Defaults are shown until you restore your file.", bundle: .module)
            } else {
                unreadableOriginal = true
                persistenceError = String(localized: "Profiles could not be read or backed up. Saving is blocked to protect the original. Check the data folder permissions and reopen Airdraft.", bundle: .module)
            }
            return
        }
        var loaded = p.profiles
        // Built-ins added in later versions appear even in older files.
        for d in RefinementProfile.defaults where !loaded.contains(where: { $0.id == d.id }) {
            loaded.append(d)
        }
        profiles = loaded
        baseRules = p.baseRules.isEmpty ? PromptBuilder.defaultBaseRules : p.baseRules
        activeProfileID = loaded.contains(where: { $0.id == p.activeProfileID }) ? p.activeProfileID : RefinementProfile.cleanID
        choosesProfileByApp = p.choosesProfileByApp ?? false
        // Keep one rule per app or family, each naming a profile that exists.
        var seen = Set<AppProfileRule.Match>()
        appRules = (p.appRules?.rules ?? []).filter { rule in
            guard loaded.contains(where: { $0.id == rule.profileID }), rule.match != .family(.general) else { return false }
            return seen.insert(rule.match).inserted
        }
        // Unreadable rules naming a profile that no longer exists are dropped too.
        unreadableAppRules = (p.appRules?.unreadable ?? []).filter { raw in
            raw.ruleProfileID.map { id in loaded.contains { $0.id == id } } ?? true
        }
    }

    public func retrySave() { save() }

    @discardableResult
    private func save() -> Bool {
        guard !unreadableOriginal else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let p = Persisted(version: 1, baseRules: baseRules, profiles: profiles, activeProfileID: activeProfileID,
                          choosesProfileByApp: choosesProfileByApp, appRules: LossyAppProfileRules(appRules, unreadable: unreadableAppRules))
        do {
            let data = try encoder.encode(p)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = String(localized: "Changes are not saved. Keep Airdraft open and retry after checking storage.", bundle: .module) + " " + error.localizedDescription
            return false
        }
    }

    /// A new profile's name is the user's own text, so it starts in the interface language.
    private static func copyName(_ source: RefinementProfile) -> String {
        String(localized: "\(source.displayName) copy", bundle: .module, comment: "Name of a duplicated profile")
    }

    private func uniqueName(_ base: String) -> String {
        var name = base
        var n = 2
        while profile(named: name, except: nil) != nil {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }
}
