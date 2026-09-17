import Foundation

/// Character-level Simplified <-> Traditional conversion via ICU. It is the
/// safety net after ASR biasing and the LLM instruction; phrase-level
/// vocabulary differences (軟體/软件) are left to the LLM prompt.
public enum ChineseScriptConverter {
    public static func convert(_ text: String, to script: ChineseScript) -> String {
        guard script != .auto, containsHan(text) else { return text }
        let transform = StringTransform(script == .traditional ? "Hans-Hant" : "Hant-Hans")
        return text.applyingTransform(transform, reverse: false) ?? text
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }
}
