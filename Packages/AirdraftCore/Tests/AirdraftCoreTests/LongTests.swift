import Foundation

/// Everyday runs shorten tests that model hours of audio; releases set
/// `AIRDRAFT_LONG_TESTS=1` (through `TEST_RUNNER_AIRDRAFT_LONG_TESTS`) and run
/// the full lengths.
enum LongTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["AIRDRAFT_LONG_TESTS"] == "1" }
}
