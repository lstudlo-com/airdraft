import Foundation

/// Searchable UI copy only. Setting values and credentials never enter the index.
public struct SettingsSearchDocument: Equatable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable {
        public let section: String
        public let title: String
    }

    public let section: String
    public let title: String
    public let detail: String
    public var id: ID { ID(section: section, title: title) }

    public init(section: String, title: String, detail: String = "") {
        self.section = section
        self.title = title
        self.detail = detail
    }
}

/// A small, in-memory index, rebuilt when UI copy changes, never while scrolling.
public struct SettingsSearchIndex: Sendable {
    private struct Entry: Sendable {
        let document: SettingsSearchDocument
        let title: String
        let text: String
    }

    private let entries: [Entry]

    public init(_ documents: [SettingsSearchDocument]) {
        var seen = Set<SettingsSearchDocument.ID>()
        entries = documents.filter { seen.insert($0.id).inserted }.map {
            Entry(document: $0, title: Self.fold($0.title),
                  text: Self.fold([$0.section, $0.title, $0.detail].joined(separator: "\n")))
        }
    }

    /// Every whitespace-separated term must occur; punctuation is literal, not a regex.
    /// Exact setting names win, then matches retain the page's reading order.
    public func matches(_ query: String) -> [SettingsSearchDocument] {
        let terms = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let phrase = terms.joined(separator: " ")
        let found = entries.filter { entry in terms.allSatisfy { entry.text.contains($0) } }
        return found.filter { $0.title == phrase }.map(\.document)
            + found.filter { $0.title != phrase }.map(\.document)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }
}
