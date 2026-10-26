import Foundation
import XCTest
@testable import AirdraftCore

final class SpeechPreviewTests: XCTestCase {
    /// The audio queue is bounded by samples (overflow discards pending audio), oversize and non-finite
    /// chunks disable it, and it keeps chunk order while releasing its budget as consumed.
    func testAudioQueueBoundsSamplesKeepsOrderAndStopsOnInvalidChunks() async {
        do {
            let queue = SpeechPreviewAudioQueue(maximumSamples: 8)
            XCTAssertEqual(queue.append([1, 2, 3]), .accepted)
            XCTAssertEqual(queue.append([4, 5, 6, 7, 8]), .accepted)
            XCTAssertEqual(queue.pendingSampleCount, 8)
            XCTAssertEqual(queue.append([9]), .overflow)
            XCTAssertEqual(queue.pendingSampleCount, 0)
            XCTAssertEqual(queue.append([10]), .stopped)
            let afterOverflow = await queue.next()
            XCTAssertNil(afterOverflow)
        }
        do {
            let oversize = SpeechPreviewAudioQueue(maximumSamples: 4)
            XCTAssertEqual(oversize.append([0, 0, 0, 0, 0]), .overflow)
            XCTAssertEqual(oversize.pendingSampleCount, 0)
            let invalid = SpeechPreviewAudioQueue(maximumSamples: 4)
            XCTAssertEqual(invalid.append([.nan]), .invalid)
            XCTAssertEqual(invalid.append([0]), .stopped)
            let ended = await invalid.next()
            XCTAssertNil(ended)
        }
        do {
            let queue = SpeechPreviewAudioQueue(maximumSamples: 4)
            XCTAssertEqual(queue.append([1, 2]), .accepted)
            XCTAssertEqual(queue.append([3, 4]), .accepted)
            let first = await queue.next()
            XCTAssertEqual(first, [1, 2])
            XCTAssertEqual(queue.pendingSampleCount, 2)
            XCTAssertEqual(queue.append([5, 6]), .accepted)
            let second = await queue.next()
            let third = await queue.next()
            XCTAssertEqual(second, [3, 4])
            XCTAssertEqual(third, [5, 6])
            XCTAssertEqual(queue.pendingSampleCount, 0)
            queue.cancel()
        }
    }

    /// Cancellation resumes a waiting consumer and rejects new audio; cancelling the consumer task also
    /// closes the queue; concurrent append and cancel cannot retain audio.
    func testCancellationClosesTheQueueForConsumersTasksAndConcurrentAppends() async {
        do {
            let queue = SpeechPreviewAudioQueue()
            let completed = expectation(description: "Waiting audio consumer exits")
            let consumer = Task {
                let audio = await queue.next()
                XCTAssertNil(audio)
                completed.fulfill()
            }
            queue.cancel()
            await fulfillment(of: [completed], timeout: 1)
            consumer.cancel()
            XCTAssertEqual(queue.append([0]), .stopped)
            XCTAssertEqual(queue.pendingSampleCount, 0)
        }
        do {
            let queue = SpeechPreviewAudioQueue()
            let completed = expectation(description: "Task cancellation closes audio input")
            let consumer = Task {
                let audio = await queue.next()
                XCTAssertNil(audio)
                completed.fulfill()
            }
            consumer.cancel()
            await fulfillment(of: [completed], timeout: 1)
            XCTAssertEqual(queue.append([0]), .stopped)
        }
        do {
            let queue = SpeechPreviewAudioQueue(maximumSamples: 32_000)
            DispatchQueue.concurrentPerform(iterations: 200) { index in
                if index.isMultiple(of: 17) { queue.cancel() }
                else { _ = queue.append([0, 0.5, -0.5]) }
            }
            XCTAssertEqual(queue.pendingSampleCount, 0)
            XCTAssertEqual(queue.append([0]), .stopped)
        }
    }

    /// Preview replaces its volatile phrase, ignores older results and bounds text; overflow reports once and
    /// cancels the owned worker; cancelling before worker installation cancels the late worker.
    func testControlReplacesPhrasesBoundsTextAndCancelsWorkersOnOverflowOrCancel() {
        do {
            let events = PreviewEvents()
            let control = SpeechPreviewControl(onText: { events.text($0) }, onIssue: { events.issue($0) })
            control.publish(" hello ", startTime: 1)
            control.publish("hello world", startTime: 1)
            control.publish("hello world", startTime: 1)
            control.publish("old finalized phrase", startTime: 0)
            XCTAssertEqual(events.texts, ["hello", "hello world"])
            let longText = String(repeating: "語", count: 550)
            control.publish(longText, startTime: 2)
            XCTAssertEqual(events.texts.last?.count, 500)
            control.cancel()
            control.publish("late result", startTime: 3)
            control.fail("late issue")
            XCTAssertEqual(events.texts.count, 3)
            XCTAssertTrue(events.issues.isEmpty)
        }
        do {
            let events = PreviewEvents()
            let control = SpeechPreviewControl(maximumSamples: 2, onText: { events.text($0) }, onIssue: { events.issue($0) })
            let worker = Task<Void, Never> { _ = await control.audio.next() }
            // An oversize chunk fails even when the worker is already waiting for audio.
            control.setWorker(worker)
            control.append([0, 0, 0])
            control.append([0, 0, 0])
            control.publish("stale", startTime: 0)
            XCTAssertFalse(control.isActive)
            XCTAssertTrue(worker.isCancelled)
            XCTAssertEqual(events.issues.count, 1)
            XCTAssertTrue(events.issues.first?.contains("could not keep up") == true)
            XCTAssertTrue(events.texts.isEmpty)
            XCTAssertEqual(control.audio.pendingSampleCount, 0)
        }
        do {
            let control = SpeechPreviewControl(onText: { _ in XCTFail("Cancelled preview published text") },
                                               onIssue: { _ in XCTFail("Cancelled preview published an issue") })
            control.cancel()
            let worker = Task<Void, Never> { _ = await control.audio.next() }
            control.setWorker(worker)
            XCTAssertTrue(worker.isCancelled)
            control.publish("late setup result", startTime: 0)
            control.fail("late setup failure")
            XCTAssertFalse(control.isActive)
        }
    }
}

private final class PreviewEvents: Sendable {
    private let recordedTexts = Locked<[String]>([])
    private let recordedIssues = Locked<[String]>([])
    var texts: [String] { recordedTexts.value }
    var issues: [String] { recordedIssues.value }
    func text(_ value: String) { recordedTexts.withLock { $0.append(value) } }
    func issue(_ value: String) { recordedIssues.withLock { $0.append(value) } }
}
