import Foundation
import XCTest
@testable import AirdraftCore

final class SpeechPreviewTests: XCTestCase {
    func testAudioQueueIsBoundedBySamplesAndOverflowDiscardsPendingAudio() async {
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

    func testOversizeAndNonFiniteChunksDisableTheirQueue() async {
        let oversize = SpeechPreviewAudioQueue(maximumSamples: 4)
        XCTAssertEqual(oversize.append([0, 0, 0, 0, 0]), .overflow)
        XCTAssertEqual(oversize.pendingSampleCount, 0)
        let invalid = SpeechPreviewAudioQueue(maximumSamples: 4)
        XCTAssertEqual(invalid.append([.nan]), .invalid)
        XCTAssertEqual(invalid.append([0]), .stopped)
        let ended = await invalid.next()
        XCTAssertNil(ended)
    }

    func testQueuePreservesChunkOrderAndReleasesItsBudgetAsConsumed() async {
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

    func testCancellationResumesAWaitingConsumerAndRejectsNewAudio() async {
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

    func testCancellingConsumerTaskAlsoClosesTheQueue() async {
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

    func testPreviewReplacesVolatilePhraseIgnoresOlderResultsAndBoundsText() {
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

    func testOverflowReportsOnceAndCancelsOwnedWorker() {
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

    func testCancelBeforeWorkerInstallationCancelsLateWorker() {
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

    func testConcurrentAppendAndCancelCannotRetainAudio() {
        let queue = SpeechPreviewAudioQueue(maximumSamples: 32_000)
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            if index.isMultiple(of: 17) { queue.cancel() }
            else { _ = queue.append([0, 0.5, -0.5]) }
        }
        XCTAssertEqual(queue.pendingSampleCount, 0)
        XCTAssertEqual(queue.append([0]), .stopped)
    }
}

private final class PreviewEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTexts: [String] = []
    private var recordedIssues: [String] = []
    var texts: [String] { lock.withLock { recordedTexts } }
    var issues: [String] { lock.withLock { recordedIssues } }
    func text(_ value: String) { lock.withLock { recordedTexts.append(value) } }
    func issue(_ value: String) { lock.withLock { recordedIssues.append(value) } }
}
