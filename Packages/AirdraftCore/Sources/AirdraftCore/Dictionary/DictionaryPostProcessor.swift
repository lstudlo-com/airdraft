import Foundation

/// Deterministic last-pass replacement. Runs after the LLM so the dictionary
/// always wins. Latin aliases match on word boundaries (case-insensitive
/// unless the entry says otherwise); CJK aliases match literally,
/// longest first.
public enum DictionaryPostProcessor {

    public static func apply(_ text: String, entries: [DictionaryEntry]) -> String {
        var output = text
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { continue }

            var candidates = entry.aliases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0 != term && (isLatin($0) || $0.count >= 2) }
            // Match canonical spellings too, so a shorter alias cannot rewrite
            // part of an already correct term. Latin matches also fix its casing.
            candidates.append(term)
            candidates.sort { $0.count > $1.count }
            let pattern = candidates.map { pattern(for: $0, caseSensitive: entry.caseSensitive) }.joined(separator: "|")
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            output = regex.stringByReplacingMatches(
                in: output, range: NSRange(output.startIndex..., in: output),
                withTemplate: NSRegularExpression.escapedTemplate(for: term)
            )
        }
        return output
    }

    /// Comma-separated vocabulary for ASR biasing and the LLM prompt.
    public static func vocabulary(_ entries: [DictionaryEntry]) -> [String] {
        entries.map { $0.term.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// "misheard -> correct" lines for the LLM prompt.
    public static func correctionLines(_ entries: [DictionaryEntry]) -> [String] {
        entries.flatMap { entry in
            entry.aliases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { "\($0) -> \(entry.term)" }
        }
    }

    // MARK: - Internals

    static func isLatin(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isAlphabetic && scalar.value < 0x0250 || scalar.properties.numericType != nil
                || scalar == " " || scalar == "-" || scalar == "_" || scalar == "." || scalar == "'"
        }
    }

    private static func pattern(for alias: String, caseSensitive: Bool) -> String {
        let literal = NSRegularExpression.escapedPattern(for: alias)
        if isLatin(alias) {
            let bounded = "(?<![\\p{L}\\p{N}])" + literal + "(?![\\p{L}\\p{N}])"
            return caseSensitive ? bounded : "(?i:\(bounded))"
        }
        return literal
    }
}
