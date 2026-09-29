import XCTest
@testable import AirdraftCore

final class CLIProcessTests: XCTestCase {
    func testLiteralInputRoundTripsWhileOutputIsDrained() async throws {
        let process = makeProcess("/bin/cat")
        let text = String(repeating: "繁體中文🙂\n$HOME; 'quoted' $(not-executed)\n", count: 4_000)
        let output = try await CLIProcess.run(process, input: text, timeout: 5)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout, text)
        XCTAssertFalse(output.stdoutTruncated)
        XCTAssertFalse(output.stderrTruncated)
    }

    func testBothOutputStreamsAreBoundedButFullyDrained() async throws {
        let bytes = CLIProcess.outputLimit * 3
        let process = makeProcess("/bin/sh", ["-c", "/usr/bin/head -c \(bytes) /dev/zero; /usr/bin/head -c \(bytes) /dev/zero >&2; /bin/cat >/dev/null"])
        let output = try await CLIProcess.run(process, input: String(repeating: "input", count: 100_000), timeout: 5)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(output.stdout.utf8.count, CLIProcess.outputLimit)
        XCTAssertEqual(output.stderr.utf8.count, CLIProcess.outputLimit)
        XCTAssertTrue(output.stdoutTruncated)
        XCTAssertTrue(output.stderrTruncated)
    }

    func testExitStatusAndStderrArePreserved() async throws {
        let process = makeProcess("/bin/sh", ["-c", "printf 'failure details' >&2; exit 17"])
        let output = try await CLIProcess.run(process, input: "", timeout: 2)
        XCTAssertEqual(output.status, 17)
        XCTAssertEqual(output.stderr, "failure details")
    }

    func testDeadlineBoundsBlockedStdin() async throws {
        let process = makeProcess("/bin/sleep", ["30"])
        let started = Date()
        do {
            _ = try await CLIProcess.run(process, input: String(repeating: "x", count: 8_388_608), timeout: 0.2)
            XCTFail("Expected timeout")
        } catch RefinerError.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        try await waitForExit(process)
    }

    func testParentExitDoesNotDisableDeadlineForInheritedPipes() async throws {
        // The selected shell exits immediately; a short-lived child retains its output pipes.
        let process = makeProcess("/bin/sh", ["-c", "(/bin/sleep 2) & exit 0"])
        let started = Date()
        do {
            _ = try await CLIProcess.run(process, input: "", timeout: 0.25)
            XCTFail("Expected inherited-pipe timeout")
        } catch RefinerError.timeout {}
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testCancellationStopsProcessWithBlockedStdin() async throws {
        let process = makeProcess("/bin/sleep", ["30"])
        let operation = Task { try await CLIProcess.run(process, input: String(repeating: "x", count: 8_388_608), timeout: 10) }
        for _ in 0..<100 where !process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(process.isRunning)
        let started = Date()
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        try await waitForExit(process)
    }

    func testEarlyExitBeforeLargeInputDoesNotRaiseSIGPIPEOrReportDelivery() async throws {
        let process = makeProcess("/usr/bin/true")
        do {
            _ = try await CLIProcess.run(process, input: String(repeating: "x", count: 8_388_608), timeout: 2)
            XCTFail("Expected incomplete stdin delivery")
        } catch CLIProcess.Failure.incompleteInput {}
        XCTAssertFalse(process.isRunning)
    }

    func testMissingExecutableFailsWithoutWaitingForDeadline() async throws {
        let process = makeProcess("/tmp/airdraft-missing-\(UUID().uuidString)")
        let started = Date()
        do {
            _ = try await CLIProcess.run(process, input: "", timeout: 10)
            XCTFail("Expected launch failure")
        } catch CLIProcess.Failure.launchFailed(_) {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testClaudeFailureKeepsTheMessageAfterLargeMetadata() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-cli-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: script) }
        let json = try JSONSerialization.data(withJSONObject: [
            "duration_api_ms": 0, "metadata": String(repeating: "x", count: 800),
            "is_error": true, "result": "Subscription is unavailable. Sign in again."
        ], options: [.sortedKeys])
        let body = "#!/bin/sh\n/bin/cat >/dev/null\nprintf '%s' '\(String(decoding: json, as: UTF8.self))'\nexit 1\n"
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let refiner = CLIRefiner(tool: .claudeCode, executable: script.path, model: "", timeout: 2)
        let request = RefineRequest(transcript: "Test transcript", profile: RefinementProfile.defaults[0],
                                    context: .empty, family: .general, dictionary: [])
        do {
            _ = try await refiner.refine(request)
            XCTFail("A failed CLI must never return text")
        } catch RefinerError.http(let status, let message) {
            XCTAssertEqual(status, 1)
            XCTAssertEqual(message, "Subscription is unavailable. Sign in again.")
        }
    }

    private func makeProcess(_ path: String, _ arguments: [String] = []) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        return process
    }

    private func waitForExit(_ process: Process) async throws {
        for _ in 0..<200 where process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(process.isRunning)
    }
}
