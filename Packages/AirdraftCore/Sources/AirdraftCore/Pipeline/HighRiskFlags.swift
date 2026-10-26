import Foundation

/// One word or number in a dictation's final text that deserves a look before
/// it is sent (AD-104). Flags never use engine confidence: they come from what
/// refinement changed, from the shape of the word and from the speech guards.
public struct DictationFlag: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A number refinement added, removed or changed.
        case number
        /// A negation refinement added or removed.
        case negation
        /// A name or term refinement introduced that the speech did not contain.
        case newTerm
        /// A word shaped like code (camelCase, snake_case, a path or a flag).
        case identifier
        /// A local speech guard cut a loop or decoded the audio again.
        case recognition
    }

    public var kind: Kind
    /// The flagged token as it appears in the final text (or the raw transcript
    /// when refinement removed it).
    public var text: String
    /// The token with a few characters of context.
    public var snippet: String
    /// Whether this flag keeps a requested send from pressing Return.
    public var holdsSend: Bool

    public init(kind: Kind, text: String, snippet: String, holdsSend: Bool = true) {
        self.kind = kind
        self.text = text
        self.snippet = snippet
        self.holdsSend = holdsSend
    }
}

/// Finds high-risk words in a dictation (AD-104, flag version 0). LLMs tolerate
/// spoken filler and small typos; they do not tolerate a wrong identifier,
/// number or negation, so only those are flagged. Ordinary cleanup (casing,
/// punctuation, filler removal) is never flagged.
public enum HighRiskFlags {
    /// At most this many flags are kept for one dictation.
    public static let maximumStored = 20
    /// At most this many are listed in the recording window.
    public static let maximumShown = 3

    /// `raw` is the speech transcript, `final` the text that will be delivered.
    /// `vocabulary` holds the user's preferred spellings, which never flag.
    /// `identifiersHoldSend` false keeps identifier flags visible but lets a
    /// requested send continue.
    public static func flags(raw: String, final: String, vocabulary: [String] = [],
                             adjustments: [TranscriptAdjustment] = [],
                             identifiersHoldSend: Bool = true) -> [DictationFlag] {
        var result: [DictationFlag] = []
        var seen = Set<String>()
        func add(_ kind: DictationFlag.Kind, _ token: String, in text: String, holdsSend: Bool = true) {
            let key = "\(kind.rawValue)|\(token.lowercased())"
            guard result.count < maximumStored, seen.insert(key).inserted else { return }
            result.append(DictationFlag(kind: kind, text: token, snippet: snippet(for: token, in: text), holdsSend: holdsSend))
        }
        let known = Set(vocabulary.flatMap { term in words(in: term).map { $0.lowercased() } } + vocabulary.map { $0.lowercased() })

        if adjustments.contains(where: { [.repetitionTrimmed, .languageRetried, .emptyRetried].contains($0) }) {
            let token = String(final.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            if !token.isEmpty { add(.recognition, token, in: final) }
        }

        // Numbers: any digit run that is not in both texts.
        let rawNumbers = numbers(in: raw)
        let finalNumbers = numbers(in: final)
        for number in finalNumbers where !rawNumbers.contains(number) { add(.number, number, in: final) }
        for number in rawNumbers where !finalNumbers.contains(number) { add(.number, number, in: raw) }

        // Negation: a different count of negating words means the meaning may have flipped.
        let rawNegations = negations(in: raw)
        let finalNegations = negations(in: final)
        if rawNegations.count != finalNegations.count {
            let extra = finalNegations.count > rawNegations.count
            let source = extra ? finalNegations : rawNegations
            let other = extra ? rawNegations : finalNegations
            let differing = source.filter { word in source.filter { $0 == word }.count > other.filter { $0 == word }.count }
            for word in differing.isEmpty ? source : differing { add(.negation, word, in: extra ? final : raw) }
        }

        let rawWords = Set(words(in: raw).map { $0.lowercased() })
        for occurrence in wordOccurrences(in: final) {
            let word = occurrence.word
            let lower = word.lowercased()
            guard !known.contains(lower) else { continue }
            if isIdentifier(word) {
                add(.identifier, word, in: final, holdsSend: identifiersHoldSend)
            } else if !rawWords.contains(lower), isNameLike(word, sentenceStart: occurrence.sentenceStart) {
                add(.newTerm, word, in: final)
            }
        }
        return result
    }

    /// Flags that keep a requested send from pressing Return.
    public static func holdingSend(_ flags: [DictationFlag]) -> [DictationFlag] {
        flags.filter(\.holdsSend)
    }

    // MARK: - Tokens

    private static let latinWord = try! NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9]*(?:[._/:#+-][A-Za-z0-9]+)*|--?[A-Za-z][A-Za-z0-9-]*")
    private static let digitRun = try! NSRegularExpression(pattern: "[0-9]+(?:[.,:/][0-9]+)*")

    static func words(in text: String) -> [String] {
        wordOccurrences(in: text).map(\.word)
    }

    struct Occurrence { let word: String; let sentenceStart: Bool }

    static func wordOccurrences(in text: String) -> [Occurrence] {
        let ns = text as NSString
        return latinWord.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let word = ns.substring(with: match.range)
            var index = match.range.location - 1
            var start = true
            while index >= 0 {
                let character = ns.character(at: index)
                if let scalar = Unicode.Scalar(character), CharacterSet.whitespaces.contains(scalar) || scalar == "\"" || scalar == "(" || scalar == "“" || scalar == "「" {
                    index -= 1
                    continue
                }
                let previous = Character(Unicode.Scalar(character) ?? " ")
                start = ".!?。！？\n:：".contains(previous)
                break
            }
            return Occurrence(word: word, sentenceStart: start)
        }
    }

    static func numbers(in text: String) -> [String] {
        let normalized = String(text.unicodeScalars.map { scalar -> Character in
            // Full-width digits read as their ASCII forms.
            if (0xFF10...0xFF19).contains(scalar.value), let ascii = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) {
                return Character(ascii)
            }
            return Character(scalar)
        })
        let ns = normalized as NSString
        return digitRun.matches(in: normalized, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,:/"))
        }
    }

    /// Negating words in the interface's and speech's main languages.
    static let latinNegations: Set<String> = [
        "not", "no", "never", "none", "nothing", "nobody", "neither", "nor", "cannot",
        "don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "couldn't", "shouldn't",
        "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't", "hadn't", "mustn't",
        "dont", "doesnt", "didnt", "wont", "cant", "isnt", "arent",
        "nunca", "jamás", "jamas", "ni", "nada", "nadie", "ningún", "ninguno", "ninguna",
    ]
    static let cjkNegations = ["沒有", "没有", "不要", "別", "别", "不", "沒", "没", "未", "無", "无", "勿", "ない", "ません", "なかった", "ず", "안", "않", "못"]

    static func negations(in text: String) -> [String] {
        var found: [String] = []
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let tokens = lowered.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        found += tokens.filter { latinNegations.contains($0) }
        var remaining = text
        for marker in cjkNegations {
            var count = 0
            while let range = remaining.range(of: marker) {
                count += 1
                remaining.replaceSubrange(range, with: " ")
            }
            found += Array(repeating: marker, count: count)
        }
        return found
    }

    /// camelCase, snake_case, dotted names, paths, URLs and command flags.
    static func isIdentifier(_ word: String) -> Bool {
        if word.hasPrefix("-") { return true }
        if word.contains("_") || word.contains("/") || word.contains("#") { return true }
        if word.contains("."), word.split(separator: ".").count >= 2, !word.hasSuffix(".") { return true }
        let scalars = Array(word.unicodeScalars)
        for index in scalars.indices.dropFirst() where CharacterSet.uppercaseLetters.contains(scalars[index])
            && CharacterSet.lowercaseLetters.contains(scalars[index - 1]) {
            return true // camelCase or PascalCase with an inner capital
        }
        if word.rangeOfCharacter(from: .decimalDigits) != nil, word.rangeOfCharacter(from: .letters) != nil { return true }
        return false
    }

    /// A capitalized word outside a sentence start, or an all-capitals acronym.
    static func isNameLike(_ word: String, sentenceStart: Bool) -> Bool {
        guard word.count >= 2, let first = word.unicodeScalars.first else { return false }
        let upper = CharacterSet.uppercaseLetters
        if word.unicodeScalars.allSatisfy({ upper.contains($0) }) { return true }
        return upper.contains(first) && !sentenceStart
    }

    static func snippet(for token: String, in text: String, context: Int = 8) -> String {
        guard let range = text.range(of: token) else { return token }
        let start = text.index(range.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
        var result = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start != text.startIndex { result = "…" + result }
        if end != text.endIndex { result += "…" }
        return result
    }
}
