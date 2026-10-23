import Foundation

/// Character-level Simplified <-> Traditional conversion via ICU. It is the
/// safety net after ASR biasing and the LLM instruction; phrase-level
/// vocabulary differences (軟體/软件) are left to the LLM prompt.
public enum ChineseScriptConverter {
    public static func convert(_ text: String, to script: ChineseScript) -> String {
        guard script != .auto, containsHan(text), !containsKana(text) else { return text }
        let transform = StringTransform(script == .traditional ? "Hans-Hant" : "Hant-Hans")
        return text.applyingTransform(transform, reverse: false) ?? text
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// Kana marks Japanese, whose kanji are neither Simplified nor Traditional
    /// Chinese: the ICU transform would rewrite 国 as 國 and 数 as 數 (AD-083,
    /// `eval/eja-asr`). The middle dot U+30FB also appears in Chinese names, so
    /// it does not count.
    static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3041...0x309F).contains(value) || ((0x30A0...0x30FF).contains(value) && value != 0x30FB)
                || (0x31F0...0x31FF).contains(value) || (0xFF66...0xFF9F).contains(value)
        }
    }
}
