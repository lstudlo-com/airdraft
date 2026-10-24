import Foundation
import NaturalLanguage

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
            case .repeatsEarlierDictation: return String(localized: "Refinement repeated an earlier dictation instead of this one.", bundle: .module)
            case .changesLanguage: return String(localized: "Refinement changed the language of the transcript.", bundle: .module)
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

    /// Kana and Hangul tell Japanese and Korean apart from Chinese, which all
    /// count as CJK above: a Japanese transcript returned as Chinese keeps its
    /// CJK share while losing every kana.
    static func scriptMarks(_ text: String) -> (kana: Int, hangul: Int) {
        var kana = 0, hangul = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            default: break
            }
        }
        return (kana, hangul)
    }

    static func languageChanged(from transcript: String, to output: String) -> Bool {
        let heardMarks = scriptMarks(transcript), producedMarks = scriptMarks(output)
        if heardMarks.kana >= 3 && producedMarks.kana == 0 { return true }
        if heardMarks.hangul >= 2 && producedMarks.hangul == 0 { return true }
        let heard = scriptCounts(transcript), produced = scriptCounts(output)
        // Chinese speech returned as Japanese or Korean.
        if heardMarks.kana == 0 && heard.cjk >= 4 && producedMarks.kana >= 3 { return true }
        if heardMarks.hangul == 0 && heard.cjk >= 4 && producedMarks.hangul >= 2 { return true }
        if heard.cjk >= 2 && produced.cjk == 0 { return true }
        if heard.cjk == 0 && heard.other >= 2 && produced.cjk >= 2 { return true }
        let heardProfile = ScriptProfile(transcript), producedProfile = ScriptProfile(output)
        if otherScriptChanged(heard: heardProfile, produced: producedProfile) { return true }
        let heardTotal = heard.cjk + heard.other, producedTotal = produced.cjk + produced.other
        if heardTotal >= 4, producedTotal >= 4 {
            let heardShare = Double(heard.cjk) / Double(heardTotal)
            let producedShare = Double(produced.cjk) / Double(producedTotal)
            if abs(heardShare - producedShare) >= 0.5 { return true }
        }
        return latinLanguageChanged(from: transcript, to: output, heard: heardProfile, produced: producedProfile)
    }

    /// Scripts other than Latin and CJK (Cyrillic, Arabic, Devanagari, Thai and
    /// the rest): Russian, Arabic or Hindi speech returned in English loses its
    /// script, and English speech returned in one of them gains it.
    static func otherScriptChanged(heard: ScriptProfile, produced: ScriptProfile) -> Bool {
        let cjkOrUndecided: Set<WritingScript> = [.latin, .other, .han, .kana, .hangul]
        let scripts = Set(heard.counts.keys).union(produced.counts.keys).subtracting(cjkOrUndecided)
        for script in scripts {
            if heard.count(script) >= 8, heard.fraction(script) >= 0.3, produced.fraction(script) < 0.05 { return true }
            if produced.count(script) >= 8, produced.fraction(script) >= 0.3, heard.count(script) == 0 { return true }
        }
        return false
    }

    /// Languages that share the Latin alphabet (Spanish returned in English) differ
    /// only by words. The on-device recognizer decides, and only when it is
    /// confident about both texts: mixed speech and short phrases never count.
    static func latinLanguageChanged(from transcript: String, to output: String,
                                     heard: ScriptProfile, produced: ScriptProfile) -> Bool {
        guard heard.letters >= 30, produced.letters >= 30,
              heard.fraction(.latin) >= 0.9, produced.fraction(.latin) >= 0.9,
              let from = dominantLanguage(transcript), let to = dominantLanguage(output), from != to else { return false }
        return !closelyRelatedLanguages.contains { $0.contains(from) && $0.contains(to) }
    }

    /// The recognizer confuses these with each other on short text.
    static let closelyRelatedLanguages: [Set<String>] = [
        ["id", "ms"], ["nb", "nn", "no", "da", "sv"], ["hr", "bs", "sr"], ["cs", "sk"], ["es", "gl", "pt"],
    ]

    static func dominantLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first,
              probability >= 0.9 else { return nil }
        return language.rawValue.split(separator: "-").first.map(String.init)
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
