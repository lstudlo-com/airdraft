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
}
