import XCTest
@testable import AirdraftCore

final class LiveTextRevealTimelineTests: XCTestCase {
    private typealias Segment = LiveTextRevealTimeline.Segment
    private let settled = LiveTextRevealTimeline.settled

    func testGrowingTextStampsOnlyNewLettersSettlesOldOnesAndBoundsItsTiming() {
        // The first text appears from now.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .fade)
            timeline.update(text: "Hello", reveal: .fade, now: 10)
            XCTAssertEqual(timeline.segments, [Segment(offset: 0, start: 10, stagger: 0.012)])
            XCTAssertEqual(timeline.end, 10 + 4 * 0.012 + 0.35, accuracy: 1e-9)
        }

        // Appended words animate and earlier words keep their time.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .rise)
            timeline.update(text: "Hello", reveal: .rise, now: 10)
            timeline.update(text: "Hello world", reveal: .rise, now: 10.2)
            XCTAssertEqual(timeline.segments.map(\.offset), [0, 5])
            XCTAssertEqual(timeline.segments[0].start, 10)
            XCTAssertEqual(timeline.segments[1].start, 10.2)
        }

        // Finished text settles into one segment.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .fade)
            timeline.update(text: "One", reveal: .fade, now: 0)
            timeline.update(text: "One two", reveal: .fade, now: 5)
            timeline.update(text: "One two three", reveal: .fade, now: 10)
            XCTAssertEqual(timeline.segments, [Segment(offset: 0, start: settled, stagger: 0),
                                               Segment(offset: 7, start: 10, stagger: 0.012)])
        }

        // Letters keep their order: an update arriving while the typewriter is still
        // typing starts after the last letter, but never queues far behind speech.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .typewriter)
            timeline.update(text: "abcdefghij", reveal: .typewriter, now: 0)
            timeline.update(text: "abcdefghij klm", reveal: .typewriter, now: 0.1)
            XCTAssertEqual(timeline.segments.last!.start, 9 * 0.035 + 0.035, accuracy: 1e-9)
            let long = String(repeating: "x", count: 40)
            var queued = LiveTextRevealTimeline(reveal: .typewriter)
            queued.update(text: long, reveal: .typewriter, now: 0)
            queued.update(text: long + "yz", reveal: .typewriter, now: 0.1)
            XCTAssertEqual(queued.segments.last!.start, 0.1 + LiveTextRevealTimeline.maximumQueue, accuracy: 1e-9)
        }

        // A long update spreads within its maximum.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .wave)
            let text = String(repeating: "a", count: 101)
            timeline.update(text: text, reveal: .wave, now: 0)
            XCTAssertEqual(timeline.segments[0].stagger, 0.7 / 100, accuracy: 1e-12)
            XCTAssertEqual(timeline.end, 0.7 + 0.55, accuracy: 1e-9)
        }
    }

    func testRewrittenTailsDroppedHeadsAndUnrelatedTextAlignWithThePreviousUpdate() {
        // A rewritten provisional tail animates again from where it changed.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .focus)
            timeline.update(text: "send the report", reveal: .focus, now: 0)
            timeline.update(text: "send the reports today", reveal: .focus, now: 5)
            XCTAssertEqual(timeline.segments.last?.offset, 15)
            timeline.update(text: "send the rapport", reveal: .focus, now: 9)
            XCTAssertEqual(timeline.segments.map(\.offset), [0, 10])
            XCTAssertEqual(timeline.segments.last?.start, 9)
        }

        // Past the display limit the oldest characters drop off; the rest must not
        // animate again, only the words that actually arrived.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .pop)
            let first = String(repeating: "word ", count: 20)
            timeline.update(text: first, reveal: .pop, now: 0)
            timeline.update(text: String(first.dropFirst(10)) + "next ", reveal: .pop, now: 5)
            XCTAssertEqual(timeline.segments, [Segment(offset: 0, start: settled, stagger: 0),
                                               Segment(offset: 90, start: 5, stagger: 0.022)])
        }

        // A head dropped while text is still appearing keeps the timing of the letters
        // that remain, and the new words queue behind them.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .fade)
            timeline.update(text: "alpha beta gamma delta epsilon", reveal: .fade, now: 0)
            timeline.update(text: "beta gamma delta epsilon zeta", reveal: .fade, now: 0.1)
            XCTAssertEqual(timeline.segments.map(\.offset), [0, 24])
            XCTAssertEqual(timeline.segments[0].start, 6 * 0.012, accuracy: 1e-9)
            XCTAssertEqual(timeline.segments[1].start, 6 * 0.012 + 24 * 0.012, accuracy: 1e-9)
        }

        // Unrelated text animates whole.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .fade)
            timeline.update(text: "first session", reveal: .fade, now: 0)
            timeline.update(text: "another one", reveal: .fade, now: 5)
            XCTAssertEqual(timeline.segments, [Segment(offset: 0, start: 5, stagger: 0.012)])
        }
    }

    func testChangingTheEffectSettlesAndClearingEmptiesTheTimeline() {
        // Changing the effect settles shown text.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .fade)
            timeline.update(text: "Hello", reveal: .fade, now: 0)
            timeline.update(text: "Hello", reveal: .glow, now: 0.1)
            XCTAssertEqual(timeline.segments, [Segment(offset: 0, start: settled, stagger: 0)])
            XCTAssertEqual(timeline.end, settled)
        }

        // Clearing text empties the timeline.
        do {
            var timeline = LiveTextRevealTimeline(reveal: .fade)
            timeline.update(text: "Hello", reveal: .fade, now: 0)
            timeline.update(text: "", reveal: .fade, now: 1)
            XCTAssertEqual(timeline.segments, [])
            timeline.update(text: "Again", reveal: .fade, now: 2)
            XCTAssertEqual(timeline.segments, [Segment(offset: 0, start: 2, stagger: 0.012)])
        }
    }

}
