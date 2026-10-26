import XCTest
@testable import AirdraftCore

final class AudioChunkerTests: XCTestCase {
    func testSplitCutsAtSilenceKeepsEverySampleAndAvoidsTinyTails() {
        // ShortAudioIsOneChunk
        do {
            let chunks = AudioChunker.split([Float](repeating: 0.1, count: 16_000 * 10), maxSeconds: 25)
            XCTAssertEqual(chunks.count, 1)
        }
        // LongAudioCutsAtSilenceAndKeepsEverySample
        do {
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
        // TinyTailMovesTheCutEarlierWithinTheWindowLimit
        // ja-2000 was 15.06 s at Parakeet's 15 s cap: the old split left a 0.06 s
        // tail that decoded alone as noise. The last window now keeps at least
        // the minimum tail, and no window exceeds the engine's limit.
        do {
            let samples = [Float](repeating: 0.2, count: Int(15.06 * 16_000))
            for chunks in [AudioChunker.split(samples, maxSeconds: 15)] {
                XCTAssertEqual(chunks.count, 2)
                XCTAssertTrue(chunks.allSatisfy { $0.samples.count <= 15 * 16_000 })
                XCTAssertGreaterThanOrEqual(chunks[1].samples.count, 3 * 16_000)
                XCTAssertEqual(chunks.reduce(0) { $0 + $1.samples.count }, samples.count)
            }
        }
        // TailCutPrefersSilenceInsideTheAllowedRange
        do {
            // Two "sentences" with a pause at 7.0-7.4 s; the audio is 15.06 s long.
            var samples = [Float](repeating: 0.3, count: Int(15.06 * 16_000))
            for i in Int(7.0 * 16_000)..<Int(7.4 * 16_000) { samples[i] = 0 }
            let chunks = AudioChunker.split(samples, maxSeconds: 15)
            XCTAssertEqual(chunks.count, 2)
            XCTAssertTrue((7.0...7.4).contains(chunks[1].startSeconds), "cut at \(chunks[1].startSeconds)")
        }
        // LongTailKeepsTheOldCutAndZeroMinimumKeepsMeetingsSplit
        do {
            // With at least the minimum left over, the cut search is unchanged.
            let long = [Float](repeating: 0.1, count: 40 * 16_000)
            XCTAssertEqual(AudioChunker.split(long, maxSeconds: 25).map(\.samples.count),
                           AudioChunker.split(long, maxSeconds: 25, minTailSeconds: 0).map(\.samples.count))
            // Meetings passes 0 and keeps the latest quiet point, here at 24.5 s.
            var media = [Float](repeating: 0.3, count: Int(25.06 * 16_000))
            for i in Int(24.5 * 16_000)..<Int(24.8 * 16_000) { media[i] = 0 }
            XCTAssertTrue((24.5...24.8).contains(AudioChunker.split(media, maxSeconds: 25, minTailSeconds: 0)[1].startSeconds))
            XCTAssertLessThan(AudioChunker.split(media, maxSeconds: 25)[1].startSeconds, 22.07)
        }
    }

    func testDecodingKeepsEverySampleInBoundedWindowsForBothVariants() async throws {
        // AsyncDecodingKeepsEverySampleAndShortTailInOrder
        do {
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
        // AsyncDecodingDoesNotMergeTailBeyondMaximumWindow
        do {
            var sizes: [Int] = []
            _ = try await AudioChunker.transcribeAsync(Array(repeating: 0.1, count: 27 * 16_000), maxSeconds: 25) { chunk in
                sizes.append(chunk.count)
                return "text"
            }
            XCTAssertEqual(sizes.reduce(0, +), 27 * 16_000)
            XCTAssertEqual(sizes.count, 2)
            XCTAssertLessThanOrEqual(sizes.max()!, 25 * 16_000)
        }
        // SynchronousAndAsyncDecodingShareTheBoundedSplit
        do {
            let samples = [Float](repeating: 0.1, count: Int(25.5 * 16_000))
            var asyncSizes: [Int] = []
            _ = try await AudioChunker.transcribeAsync(samples, maxSeconds: 25) { asyncSizes.append($0.count); return "a" }
            var syncSizes: [Int] = []
            _ = try AudioChunker.transcribe(samples, maxSeconds: 25) { syncSizes.append($0.count); return "a" }
            XCTAssertEqual(asyncSizes, syncSizes)
            XCTAssertEqual(syncSizes.count, 2, "The synchronous variant no longer merges a tail beyond its window")
            XCTAssertTrue(syncSizes.allSatisfy { $0 <= 25 * 16_000 })
            XCTAssertGreaterThanOrEqual(syncSizes.last!, 3 * 16_000)
            XCTAssertEqual(syncSizes.reduce(0, +), samples.count)
        }
    }

    func testDecodingPropagatesLaterFailuresAndStopsAfterCancellation() async {
        // AsyncDecodingPropagatesLaterFailureInsteadOfReturningPrefix
        do {
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
        // AsyncDecodingStopsAfterCancellationBeforeNextWindow
        do {
            let calls = Locked(0)
            let task = Task {
                try await AudioChunker.transcribeAsync(Array(repeating: 0.1, count: 60 * 16_000), maxSeconds: 25) { _ in
                    calls.withLock { $0 += 1 }
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "cancelled prefix"
                }
            }
            do {
                _ = try await task.value
                XCTFail("Cancellation must not return a partial transcript")
            } catch is CancellationError {
                XCTAssertEqual(calls.value, 1)
            } catch { XCTFail("Unexpected error: \(error)") }
        }
        // SynchronousDecodingStopsAfterCancellationBeforeNextWindow
        do {
            let calls = Locked(0)
            let task = Task<String, Error> {
                try AudioChunker.transcribe(Array(repeating: 0.1, count: 74 * 16_000), maxSeconds: 25) { _ in
                    if calls.withLock({ $0 += 1; return $0 }) == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                    return "cancelled prefix"
                }
            }
            do {
                _ = try await task.value
                XCTFail("Cancellation must stop later expensive decoder calls")
            } catch is CancellationError {
                XCTAssertEqual(calls.value, 1)
            } catch { XCTFail("Unexpected error: \(error)") }
        }
    }

    // MARK: AD-083 follow-up: window joins (tiny tails are covered by the split test)

    func testWindowsJoinWithoutSpacesBetweenChineseOrJapaneseCharactersInBothDecoders() async throws {
        // WindowsJoinWithoutSpacesBetweenChineseOrJapaneseCharacters
        do {
            XCTAssertEqual(AudioChunker.join(["船室の位置を確認してください。", "氷の中を突き進む"]), "船室の位置を確認してください。氷の中を突き進む")
            XCTAssertEqual(AudioChunker.join(["今天先開會", "然後再討論"]), "今天先開會然後再討論")
            XCTAssertEqual(AudioChunker.join(["カタカナ", "ひらがな", "漢字"]), "カタカナひらがな漢字")
            XCTAssertEqual(AudioChunker.join(["first window.", "Second window"]), "first window. Second window")
            XCTAssertEqual(AudioChunker.join(["我等一下把 PR", "merge 到 main"]), "我等一下把 PR merge 到 main")
            XCTAssertEqual(AudioChunker.join(["部署到 main", "branch 之後"]), "部署到 main branch 之後")
            XCTAssertEqual(AudioChunker.join(["회의를 시작합니다", "다음 안건"]), "회의를 시작합니다 다음 안건", "Korean keeps word spacing")
            XCTAssertEqual(AudioChunker.join(["only"]), "only")
            XCTAssertEqual(AudioChunker.join([]), "")
        }
        // DecodersJoinJapaneseWindowsWithoutASpace
        do {
            let samples = [Float](repeating: 0.1, count: 20 * 16_000)
            var index = 0
            let text = try await AudioChunker.transcribeAsync(samples, maxSeconds: 15) { _ in
                index += 1
                return index == 1 ? "冬に北バルト海を横断する場合は、" : " 船室の位置を確認してください。 "
            }
            XCTAssertEqual(text, "冬に北バルト海を横断する場合は、船室の位置を確認してください。")
            index = 0
            let latin = try AudioChunker.transcribe(samples, maxSeconds: 15) { _ in
                index += 1
                return index == 1 ? "first" : "second"
            }
            XCTAssertEqual(latin, "first second")
        }
    }

}
