import Foundation

/// Corrections the local speech output guards made to a transcript (AD-082).
/// Recorded on `Transcript.adjustments` and logged without any text.
public enum TranscriptAdjustment: String, Sendable, Equatable, Codable, CaseIterable {
    /// A decoder loop (one block repeated many times) was cut to one occurrence.
    case repetitionTrimmed
    /// An Auto result in an unexpected language or script was replaced by an
    /// explicit-language decode of the same audio and model.
    case languageRetried
    /// An empty result on audible input was replaced by one relaxed second decode.
    case emptyRetried
    /// All-capitals English from SenseVoice/FireRedASR2 was given natural case.
    case casingNormalized
    /// Sentence-final punctuation was added to unpunctuated engine output.
    case punctuationAdded
}

/// Writing systems the language guard can map to languages. Latin is shared by
/// too many languages to judge from text, so it never marks a result implausible.
enum WritingScript: Hashable, Sendable {
    case latin, han, kana, hangul, cyrillic, greek, arabic, hebrew, thai, devanagari, bengali, tamil
    case georgian, armenian, ethiopic, khmer, lao, myanmar, sinhala, tibetan, other

    /// Languages normally written in this script; nil when text cannot decide.
    var languages: Set<String>? {
        switch self {
        case .latin, .other: return nil
        case .han: return ["zh", "yue", "ja", "zh-hk"]
        case .kana: return ["ja"]
        case .hangul: return ["ko"]
        case .cyrillic: return ["ru", "uk", "be", "bg", "mk", "sr", "kk", "ky", "mn", "tg", "tt", "ba"]
        case .greek: return ["el"]
        case .arabic: return ["ar", "fa", "ur", "ps", "sd", "ug"]
        case .hebrew: return ["he", "yi"]
        case .thai: return ["th"]
        case .devanagari: return ["hi", "mr", "ne", "sa"]
        case .bengali: return ["bn", "as"]
        case .tamil: return ["ta"]
        case .georgian: return ["ka"]
        case .armenian: return ["hy"]
        case .ethiopic: return ["am"]
        case .khmer: return ["km"]
        case .lao: return ["lo"]
        case .myanmar: return ["my"]
        case .sinhala: return ["si"]
        case .tibetan: return ["bo"]
        }
    }

    static func of(_ scalar: Unicode.Scalar) -> WritingScript? {
        let v = scalar.value
        guard scalar.properties.isAlphabetic || (0x3400...0x9FFF).contains(v) else { return nil }
        switch v {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF, 0xFF21...0xFF3A, 0xFF41...0xFF5A: return .latin
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return .kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return .han
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
        case 0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: return .cyrillic
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return .greek
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return .arabic
        case 0x0590...0x05FF: return .hebrew
        case 0x0E00...0x0E7F: return .thai
        case 0x0900...0x097F: return .devanagari
        case 0x0980...0x09FF: return .bengali
        case 0x0B80...0x0BFF: return .tamil
        case 0x10A0...0x10FF: return .georgian
        case 0x0530...0x058F: return .armenian
        case 0x1200...0x139F: return .ethiopic
        case 0x1780...0x17FF: return .khmer
        case 0x0E80...0x0EFF: return .lao
        case 0x1000...0x109F: return .myanmar
        case 0x0D80...0x0DFF: return .sinhala
        case 0x0F00...0x0FFF: return .tibetan
        default: return .other
        }
    }
}

extension WritingScript {
    /// Thai, Lao, Khmer and Myanmar write words without spaces, like Chinese
    /// and Japanese, but form words from several letters, including tone and
    /// vowel marks that are not alphabetic. Covers the whole blocks.
    static func isUnspacedSoutheastAsian(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0E00...0x0E7F, 0x0E80...0x0EFF, 0x1780...0x17FF, 0x19E0...0x19FF, 0x1000...0x109F, 0xAA60...0xAA7F:
            return true
        default:
            return false
        }
    }
}

/// Letter counts per writing system. Japanese is recognised by kana: Han
/// characters inside text that also contains kana count as Japanese.
struct ScriptProfile: Sendable, Equatable {
    private(set) var counts: [WritingScript: Int] = [:]
    var letters: Int { counts.values.reduce(0, +) }

    init(_ text: String) {
        for scalar in text.unicodeScalars {
            if let script = WritingScript.of(scalar) { counts[script, default: 0] += 1 }
        }
        let kana = counts[.kana] ?? 0, han = counts[.han] ?? 0
        if kana > 0, Double(kana) >= 0.1 * Double(kana + han) {
            counts[.kana] = kana + han
            counts[.han] = nil
        }
    }

    func count(_ script: WritingScript) -> Int { counts[script] ?? 0 }

    func fraction(_ script: WritingScript) -> Double {
        letters == 0 ? 0 : Double(count(script)) / Double(letters)
    }

    /// True when every letter is Latin (and there is at least one).
    var isLatinOnly: Bool { letters > 0 && count(.latin) == letters }

    /// Share of letters written in scripts consistent with `expected` languages.
    /// Latin and unmapped scripts count as consistent: text alone cannot decide.
    func plausibility(expected: Set<String>) -> Double {
        guard letters > 0 else { return 0 }
        let consistent = counts.reduce(0) { sum, entry in
            guard let languages = entry.key.languages else { return sum + entry.value }
            return languages.isDisjoint(with: expected) ? sum : sum + entry.value
        }
        return Double(consistent) / Double(letters)
    }

    /// A substantial part of the text (30% of letters or more) is in a script
    /// none of the expected languages use, such as Cyrillic for a zh/en user.
    func isImplausible(expected: Set<String>) -> Bool {
        letters > 0 && plausibility(expected: expected) <= 0.7
    }
}

/// Finds decoder loops: one block of tokens repeated many times in a row, as in
/// `克里克里克里…` from Qwen3-ASR on degraded audio. Thresholds stay well above
/// ordinary emphasis (`對對對`, `哈哈哈哈`, `no no no`).
enum TranscriptRepetition {
    struct Unit { let key: String; let range: Range<String.Index> }

    /// The longest block size checked, in tokens (Han characters or words).
    static let maximumPeriod = 10

    /// Repeats a block of `period` tokens must reach before it counts as a loop.
    static func minimumRepeats(period: Int) -> Int {
        switch period {
        case 1: return 8
        case 2: return 6
        default: return max(4, Int((12.0 / Double(period)).rounded(.up)))
        }
    }

    /// Han, kana and Hangul characters are one token each; other letter/digit
    /// runs are one case-insensitive word. Punctuation and spaces are skipped.
    static func units(_ text: String) -> [Unit] {
        var result: [Unit] = []
        var index = text.startIndex
        var wordStart: String.Index?
        func closeWord(at end: String.Index) {
            if let start = wordStart { result.append(Unit(key: text[start..<end].lowercased(), range: start..<end)) }
            wordStart = nil
        }
        while index < text.endIndex {
            let next = text.index(after: index)
            let character = text[index]
            let scalar = character.unicodeScalars.first!
            let script = WritingScript.of(scalar)
            if script == .han || script == .kana || script == .hangul {
                closeWord(at: index)
                result.append(Unit(key: String(character), range: index..<next))
            } else if character.isLetter || character.isNumber || character == "'" || character == "’" {
                if wordStart == nil { wordStart = index }
            } else {
                closeWord(at: index)
            }
            index = next
        }
        closeWord(at: text.endIndex)
        return result
    }

    /// Range to delete (from the second occurrence to the end of the loop), if any.
    static func loop(in units: [Unit]) -> (remove: Range<Int>, period: Int, repeats: Int)? {
        guard units.count >= 8 else { return nil }
        var best: (remove: Range<Int>, period: Int, repeats: Int, covered: Int)?
        for period in 1...min(maximumPeriod, units.count / 2) {
            var start = 0
            while start + period < units.count {
                var length = 0
                while start + length + period < units.count, units[start + length].key == units[start + length + period].key {
                    length += 1
                }
                if length == 0 { start += 1; continue }
                let covered = length + period
                let repeats = covered / period
                if repeats >= minimumRepeats(period: period), best == nil || covered > best!.covered {
                    best = ((start + period)..<(start + covered), period, repeats, covered)
                }
                start += length
            }
        }
        return best.map { ($0.remove, $0.period, $0.repeats) }
    }

    /// Text with every loop cut to its first occurrence, or nil when none is found.
    static func trimmed(_ text: String) -> String? {
        var current = text
        var changed = false
        for _ in 0..<4 {
            let tokens = units(current)
            guard let found = loop(in: tokens) else { break }
            let lower = tokens[found.remove.lowerBound - 1].range.upperBound
            let upper = tokens[found.remove.upperBound - 1].range.upperBound
            current.removeSubrange(lower..<upper)
            changed = true
        }
        guard changed else { return nil }
        return current.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Coarse speech-energy check, used only to decide whether an empty result on
/// this audio deserves one more decode. It never rejects or alters audio.
enum AudioActivity {
    /// At least 0.25 s of 20 ms frames above about -40 dBFS RMS.
    static func isAudible(_ samples: [Float], sampleRate: Int = 16_000) -> Bool {
        let frame = sampleRate / 50
        guard frame > 0, samples.count >= frame else { return false }
        let needed = 12
        var loud = 0
        var start = 0
        while start + frame <= samples.count {
            var energy: Float = 0
            for value in samples[start..<(start + frame)] { energy += value * value }
            if energy / Float(frame) > 0.0001 {
                loud += 1
                if loud >= needed { return true }
            }
            start += frame
        }
        return false
    }
}

/// Phrases Whisper is known to invent on non-speech audio. A relaxed retry that
/// returns only one of these keeps the original empty result.
enum KnownHallucination {
    private static let phrases: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching", "thanks for watching!",
        "please subscribe", "subtitles by the amara.org community", "you",
        "字幕由amara.org社區提供", "字幕由amara.org社区提供", "請不吝點贊訂閱轉發打賞支持明鏡與點點欄目",
        "请不吝点赞订阅转发打赏支持明镜与点点栏目", "謝謝觀看", "谢谢观看", "謝謝大家", "谢谢大家",
        // Subtitle credits and sign-offs from Whisper's training videos in other languages.
        "subtítulos realizados por la comunidad de amara.org", "gracias por ver el video", "gracias por ver",
        "sous-titres réalisés para la communauté d'amara.org", "sous-titres réalisés par la communauté d'amara.org",
        "merci d'avoir regardé", "untertitel der amara.org-community", "vielen dank fürs zuschauen",
        "legendas pela comunidade amara.org", "obrigado por assistir", "sottotitoli creati dalla comunità amara.org",
        "grazie per la visione", "продолжение следует", "спасибо за просмотр",
        "ご視聴ありがとうございました", "ご視聴ありがとうございます", "チャンネル登録よろしくお願いします",
        "시청해주셔서감사합니다",
    ]

    static func matches(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return phrases.contains(normalized) || phrases.contains(normalized.replacingOccurrences(of: " ", with: ""))
    }
}
