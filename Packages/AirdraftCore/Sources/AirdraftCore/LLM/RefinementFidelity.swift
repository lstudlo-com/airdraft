import Foundation

/// Deterministic checks that a refinement still renders the new transcript.
/// Small models sometimes returned an earlier dictation or answered in the
/// language of their instructions; the pipeline then delivers the raw
/// transcript instead, which also keeps the bad output out of later context.
public enum RefinementFidelity {
    public enum Violation: Equatable, Sendable {
        case repeatsEarlierDictation
        case changesLanguage

        public var message: String {
            switch self {
            case .repeatsEarlierDictation: return "Refinement repeated an earlier dictation instead of this one."
            case .changesLanguage: return "Refinement changed the language of the transcript."
            }
        }
    }

    /// `allowsLanguageChange` is true when a profile TASK or selected text may
    /// legitimately ask for another language.
    public static func violation(output: String, transcript: String, recentDictations: [String],
                                 allowsLanguageChange: Bool) -> Violation? {
        let produced = tokens(output), heard = tokens(transcript)
        for earlier in recentDictations {
            let prior = tokens(earlier)
            guard !prior.isEmpty else { continue }
            // A copy of earlier text that the new speech does not resemble.
            // Repeating the same sentence keeps the transcript close to it.
            if similarity(produced, prior) >= 0.75, similarity(produced, heard) < 0.3,
               similarity(heard, prior) < 0.5 {
                return .repeatsEarlierDictation
            }
        }
        if !allowsLanguageChange, languageChanged(from: transcript, to: output) { return .changesLanguage }
        return nil
    }

    // MARK: - Internals

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF: return true
        default: return false
        }
    }

    /// CJK characters and Latin words count one each, like the LLM word threshold.
    static func scriptCounts(_ text: String) -> (cjk: Int, other: Int) {
        var cjk = 0, other = 0, inWord = false
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                cjk += 1
                inWord = false
            } else if scalar.properties.isAlphabetic {
                if !inWord { other += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return (cjk, other)
    }

    static func languageChanged(from transcript: String, to output: String) -> Bool {
        let heard = scriptCounts(transcript), produced = scriptCounts(output)
        if heard.cjk >= 2 && produced.cjk == 0 { return true }
        if heard.cjk == 0 && heard.other >= 2 && produced.cjk >= 2 { return true }
        let heardTotal = heard.cjk + heard.other, producedTotal = produced.cjk + produced.other
        guard heardTotal >= 4, producedTotal >= 4 else { return false }
        let heardShare = Double(heard.cjk) / Double(heardTotal)
        let producedShare = Double(produced.cjk) / Double(producedTotal)
        return abs(heardShare - producedShare) >= 0.5
    }

    /// Lowercased Latin words and single CJK characters, without punctuation.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        for scalar in text.lowercased().unicodeScalars {
            if isCJK(scalar) {
                if !word.isEmpty { result.append(word); word = "" }
                result.append(String(scalar))
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                word.unicodeScalars.append(scalar)
            } else if !word.isEmpty {
                result.append(word)
                word = ""
            }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }

    /// Dice coefficient over token bigrams; unrelated texts share few pairs
    /// even when they share common words or characters.
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        func grams(_ t: [String]) -> [String: Int] {
            let pairs = t.count == 1 ? t : zip(t, t.dropFirst()).map { $0 + "\u{1F}" + $1 }
            return pairs.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        }
        let x = grams(a), y = grams(b)
        let shared = x.reduce(0) { $0 + min($1.value, y[$1.key] ?? 0) }
        return 2 * Double(shared) / Double(x.values.reduce(0, +) + y.values.reduce(0, +))
    }
}
