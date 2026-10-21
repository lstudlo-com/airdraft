import XCTest
@testable import AirdraftCore

final class CLIWarmPoolTests: XCTestCase {
    func testSameKeyCannotCrossRecordingOwnersAndStaleCleanupCannotStopNewSession() async throws {
        let pool = CLIWarmPool()
        let firstOwner = UUID(), secondOwner = UUID()
        let first = try makeSession("exec /bin/sleep 30")
        let second = try makeSession("exec /bin/sleep 30")
        defer { first.stop(); second.stop() }
        await pool.prewarm(key: first.key, owner: firstOwner) { first }
        let wrongOwner = await pool.take(key: first.key, owner: secondOwner)
        XCTAssertNil(wrongOwner)
        await pool.prewarm(key: second.key, owner: secondOwner) { second }
        try await waitForExit(first)
        await pool.discard(owner: firstOwner)
        XCTAssertTrue(second.isAlive)
        let taken = await pool.take(key: second.key, owner: secondOwner)
        XCTAssertTrue(taken === second)
    }

    func testOwnerCleanupStopsUnconsumedWarmSession() async throws {
        let pool = CLIWarmPool()
        let owner = UUID()
        let session = try makeSession("exec /bin/sleep 30")
        defer { session.stop() }
        await pool.prewarm(key: session.key, owner: owner) { session }
        await pool.discard(owner: owner)
        try await waitForExit(session)
        let taken = await pool.take(key: session.key, owner: owner)
        XCTAssertNil(taken)
    }

    func testCancelledPreparationCannotLeaveNewWarmProcess() async throws {
        let pool = CLIWarmPool()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await pool.prewarm(key: "cancelled", owner: UUID()) {
                XCTFail("Cancelled warm preparation must not launch a process")
                return try self.makeSession("exec /bin/sleep 30", key: "cancelled")
            }
        }
        await cancelled.value
        let taken = await pool.take(key: "cancelled")
        XCTAssertNil(taken)
    }

    func testChangingWarmKeyReplacesPreviousSession() async throws {
        let pool = CLIWarmPool()
        let first = try makeSession("exec /bin/sleep 30", key: "first-profile")
        let second = try makeSession("exec /bin/sleep 30", key: "second-profile")
        defer { first.stop(); second.stop() }
        await pool.prewarm(key: first.key) { first }
        await pool.prewarm(key: second.key) { second }
        let taken = await pool.take(key: second.key)
        XCTAssertTrue(taken === second)
        try await waitForExit(first)
        await pool.shutdown()
    }

    func testUnchangedWarmKeyKeepsExistingSession() async throws {
        let pool = CLIWarmPool()
        let first = try makeSession("exec /bin/sleep 30")
        let unused = try makeSession("exec /bin/sleep 30")
        defer { first.stop(); unused.stop() }
        await pool.prewarm(key: first.key) { first }
        await pool.prewarm(key: first.key) { unused }
        let taken = await pool.take(key: first.key)
        XCTAssertTrue(taken === first)
        await pool.shutdown()
    }

    func testWarmSessionAcceptsSuccessAndSkipsProgressLines() async throws {
        let session = try makeSession("read line; printf '%s\\n' '{\"type\":\"system\"}' '{\"type\":\"result\",\"is_error\":false,\"result\":\"完成\"}'; exec /bin/sleep 30")
        let result = try await CLIProcess.blocking { try session.send("literal $(not-executed)\n中文", timeout: 2) }
        XCTAssertEqual(result, "完成")
        try await waitForExit(session)
    }

    func testWarmErrorResultCannotBecomeDictationText() async throws {
        let session = try makeSession("read line; printf '%s\\n' '{\"type\":\"result\",\"is_error\":true,\"result\":\"fixture failed\"}'")
        do {
            _ = try await CLIProcess.blocking { try session.send("text", timeout: 2) }
            XCTFail("An error result must preserve the raw-transcript fallback")
        } catch RefinerError.http(_, let body) {
            XCTAssertEqual(body, "fixture failed")
        }
        try await waitForExit(session)
    }

    func testWarmErrorPreservesErrorsAfterLargeMetadata() async throws {
        let metadata = String(repeating: "m", count: 800)
        let session = try makeSession("read line; printf '%s\\n' '{\"type\":\"result\",\"is_error\":true,\"metadata\":\"\(metadata)\",\"errors\":[\"Subscription unavailable\"]}'")
        do {
            _ = try await CLIProcess.blocking { try session.send("text", timeout: 2) }
            XCTFail("An error must not become dictation text")
        } catch RefinerError.http(_, let body) {
            XCTAssertEqual(body, "Subscription unavailable")
        }
        try await waitForExit(session)
    }

    func testWarmDeadlineIncludesBlockedInput() async throws {
        let session = try makeSession("exec /bin/sleep 30")
        let started = Date()
        do {
            _ = try await CLIProcess.blocking {
                try session.send(String(repeating: "x", count: 8_388_608), timeout: 0.2)
            }
            XCTFail("Expected timeout")
        } catch RefinerError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        try await waitForExit(session)
    }

    func testWarmSessionDrainsOutputWhileSendingLargeInput() async throws {
        let session = try makeSession("/usr/bin/head -c 262144 /dev/zero; printf '\\n'; read line; printf '%s\\n' '{\"type\":\"result\",\"result\":\"complete\"}'")
        let result = try await CLIProcess.blocking {
            try session.send(String(repeating: "x", count: 262_144), timeout: 5)
        }
        XCTAssertEqual(result, "complete")
        try await waitForExit(session)
    }

    func testStoppedWarmSessionCannotWriteOrReturnOutput() async throws {
        let session = try makeSession("exec /bin/sleep 30")
        session.stop()
        do {
            _ = try await CLIProcess.blocking { try session.send("text", timeout: 2) }
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        try await waitForExit(session)
    }

    func testWarmCancellationInterruptsBlockedInput() async throws {
        let session = try makeSession("exec /bin/sleep 30")
        let operation = Task {
            try await withTaskCancellationHandler {
                try await CLIProcess.blocking {
                    try session.send(String(repeating: "x", count: 8_388_608), timeout: 10)
                }
            } onCancel: { session.stop() }
        }
        try await Task.sleep(for: .milliseconds(100))
        let started = Date()
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        try await waitForExit(session)
    }

    func testWarmEarlyExitDoesNotRaiseSIGPIPE() async throws {
        let session = try makeSession("exit 0")
        do {
            _ = try await CLIProcess.blocking {
                try session.send(String(repeating: "x", count: 8_388_608), timeout: 2)
            }
            XCTFail("Expected incomplete input")
        } catch CLIProcess.Failure.incompleteInput {}
        try await waitForExit(session)
    }

    func testWarmMissingResultIsRejected() async throws {
        let session = try makeSession("read line; printf '%s\\n' '{\"type\":\"system\"}'")
        do {
            _ = try await CLIProcess.blocking { try session.send("text", timeout: 2) }
            XCTFail("Expected invalid response")
        } catch RefinerError.invalidResponse {}
        try await waitForExit(session)
    }

    /// A long recording must not lose its warm session to the unowned idle limit.
    func testOwnedSessionOutlivesUnownedIdleLimitUntilTheRecordingCapAndProcessing() async throws {
        let clock = TestClock()
        let pool = CLIWarmPool(now: { clock.now })
        let owner = UUID()
        let owned = try makeSession("exec /bin/sleep 30", key: "owned")
        let unowned = try makeSession("exec /bin/sleep 30", key: "unowned")
        let expiring = try makeSession("exec /bin/sleep 30", key: "expiring")
        defer { owned.stop(); unowned.stop(); expiring.stop() }

        await pool.prewarm(key: owned.key, owner: owner) { owned }
        clock.advance(590)  // a recording close to the 600-second cap
        let taken = await pool.take(key: owned.key, owner: owner)
        XCTAssertTrue(taken === owned, "An owned warm session must survive a long recording")

        await pool.prewarm(key: unowned.key) { unowned }
        clock.advance(181)
        let stale = await pool.take(key: unowned.key)
        XCTAssertNil(stale, "Unowned warm sessions keep the 180-second idle limit")
        try await waitForExit(unowned)

        await pool.prewarm(key: expiring.key, owner: owner) { expiring }
        clock.advance(TimeInterval(SpeechInputLimits.recordingSecondsRange.upperBound) + CLIWarmPool.ownedSessionProcessingSeconds + 1)
        let leaked = await pool.take(key: expiring.key, owner: owner)
        XCTAssertNil(leaked, "An owned session still has a hard lifetime bound")
        try await waitForExit(expiring)
    }

    private func makeSession(_ script: String, key: String = "fixture") throws -> CLISession {
        try CLISession(key: key, executable: "/bin/sh", arguments: ["-c", script],
                       environment: [:], workDir: FileManager.default.temporaryDirectory)
    }

    private func waitForExit(_ session: CLISession) async throws {
        for _ in 0..<200 where session.isAlive { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.isAlive)
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}
