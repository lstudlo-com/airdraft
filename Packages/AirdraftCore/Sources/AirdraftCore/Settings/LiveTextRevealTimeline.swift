import Foundation

/// Tracks when each part of the live text arrived, so only new words animate (AD-110).
///
/// Live text is resent whole on every update: it grows at the end, its provisional
/// tail is rewritten, and its oldest characters are dropped once it passes the display
/// limit. The timeline aligns each update with the previous one, keeps the arrival time
/// of text that survived, and stamps only what changed.
public struct LiveTextRevealTimeline: Sendable, Equatable {
    /// A run of characters that arrived together. `offset` counts Characters from the
    /// start of the current text; a segment ends where the next begins.
    public struct Segment: Sendable, Equatable {
        public var offset: Int
        /// When its first letter starts to appear.
        public var start: TimeInterval
        /// Seconds between its letters.
        public var stagger: TimeInterval

        /// The start of text that had already appeared when it was first seen.
        public static let settledStart = -TimeInterval.greatestFiniteMagnitude

        public init(offset: Int, start: TimeInterval, stagger: TimeInterval) {
            self.offset = offset
            self.start = start
            self.stagger = stagger
        }
    }

    static let settled = Segment.settledStart

    /// The furthest a new update may queue behind one still appearing.
    static let maximumQueue: TimeInterval = 0.6

    /// How far back dropped leading characters are searched for.
    static let maximumDroppedPrefix = 600

    public private(set) var text = ""
    public private(set) var segments: [Segment] = []
    public private(set) var reveal: LiveTextOptions.Reveal

    public init(reveal: LiveTextOptions.Reveal = .fade) {
        self.reveal = reveal
    }

    /// When the last letter finishes appearing.
    public var end: TimeInterval {
        guard let last = segments.last, last.start != Self.settled else { return Self.settled }
        let count = text.count - last.offset
        return last.start + Double(max(0, count - 1)) * last.stagger + reveal.duration
    }

    /// Records an update. Text present before keeps its time; changed or new text
    /// starts now, or right after a still-appearing update so letters keep their order.
    public mutating func update(text newText: String, reveal: LiveTextOptions.Reveal, now: TimeInterval) {
        if reveal != self.reveal {
            self.reveal = reveal
            segments = newText.isEmpty ? [] : [Segment(offset: 0, start: Self.settled, stagger: 0)]
            text = newText
            return
        }
        guard newText != text else { return }
        let old = Array(text)
        let new = Array(newText)
        defer { text = newText }
        // First text, or a fresh session: everything arriving at once animates.
        guard !old.isEmpty else {
            segments = new.isEmpty ? [] : [segment(at: 0, count: new.count, now: now, after: nil)]
            return
        }
        let (dropped, kept) = Self.alignment(old: old, new: new)
        var aligned: [Segment] = []
        for var segment in segments {
            segment.offset -= dropped
            if segment.offset < 0 {
                // Its head was dropped; the rest still started at the same time.
                segment.start += Double(-segment.offset) * segment.stagger
                segment.offset = 0
            }
            guard segment.offset < kept else { continue }
            if let last = aligned.last, last.offset == segment.offset { aligned.removeLast() }
            aligned.append(segment)
        }
        if aligned.isEmpty, kept > 0 { aligned = [Segment(offset: 0, start: Self.settled, stagger: 0)] }
        if kept < new.count {
            let previousEnd = Self.lastLetterStart(of: aligned, textCount: kept)
            aligned.append(segment(at: kept, count: new.count - kept, now: now, after: previousEnd))
        }
        segments = Self.coalesced(aligned, textCount: new.count, now: now, duration: reveal.duration)
    }

    private func segment(at offset: Int, count: Int, now: TimeInterval, after previous: TimeInterval?) -> Segment {
        let stagger = count > 1 ? min(reveal.stagger, reveal.maximumSpread / Double(count - 1)) : reveal.stagger
        var start = now
        if let previous { start = min(max(now, previous + stagger), now + Self.maximumQueue) }
        return Segment(offset: offset, start: start, stagger: stagger)
    }

    /// Characters dropped from the front, then characters kept unchanged after them.
    static func alignment(old: [Character], new: [Character]) -> (dropped: Int, kept: Int) {
        var best = (dropped: 0, kept: commonPrefix(old[...], new[...]))
        if best.kept == min(old.count, new.count) { return best }
        for dropped in 1..<min(old.count, maximumDroppedPrefix + 1) {
            let remaining = old.count - dropped
            guard remaining > best.kept else { break }
            let kept = commonPrefix(old[dropped...], new[...])
            if kept > best.kept { best = (dropped, kept) }
            if kept == remaining { break }
        }
        // A tiny accidental match is not a dropped head; treat it as new text.
        if best.dropped > 0, best.kept < min(8, new.count) { return (old.count, 0) }
        return best
    }

    private static func commonPrefix(_ a: ArraySlice<Character>, _ b: ArraySlice<Character>) -> Int {
        var count = 0
        var i = a.startIndex, j = b.startIndex
        while i < a.endIndex, j < b.endIndex, a[i] == b[j] {
            count += 1; i += 1; j += 1
        }
        return count
    }

    private static func lastLetterStart(of segments: [Segment], textCount: Int) -> TimeInterval? {
        guard let last = segments.last, last.start != settled else { return nil }
        return last.start + Double(max(0, textCount - last.offset - 1)) * last.stagger
    }

    /// Merges neighbouring segments that have both finished, keeping the list short.
    private static func coalesced(_ segments: [Segment], textCount: Int, now: TimeInterval,
                                  duration: TimeInterval) -> [Segment] {
        var result: [Segment] = []
        for (index, segment) in segments.enumerated() {
            let next = index + 1 < segments.count ? segments[index + 1].offset : textCount
            let finished = segment.start == settled
                || segment.start + Double(max(0, next - segment.offset - 1)) * segment.stagger + duration <= now
            if finished, let last = result.last, last.start == settled { continue }
            result.append(finished ? Segment(offset: segment.offset, start: settled, stagger: 0) : segment)
        }
        return result
    }
}
