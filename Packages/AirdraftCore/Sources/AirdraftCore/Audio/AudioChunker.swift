import Foundation

/// Splits long recordings at silences so engines with a short context window
/// (Qwen3-ASR) never see more than `maxSeconds` at once. Cuts are placed at
/// the quietest point inside the last few seconds of a window so words are
/// not split in the middle.
public enum AudioChunker {
    /// The shortest last window `split` leaves by default.
    public static let minimumTailSeconds: Double = 3

    public struct Chunk: Sendable {
        public let samples: [Float]
        public let startSeconds: Double
    }

    /// Windows never exceed `maxSeconds`. When the audio after a full window
    /// would be shorter than `minTailSeconds`, the cut moves earlier instead, so
    /// the last window keeps at least that much audio: a lone ~0.06 s tail made
    /// Parakeet Japanese decode noise (AD-083 ja-2000, 15.06 s at a 15 s cap).
    /// Every sample is kept exactly once, in order.
    public static func split(
        _ samples: [Float],
        sampleRate: Int = 16_000,
        maxSeconds: Double = 25,
        searchWindowSeconds: Double = 6,
        frameMs: Int = 20,
        minTailSeconds: Double = minimumTailSeconds
    ) -> [Chunk] {
        let maxLen = Int(maxSeconds * Double(sampleRate))
        guard samples.count > maxLen else { return [Chunk(samples: samples, startSeconds: 0)] }

        let frame = sampleRate * frameMs / 1000
        let searchLen = Int(searchWindowSeconds * Double(sampleRate))
        // A minimum longer than half a window could not be honoured on both sides.
        let minTail = min(Int(max(0, minTailSeconds) * Double(sampleRate)), maxLen / 2)
        var chunks: [Chunk] = []
        var start = 0
        while start < samples.count {
            let remaining = samples.count - start
            if remaining <= maxLen {
                chunks.append(Chunk(samples: Array(samples[start...]), startSeconds: Double(start) / Double(sampleRate)))
                break
            }
            // Latest allowed cut: a full window, or earlier so the rest keeps minTail.
            let windowEnd = start + min(maxLen, remaining - minTail)
            // Find the quietest frame in [windowEnd-search, windowEnd).
            let searchStart = max(start + frame, windowEnd - searchLen)
            var bestCut = windowEnd
            var bestEnergy = Float.greatestFiniteMagnitude
            var i = searchStart
            while i + frame <= windowEnd {
                var e: Float = 0
                for j in i..<(i + frame) { e += samples[j] * samples[j] }
                if e < bestEnergy { bestEnergy = e; bestCut = i + frame / 2 }
                i += frame
            }
            chunks.append(Chunk(samples: Array(samples[start..<bestCut]), startSeconds: Double(start) / Double(sampleRate)))
            start = bestCut
        }
        return chunks
    }

    /// Decodes each chunk in order and joins the non-empty texts. For engines
    /// that only take whole utterances of limited length.
    public static func transcribe(_ samples: [Float], maxSeconds: Double, decode: ([Float]) throws -> String) throws -> String {
        try Task.checkCancellation()
        let chunks = split(samples, maxSeconds: maxSeconds)
        var parts: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let text = try decode(chunk.samples).trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            if !text.isEmpty { parts.append(text) }
        }
        return join(parts)
    }

    /// Async engines decode bounded windows sequentially. A failed or cancelled
    /// window must not return the successfully decoded prefix as a full transcript.
    /// Runs on the caller's actor, so an engine actor can decode with its own
    /// non-Sendable model state without sending the closure elsewhere.
    nonisolated(nonsending) public static func transcribeAsync(
        _ samples: [Float], maxSeconds: Double,
        decode: ([Float]) async throws -> String
    ) async throws -> String {
        try Task.checkCancellation()
        let chunks = split(samples, maxSeconds: maxSeconds)
        var parts: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            let text = try await decode(chunk.samples).trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            if !text.isEmpty { parts.append(text) }
        }
        return join(parts)
    }

    /// Joins window texts. Chinese, Japanese, Thai, Lao, Khmer and Myanmar are
    /// written without spaces, so windows meet directly when both sides of the
    /// boundary use them; every other boundary (Latin, Hangul, digits) keeps one space.
    static func join(_ parts: [String]) -> String {
        var result = ""
        for part in parts {
            if let last = result.unicodeScalars.last, let first = part.unicodeScalars.first,
               !(isUnspacedScript(last) && isUnspacedScript(first)) {
                result += " "
            }
            result += part
        }
        return result
    }

    /// Han ideographs, kana and the CJK punctuation and full-width forms written
    /// with them, and Thai, Lao, Khmer and Myanmar, which also use no spaces.
    static func isUnspacedScript(_ scalar: Unicode.Scalar) -> Bool {
        if WritingScript.isUnspacedSoutheastAsian(scalar) { return true }
        switch scalar.value {
        case 0x3000...0x303F,   // CJK symbols and punctuation (。、「」)
             0x3040...0x30FF,   // Hiragana, Katakana
             0x31F0...0x31FF,   // Katakana phonetic extensions
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified ideographs
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFF01...0xFF0F, 0xFF1A...0xFF20, 0xFF5B...0xFF65, // full-width punctuation, half-width katakana marks
             0xFF66...0xFF9F,   // half-width katakana
             0x20000...0x3134F: // CJK extensions B–H
            return true
        default:
            return false
        }
    }
}
