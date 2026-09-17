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
                .filter { !$0.isEmpty && $0 != term }
            // Fix casing of the term itself ("floze" -> "Floze").
            if !entry.caseSensitive, isLatin(term) {
                candidates.append(term)
            }
            candidates.sort { $0.count > $1.count }

            for alias in candidates {
                output = replace(alias: alias, with: term, in: output, caseSensitive: entry.caseSensitive)
            }
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

    static func replace(alias: String, with term: String, in text: String, caseSensitive: Bool) -> String {
        if isLatin(alias) {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: alias) + "(?![\\p{L}\\p{N}])"
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(
                in: text, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: term)
            )
        } else {
            // CJK and mixed scripts: literal replacement. Require at least two
            // characters so a single common character never gets rewritten.
            guard alias.count >= 2 else { return text }
            return text.replacingOccurrences(of: alias, with: term)
        }
    }
}
