import Foundation

/// Splits long recordings at silences so engines with a short context window
/// (Qwen3-ASR) never see more than `maxSeconds` at once. Cuts are placed at
/// the quietest point inside the last few seconds of a window so words are
/// not split in the middle.
public enum AudioChunker {
    public struct Chunk: Sendable {
        public let samples: [Float]
        public let startSeconds: Double
    }

    public static func split(
        _ samples: [Float],
        sampleRate: Int = 16_000,
        maxSeconds: Double = 25,
        searchWindowSeconds: Double = 6,
        frameMs: Int = 20,
        minTailSeconds: Double = 3
    ) -> [Chunk] {
        let maxLen = Int(maxSeconds * Double(sampleRate))
        guard samples.count > maxLen else { return [Chunk(samples: samples, startSeconds: 0)] }

        let frame = sampleRate * frameMs / 1000
        let searchLen = Int(searchWindowSeconds * Double(sampleRate))
        var chunks: [Chunk] = []
        var start = 0
        while start < samples.count {
            let remaining = samples.count - start
            // A short remainder would become a tiny chunk the model may return
            // empty for; keep it with the current window instead.
            if remaining <= maxLen + Int(minTailSeconds * Double(sampleRate)) {
                chunks.append(Chunk(samples: Array(samples[start...]), startSeconds: Double(start) / Double(sampleRate)))
                break
            }
            // Find the quietest frame in [start+maxLen-search, start+maxLen).
            let windowEnd = start + maxLen
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
    public static func transcribe(_ samples: [Float], maxSeconds: Double, decode: ([Float]) throws -> String) rethrows -> String {
        let chunks = split(samples, maxSeconds: maxSeconds)
        var parts: [String] = []
        for chunk in chunks {
            let text = try decode(chunk.samples).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append(text) }
        }
        return parts.joined(separator: chunks.count > 1 ? " " : "")
    }
}
