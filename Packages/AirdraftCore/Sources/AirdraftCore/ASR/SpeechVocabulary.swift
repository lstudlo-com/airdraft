import Foundation

/// Preferred vocabulary spellings for on-device speech biasing (AD-081).
///
/// Only `DictionaryEntry.term` values arrive here: aliases describe how speech
/// was misheard and must never be offered to a recognizer as text to produce.
/// The list is bounded, cleaned of markup that a decoder prompt could read as
/// control text, and filtered to scripts the selected language can produce.
/// Cloud providers keep their own keyword limits in `vocabularyTerms`.
public enum SpeechVocabulary {
    /// More terms dilute the bias and lengthen every decoder prompt.
    public static let maximumTerms = 50
    public static let maximumTermCharacters = 40
    public static let maximumTermWords = 4
    /// Upper bound for the joined list (about 150 Qwen tokens).
    public static let maximumTotalCharacters = 600

    /// Characters that delimit special tokens or runtime syntax (`<|im_end|>`,
    /// sherpa-onnx `/` phrase separators and `:score` suffixes). A term that
    /// contains them is skipped rather than rewritten.
    static let rejectedCharacters = CharacterSet(charactersIn: "<>|{}[]\\/`")

    /// Bounded, deduplicated preferred spellings for `language` (nil = auto).
    public static func terms(_ vocabulary: [String], language: String?) -> [String] {
        let allowed = allowedScripts(for: language)
        var seen = Set<String>()
        var total = 0
        var result: [String] = []
        for raw in vocabulary {
            guard result.count < maximumTerms, let term = sanitized(raw) else { continue }
            guard scripts(of: term).isSubset(of: allowed) else { continue }
            guard seen.insert(term.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)).inserted else { continue }
            let cost = term.count + (result.isEmpty ? 0 : 2)
            guard total + cost <= maximumTotalCharacters else { break }
            total += cost
            result.append(term)
        }
        return result
    }

    static func sanitized(_ raw: String) -> String? {
        // A newline or control character could start a new prompt turn.
        guard raw.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == " " || $0 == "\t" }),
              raw.rangeOfCharacter(from: rejectedCharacters) == nil else { return nil }
        let words = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{3000}" })
        guard !words.isEmpty, words.count <= maximumTermWords,
              !words.contains(where: { $0.hasPrefix(":") }) else { return nil }
        let term = words.joined(separator: " ")
        guard term.count <= maximumTermCharacters,
              term.unicodeScalars.contains(where: { $0.properties.isAlphabetic || $0.properties.numericType != nil }) else { return nil }
        return term
    }

    // MARK: Prompt-echo guard

    /// RMS below which a chunk is treated as silence for biasing (about -50 dBFS).
    /// Measured speech sits near -15 dBFS and quiet speech above -45 dBFS, so
    /// this only removes the vocabulary from near-silent input.
    public static let silenceRMS: Float = 0.003

    /// Decoder-prompt models (Qwen3-ASR) read the vocabulary as preceding text
    /// and can return it for audio without speech. Silence decodes without it.
    public static func isNearSilent(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return true }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot() < silenceRMS
    }

    /// True when `text` is nothing but two or more vocabulary terms, the shape
    /// of a decoder repeating its context instead of transcribing speech.
    public static func echoesTerms(_ text: String, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        var remainder = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        var found = 0
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let folded = term.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            let parts = remainder.components(separatedBy: folded)
            found += parts.count - 1
            remainder = parts.joined(separator: " ")
        }
        let leftover = remainder.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
        return found >= 2 && !leftover
    }

    enum Script: Hashable { case latin, han, kana, hangul, other }

    static func scripts(of term: String) -> Set<Script> {
        var result = Set<Script>()
        for scalar in term.unicodeScalars where scalar.properties.isAlphabetic {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: result.insert(.kana)
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: result.insert(.hangul)
            case 0x2E80...0x2FDF, 0x3005...0x3007, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x3FFFF:
                result.insert(.han)
            case 0...0x024F, 0x1E00...0x1EFF, 0xFF21...0xFF5A: result.insert(.latin)
            default: result.insert(.other)
            }
        }
        return result
    }

    /// Latin names and identifiers occur in every language. CJK terms are kept
    /// only for languages that write them, so an English recording is never
    /// steered toward Chinese characters by a Chinese name in the same list.
    static func allowedScripts(for language: String?) -> Set<Script> {
        let code = language?.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").split(separator: "-").first?.lowercased()
        switch code {
        case nil, "", "auto": return [.latin, .han, .kana, .hangul, .other]
        case "zh", "yue": return [.latin, .han]
        case "ja": return [.latin, .han, .kana]
        case "ko": return [.latin, .han, .hangul]
        default: return [.latin, .other]
        }
    }
}
