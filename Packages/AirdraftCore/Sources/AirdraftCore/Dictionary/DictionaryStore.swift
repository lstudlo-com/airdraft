import Foundation
import Observation

/// JSON-backed dictionary. Lives on the main actor so SwiftUI can edit it
/// directly; the pipeline reads a snapshot before each run.
@MainActor
@Observable
public final class DictionaryStore {
    public private(set) var entries: [DictionaryEntry] = []
    public private(set) var persistenceError: String?
    private var unreadableOriginal = false
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("dictionary.json")
        load()
    }

    public func add(_ entry: DictionaryEntry) {
        entries.append(entry)
        save()
    }

    public func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        save()
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func removeAlias(_ alias: String, from id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].aliases.removeAll { $0 == alias }
        save()
    }

    public func restore(_ entry: DictionaryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
        else { entries.append(entry) }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { entries = try JSONDecoder().decode([DictionaryEntry].self, from: Data(contentsOf: fileURL)) }
        catch {
            if let backup = UnreadableFile.setAside(fileURL) {
                persistenceError = "Vocabulary could not be read. The original is preserved as \(backup.lastPathComponent) in the data folder. Recover that file before replacing it with an empty vocabulary."
            } else {
                unreadableOriginal = true
                persistenceError = "Vocabulary could not be read or backed up. Saving is blocked to protect the original. Check the data folder permissions and reopen Airdraft."
            }
        }
    }

    public func retrySave() { save() }

    @discardableResult
    private func save() -> Bool {
        guard !unreadableOriginal else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(entries)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Changes are not saved. Keep Airdraft open and retry after checking storage. " + error.localizedDescription
            return false
        }
    }
}
