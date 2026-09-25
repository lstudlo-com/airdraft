import XCTest
@testable import AirdraftCore

final class AudioChunkerTests: XCTestCase {
    func testShortAudioIsOneChunk() {
        let chunks = AudioChunker.split([Float](repeating: 0.1, count: 16_000 * 10), maxSeconds: 25)
        XCTAssertEqual(chunks.count, 1)
    }

    func testLongAudioCutsAtSilenceAndKeepsEverySample() {
        // 60 s of "speech" with a silent gap around 22 s and 46 s.
        var samples = [Float](repeating: 0.3, count: 16_000 * 60)
        for gap in [22.0, 46.0] {
            let s = Int(gap * 16_000), e = s + 16_000 / 2
            for i in s..<e { samples[i] = 0 }
        }
        let chunks = AudioChunker.split(samples, maxSeconds: 25)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.samples.count }, samples.count)
        XCTAssertTrue((22.0...22.5).contains(chunks[1].startSeconds), "cut inside the first silent gap")
        XCTAssertTrue((46.0...46.5).contains(chunks[2].startSeconds), "cut inside the second silent gap")
        XCTAssertTrue(chunks.allSatisfy { Double($0.samples.count) / 16_000 <= 25 })
    }

    func testAsyncDecodingKeepsEverySampleAndShortTailInOrder() async throws {
        let samples = (0..<(16_000 * 74)).map { Float($0) / 2_000_000 }
        var decoded: [Float] = []
        var sizes: [Int] = []
        let text = try await AudioChunker.transcribeAsync(samples, maxSeconds: 25) { chunk in
            sizes.append(chunk.count)
            decoded.append(contentsOf: chunk)
            return " part\(sizes.count) "
        }
        XCTAssertEqual(decoded, samples)
        XCTAssertTrue(sizes.allSatisfy { $0 <= 25 * 16_000 })
        XCTAssertGreaterThan(sizes.count, 2)
        XCTAssertEqual(text, (1...sizes.count).map { "part\($0)" }.joined(separator: " "))
    }

    func testAsyncDecodingDoesNotMergeTailBeyondMaximumWindow() async throws {
        var sizes: [Int] = []
        _ = try await AudioChunker.transcribeAsync(Array(repeating: 0.1, count: 27 * 16_000), maxSeconds: 25) { chunk in
            sizes.append(chunk.count)
            return "text"
        }
        XCTAssertEqual(sizes.reduce(0, +), 27 * 16_000)
        XCTAssertEqual(sizes.count, 2)
        XCTAssertLessThanOrEqual(sizes.max()!, 25 * 16_000)
    }

    func testAsyncDecodingPropagatesLaterFailureInsteadOfReturningPrefix() async {
        enum Failure: Error { case laterChunk }
        var calls = 0
        do {
            _ = try await AudioChunker.transcribeAsync(Array(repeating: 0.1, count: 60 * 16_000), maxSeconds: 25) { _ in
                calls += 1
                if calls == 2 { throw Failure.laterChunk }
                return "prefix"
            }
            XCTFail("A later chunk failure must fail the whole recording")
        } catch Failure.laterChunk {
            XCTAssertEqual(calls, 2)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testAsyncDecodingStopsAfterCancellationBeforeNextWindow() async {
        var calls = 0
        let task = Task {
            try await AudioChunker.transcribeAsync(Array(repeating: 0.1, count: 60 * 16_000), maxSeconds: 25) { _ in
                calls += 1
                withUnsafeCurrentTask { $0?.cancel() }
                return "cancelled prefix"
            }
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must not return a partial transcript")
        } catch is CancellationError {
            XCTAssertEqual(calls, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testSynchronousDecodingStopsAfterCancellationBeforeNextWindow() async {
        var calls = 0
        let task = Task<String, Error> {
            try AudioChunker.transcribe(Array(repeating: 0.1, count: 74 * 16_000), maxSeconds: 25) { _ in
                calls += 1
                if calls == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                return "cancelled prefix"
            }
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must stop later expensive decoder calls")
        } catch is CancellationError {
            XCTAssertEqual(calls, 1)
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
