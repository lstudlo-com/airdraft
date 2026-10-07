import Foundation

/// Disjoint, frame-aligned coverage of a recording. Overlap is decoded once and
/// retained as ambiguous, while unlabelled audio remains available to ASR.
public enum MediaSegmentPlan {
    public struct Segment: Sendable, Equatable {
        public let startFrame: Int
        public let endFrame: Int
        public let speaker: String?
        public let overlapping: Bool
        public var start: Double { Double(startFrame) / 16_000 }
        public var end: Double { Double(endFrame) / 16_000 }
    }

    public static func make(duration: Double, speakers: [SpeakerInterval], maximumSeconds: Double = 25) -> [Segment] {
        guard maximumSeconds.isFinite, maximumSeconds > 0 else { return [] }
        return bounded(partition(duration: duration, speakers: speakers, primarySpeaker: false),
                       maximum: max(1, Int(min(25, maximumSeconds) * 16_000)))
    }

    /// ASR needs a speech turn, not a separate request for every overlap edge.
    /// Keep the longest active utterance as the estimated primary speaker, retain
    /// overlap warnings, and bridge only short pauses by that same speaker.
    /// Uncovered audio is excluded only when callers explicitly use diarization.
    public static func speechTurns(duration: Double, speakers: [SpeakerInterval]) -> [Segment] {
        let pieces = partition(duration: duration, speakers: speakers, primarySpeaker: true)
        var turns: [Segment] = []
        for piece in pieces where piece.speaker != nil {
            if let previous = turns.last, previous.speaker == piece.speaker,
               piece.startFrame - previous.endFrame <= 8_000 {
                turns[turns.count - 1] = Segment(startFrame: previous.startFrame, endFrame: piece.endFrame,
                    speaker: piece.speaker, overlapping: previous.overlapping || piece.overlapping)
            } else { turns.append(piece) }
        }
        return bounded(turns, maximum: 400_000)
    }

    /// Rebalance an artificial sub-second remainder with its preceding window.
    /// A real standalone short speaker turn is kept intact.
    private static func bounded(_ segments: [Segment], maximum: Int) -> [Segment] {
        segments.flatMap { segment in
            var result: [Segment] = [], position = segment.startFrame
            while position < segment.endFrame {
                let remaining = segment.endFrame - position
                let count = remaining > maximum && remaining - maximum < min(16_000, maximum)
                    ? remaining / 2 : min(maximum, remaining)
                result.append(Segment(startFrame: position, endFrame: position + count,
                                      speaker: segment.speaker, overlapping: segment.overlapping))
                position += count
            }
            return result
        }
    }

    private static func partition(duration: Double, speakers: [SpeakerInterval], primarySpeaker: Bool) -> [Segment] {
        guard duration.isFinite, duration > 0, duration <= MediaConfiguration.maximumDuration else { return [] }
        let total = Int((duration * 16_000).rounded())
        var events: [Int: [(Int, Int)]] = [0: [], total: []]
        for (index, interval) in speakers.enumerated() where interval.start.isFinite && interval.end.isFinite && !interval.speaker.isEmpty {
            let start = Int((min(duration, max(0, interval.start)) * 16_000).rounded())
            let end = Int((min(duration, max(0, interval.end)) * 16_000).rounded())
            guard end > start else { continue }
            events[start, default: []].append((index, 1))
            events[end, default: []].append((index, -1))
        }
        let boundaries = events.keys.sorted()
        var active: [Int: SpeakerInterval] = [:]
        var result: [Segment] = []
        for index in boundaries.indices.dropLast() {
            let start = boundaries[index], end = boundaries[index + 1]
            for (interval, change) in events[start] ?? [] {
                active[interval] = change > 0 ? speakers[interval] : nil
            }
            let identities = Set(active.values.map(\.speaker))
            let speaker: String?
            if primarySpeaker && identities.count > 1 {
                speaker = active.values
                    .sorted {
                        let lhs = $0.end - $0.start, rhs = $1.end - $1.start
                        return lhs == rhs ? $0.speaker < $1.speaker : lhs > rhs
                    }.first?.speaker
            } else { speaker = identities.count == 1 ? identities.first : nil }
            let overlapping = identities.count > 1
            // Preserve whole turns before selecting bounded ASR windows.
            if let last = result.last, last.endFrame == start, last.speaker == speaker,
               last.overlapping == overlapping {
                result[result.count - 1] = Segment(startFrame: last.startFrame, endFrame: end,
                                                   speaker: speaker, overlapping: overlapping)
            } else { result.append(Segment(startFrame: start, endFrame: end, speaker: speaker, overlapping: overlapping)) }
        }
        return result
    }
}
