import Foundation

public enum ApproximateWordCount {
    /// Words for alphabetic scripts and Korean, characters for Chinese and
    /// Japanese, dictionary words for Thai, Lao, Khmer and Myanmar. Good enough
    /// for the refinement threshold and statistics.
    public static func of(_ text: String) -> Int {
        var count = 0
        var inWord = false
        var unspaced = String.UnicodeScalarView()
        // Thai, Lao, Khmer and Myanmar runs have no spaces; ICU's dictionary word
        // breaks segment them, so a sentence is not one word below the LLM threshold.
        func flushUnspaced() {
            guard !unspaced.isEmpty else { return }
            let run = String(unspaced)
            var words = 0
            run.enumerateSubstrings(in: run.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
            count += max(words, 1)
            unspaced.removeAll()
        }
        for scalar in text.unicodeScalars {
            if WritingScript.isUnspacedSoutheastAsian(scalar) {
                unspaced.append(scalar)
                inWord = false
                continue
            }
            flushUnspaced()
            // Chinese and Japanese count characters. Korean separates words with
            // spaces, so Hangul counts like other alphabets.
            let isHanOrKana = (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
            if isHanOrKana {
                count += 1
                inWord = false
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                        || (inWord && scalar.properties.generalCategory == .nonspacingMark) {
                if !inWord { count += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        flushUnspaced()
        return count
    }
}

#if !os(macOS)
/// iOS has no `DictationPipeline` (see MobileDictation); shared code such as
/// `HistoryStore` reaches the word count through this namespace.
public enum DictationPipeline {
    nonisolated static func approximateWordCount(_ text: String) -> Int {
        ApproximateWordCount.of(text)
    }
}
#endif
