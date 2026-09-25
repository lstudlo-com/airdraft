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

    public private(set) var persistenceError: String?
    private var unreadableOriginal = false
    private let fileURL: URL

    private struct Persisted: Codable {
        var version: Int
        var baseRules: String
        var profiles: [RefinementProfile]
        var activeProfileID: UUID
    }

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("profiles.json")
        load()
    }

    public var activeProfile: RefinementProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles.first ?? RefinementProfile.defaults[0]
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
        let name = uniqueName(base.usesLLM ? "\(base.name) copy" : "New profile")
        return add(RefinementProfile(
            name: name,
            symbol: base.symbol,
            usesLLM: true,
            task: base.task,
            instructions: base.instructions
        ))
    }

    /// Copy the selected profile, including raw-transcript behavior, without activating it.
    @discardableResult
    public func duplicate(id: UUID) -> RefinementProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        return add(RefinementProfile(
            name: uniqueName("\(source.name) copy"), symbol: source.symbol,
            usesLLM: source.usesLLM, task: source.task, instructions: source.instructions
        ))
    }

    public func update(_ profile: RefinementProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var p = profile
        p.isBuiltIn = profiles[idx].isBuiltIn
        profiles[idx] = p
        save()
    }

    /// Built-ins cannot be removed; use `resetProfile` instead.
    public func remove(id: UUID) {
        guard let p = profiles.first(where: { $0.id == id }), !p.isBuiltIn else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = RefinementProfile.cleanID }
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

    /// Restores every built-in profile and the base rules, and removes user profiles.
    public func resetAll() {
        profiles = RefinementProfile.defaults
        baseRules = PromptBuilder.defaultBaseRules
        activeProfileID = RefinementProfile.cleanID
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let p: Persisted
        do { p = try JSONDecoder().decode(Persisted.self, from: Data(contentsOf: fileURL)) }
        catch {
            if let backup = UnreadableFile.setAside(fileURL) {
                persistenceError = "Profiles could not be read. The original is preserved as \(backup.lastPathComponent) in the data folder. Defaults are shown until you restore your file."
            } else {
                unreadableOriginal = true
                persistenceError = "Profiles could not be read or backed up. Saving is blocked to protect the original. Check the data folder permissions and reopen Airdraft."
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
    }

    public func retrySave() { save() }

    @discardableResult
    private func save() -> Bool {
        guard !unreadableOriginal else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let p = Persisted(version: 1, baseRules: baseRules, profiles: profiles, activeProfileID: activeProfileID)
        do {
            let data = try encoder.encode(p)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Changes are not saved. Keep Airdraft open and retry after checking storage. " + error.localizedDescription
            return false
        }
    }

    private func uniqueName(_ base: String) -> String {
        var name = base
        var n = 2
        while profiles.contains(where: { $0.name == name }) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }
}
