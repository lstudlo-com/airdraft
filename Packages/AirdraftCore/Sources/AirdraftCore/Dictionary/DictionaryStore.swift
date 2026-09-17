import Foundation
import Observation

/// JSON-backed dictionary. Lives on the main actor so SwiftUI can edit it
/// directly; the pipeline reads a snapshot before each run.
@MainActor
@Observable
public final class DictionaryStore {
    public private(set) var entries: [DictionaryEntry] = []
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([DictionaryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
