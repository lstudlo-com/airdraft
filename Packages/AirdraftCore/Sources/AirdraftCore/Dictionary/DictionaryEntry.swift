import Foundation

/// A term the user wants spelled a specific way, plus the misheard forms
/// that should be rewritten to it.
public struct DictionaryEntry: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var term: String
    public var aliases: [String]
    public var caseSensitive: Bool

    public init(id: UUID = UUID(), term: String, aliases: [String] = [], caseSensitive: Bool = false) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.caseSensitive = caseSensitive
    }
}
