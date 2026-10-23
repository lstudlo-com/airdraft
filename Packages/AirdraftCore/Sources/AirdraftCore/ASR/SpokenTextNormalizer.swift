import Foundation

/// Deterministic cleanup for engines that write English in capitals and never
/// punctuate: SenseVoice and FireRedASR2 (AD-082). Other engines keep their
/// output untouched. Runs before refinement, `ChineseScriptConverter` and the
/// dictionary, which keeps the last word.
public enum SpokenTextNormalizer {
    /// Spellings kept as written whatever the input case: acronyms and product
    /// names common in dictation. Dictionary terms take precedence.
    static let canonicalSpellings: [String: String] = {
        let words = [
            "PR", "PRs", "IT", "US", "AM", "API", "APIs", "URL", "URLs", "iOS", "macOS", "iPadOS", "watchOS", "tvOS", "visionOS",
            "iPhone", "iPad", "iMac", "iCloud", "MacBook", "AirPods", "Mac", "GitHub", "GitLab", "JavaScript",
            "TypeScript", "PostgreSQL", "MySQL", "SQLite", "OK", "AI", "UI", "UX", "CPU", "GPU", "RAM", "SSD",
            "PDF", "SQL", "JSON", "HTML", "CSS", "HTTP", "HTTPS", "USB", "CEO", "CTO", "CFO", "COO", "HR", "PM",
            "QA", "KPI", "KPIs", "OKR", "OKRs", "ID", "IDs", "PPT", "LLM", "LLMs", "SDK", "CLI", "CI", "CD", "NPM",
            "VPN", "Wi-Fi", "AWS", "GCP", "IBM", "NASA", "FAQ", "ETA", "ASAP", "FYI", "MVP", "POC", "SOP", "ROI",
            "B2B", "B2C", "SaaS", "IPO", "VIP", "DIY", "TV", "DJ", "MBA", "PhD", "GPT", "ChatGPT", "OpenAI",
            "YouTube", "LinkedIn", "PayPal", "WhatsApp", "WeChat", "TikTok", "IG", "FB", "NBA", "EU", "UK", "USA",
            "iPhones", "Xcode", "SwiftUI", "AirDrop", "FaceTime", "LINE", "Google", "Apple", "Microsoft",
            "Docker", "Kubernetes", "Slack", "Notion", "Jira", "Figma", "React", "Python", "Swift", "Java",
            "Linux", "Windows", "Android", "Excel", "Word", "PowerPoint", "Zoom", "Teams", "Gmail", "Chrome",
            "Safari", "Facebook", "Instagram", "Twitter", "Netflix", "Amazon", "Tesla", "Taiwan",
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "January", "February",
            "March", "April", "June", "July", "August", "September", "October", "November", "December",
            "English", "Chinese", "Mandarin", "Cantonese", "Japanese", "Korean",
        ]
        return Dictionary(words.map { ($0.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Multi-word names matched as a phrase.
    static let builtinPhrases: [String: String] = ["HONG KONG": "Hong Kong", "NEW YORK": "New York",
                                                   "GOOGLE SHEETS": "Google Sheets", "GOOGLE DOCS": "Google Docs"]

    /// Ordinary words that are also capitalised abbreviations. Inside an English
    /// phrase they are words (`it`, `us`); alone between Chinese they stay capitals.
    static let ambiguous: Set<String> = ["IT", "US", "AM", "LINE", "WORD", "SWIFT", "APPLE", "WINDOWS", "TEAMS", "ZOOM", "MARCH", "MAY"]
    /// Interjections without vowels that are not acronyms.
    static let vowellessWords: [String: String] = ["HMM": "hmm", "MM": "mm", "MMM": "mmm", "SHH": "shh", "PSST": "psst",
                                                    "MR": "Mr", "MRS": "Mrs", "MS": "Ms", "DR": "Dr", "ST": "St", "TV": "TV"]

    /// Natural case plus sentence-final punctuation, with the adjustments made.
    public static func normalizeCapitalizedOutput(_ text: String, vocabulary: [String] = []) -> (text: String, adjustments: [TranscriptAdjustment]) {
        var adjustments: [TranscriptAdjustment] = []
        var result = text
        let cased = naturalCase(result, vocabulary: vocabulary)
        if cased != result { result = cased; adjustments.append(.casingNormalized) }
        let punctuated = addTerminalPunctuation(result)
        if punctuated != result { result = punctuated; adjustments.append(.punctuationAdded) }
        return (result, adjustments)
    }

    struct Word { let range: Range<String.Index>; let text: String }

    /// Converts all-capitals Latin words to natural case. Text whose Latin letters
    /// are not (almost) all capitals is returned unchanged.
    public static func naturalCase(_ text: String, vocabulary: [String] = []) -> String {
        let latin = text.unicodeScalars.filter { WritingScript.of($0) == .latin }
        let upper = latin.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        guard !latin.isEmpty, Double(upper) >= 0.9 * Double(latin.count) else { return text }
        let runs = phrases(in: text)
        let terms = vocabularyIndex(vocabulary).merging(builtinPhrases) { term, _ in term }
        var replacements: [(Range<String.Index>, String)] = []
        for run in runs {
            var index = 0
            while index < run.count {
                // Longest dictionary phrase first (up to four words).
                var matched = false
                for length in stride(from: min(4, run.count - index), through: 1, by: -1) {
                    let key = run[index..<(index + length)].map { $0.text.uppercased() }.joined(separator: " ")
                    if let term = terms[key] {
                        replacements.append((run[index].range.lowerBound..<run[index + length - 1].range.upperBound, term))
                        index += length
                        matched = true
                        break
                    }
                }
                if matched { continue }
                let word = run[index]
                replacements.append((word.range, cased(word.text, in: run, at: index)))
                index += 1
            }
        }
        var result = text
        for (range, value) in replacements.reversed() { result.replaceSubrange(range, with: value) }
        return capitalizeEnglishSentences(result)
    }

    private static func vocabularyIndex(_ vocabulary: [String]) -> [String: String] {
        var index: [String: String] = [:]
        for term in vocabulary {
            let words = term.split(whereSeparator: { $0 == " " }).map(String.init)
            guard !words.isEmpty, words.count <= 4,
                  words.allSatisfy({ $0.unicodeScalars.allSatisfy { WritingScript.of($0) == .latin || CharacterSet.decimalDigits.contains($0) || $0 == "-" || $0 == "." } }) else { continue }
            let key = words.map { $0.uppercased() }.joined(separator: " ")
            if index[key] == nil { index[key] = words.joined(separator: " ") }
        }
        return index
    }

    /// Latin words grouped into phrases: neighbours separated only by spaces.
    /// Digits, apostrophes and hyphens continue a word that began with a letter.
    static func phrases(in text: String) -> [[Word]] {
        var runs: [[Word]] = []
        var current: [Word] = []
        var wordStart: String.Index?
        func closeWord(at end: String.Index) {
            guard let start = wordStart else { return }
            current.append(Word(range: start..<end, text: String(text[start..<end])))
            wordStart = nil
        }
        func closeRun() {
            if !current.isEmpty { runs.append(current) }
            current = []
        }
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.unicodeScalars.allSatisfy({ WritingScript.of($0) == .latin }) {
                if wordStart == nil { wordStart = index }
            } else if wordStart != nil, character.isNumber || "'’-".contains(character) {
                // Part of the current word (B2B, I'M, WI-FI).
            } else {
                closeWord(at: index)
                if character != " " { closeRun() }
            }
            index = text.index(after: index)
        }
        closeWord(at: text.endIndex)
        closeRun()
        return runs
    }

    static func cased(_ word: String, in run: [Word], at index: Int) -> String {
        let upper = word.uppercased()
        guard word == upper else { return word }
        let inPhrase = run.count >= 2
        if let canonical = canonicalSpellings[upper], !(inPhrase && ambiguous.contains(upper)) { return canonical }
        if upper.count == 1 {
            if upper == "I" { return "I" }
            // Spelled letters (`I G I N G`) and lone letters (`A 計畫`) stay capitals.
            let neighbours = [index > 0 ? run[index - 1].text : nil, index + 1 < run.count ? run[index + 1].text : nil]
            if !inPhrase || neighbours.contains(where: { $0?.count == 1 }) { return upper }
            return upper.lowercased()
        }
        if upper.hasPrefix("I'") || upper.hasPrefix("I’") { return "I" + upper.dropFirst().lowercased() }
        if let interjection = vowellessWords[upper] { return interjection }
        let letters = upper.filter(\.isLetter)
        // Letters without vowels (PR, SQL, HTML, NPM) are acronyms; so is a word
        // mixing letters and digits (B2B, 5G).
        if letters.count >= 2, letters.count <= 5, !letters.contains(where: { "AEIOUY".contains($0) }) { return upper }
        if upper.contains(where: \.isNumber), letters.count <= 4 { return upper }
        return upper.lowercased()
    }

    /// Capitalises the first word of sentences that contain no Chinese, Japanese
    /// or Korean characters; mixed sentences keep lowercase English terms.
    static func capitalizeEnglishSentences(_ text: String) -> String {
        var result = ""
        var sentence = ""
        func flush() {
            let hasCJK = sentence.unicodeScalars.contains { [.han, .kana, .hangul].contains(WritingScript.of($0)) }
            if !hasCJK, let first = sentence.firstIndex(where: \.isLetter), sentence[first].isLowercase {
                sentence.replaceSubrange(first...first, with: String(sentence[first]).uppercased())
            }
            result += sentence
            sentence = ""
        }
        for character in text {
            sentence.append(character)
            if ".!?。！？".contains(character) { flush() }
        }
        flush()
        return result
    }

    static let terminalMarks: Set<Character> = [".", "!", "?", "。", "！", "？", "，", ",", "、", ";", "；", ":", "：", "…", "~", "～",
                                               "」", "』", "”", "\"", "'", ")", "）", "]", "】", "》"]
    static let englishQuestionStarts: Set<String> = ["can", "could", "would", "will", "should", "do", "does", "did", "is", "are",
                                                     "was", "were", "what", "why", "how", "where", "when", "who", "which", "shall", "may"]

    /// Adds one sentence-final mark to unpunctuated text of three or more tokens:
    /// `。` (or `？` after 嗎) when the text has Chinese characters or kana,
    /// `.` when Hangul dominates (Korean ends sentences with a period, not `。`),
    /// otherwise `.` (or `?` for an English question). Short fragments stay bare.
    public static func addTerminalPunctuation(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !terminalMarks.contains(last), last.isLetter || last.isNumber else { return text }
        guard TranscriptRepetition.units(trimmed).count >= 3 else { return text }
        var hanOrKana = 0, hangul = 0
        for scalar in trimmed.unicodeScalars {
            switch WritingScript.of(scalar) {
            case .han, .kana: hanOrKana += 1
            case .hangul: hangul += 1
            default: break
            }
        }
        if hangul > hanOrKana { return trimmed + "." }
        if hanOrKana > 0 {
            return trimmed + (last == "嗎" || last == "吗" ? "？" : "。")
        }
        let firstWord = trimmed.split(whereSeparator: { !$0.isLetter && $0 != "'" }).first.map { $0.lowercased() } ?? ""
        return trimmed + (englishQuestionStarts.contains(firstWord) ? "?" : ".")
    }
}
