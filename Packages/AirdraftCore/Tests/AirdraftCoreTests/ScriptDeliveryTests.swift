import XCTest
@testable import AirdraftCore

final class ScriptDeliveryTests: XCTestCase {
    /// Text and path are literal, the working directory is the script's parent, and a
    /// successful noisy script may discard its bounded output.
    func testLiteralDeliveryFromScriptParentIncludingNoisyOutput() async throws {
        let fixture = try ScriptFixture(body: "/bin/cat > received.txt\n/usr/bin/printf '%s' \"$#\" > argc.txt\n/bin/pwd > cwd.txt\n", name: "delivery ; $(literal).sh")
        defer { fixture.remove() }
        let text = "繁體中文🙂\n'quoted' \"double\" $HOME; $(touch injected) `touch injected`\nlast line"
        XCTAssertNil(ScriptDelivery.unavailableReason(path: fixture.script.path))
        try await ScriptDelivery.send(text: text, to: fixture.script.path)
        XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent("received.txt")), Data(text.utf8))
        XCTAssertEqual(try fixture.read("argc.txt"), "0")
        let actualDirectory = URL(fileURLWithPath: try fixture.read("cwd.txt").trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(actualDirectory.resolvingSymlinksInPath(), fixture.directory.resolvingSymlinksInPath())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("injected").path))

        let noisy = try ScriptFixture(body: "/bin/cat > received.txt\n/usr/bin/head -c 2000000 /dev/zero\n")
        defer { noisy.remove() }
        try await ScriptDelivery.send(text: "received exactly once", to: noisy.script.path)
        XCTAssertEqual(try noisy.read("received.txt"), "received exactly once")
    }

    func testUnavailablePathsFailBeforeLaunching() async throws {
        let fixture = try ScriptFixture(body: "touch must-not-run\n", executable: false)
        defer { fixture.remove() }
        for path in ["relative.sh", "", "/tmp/no-script-\(UUID().uuidString)", fixture.directory.path, fixture.script.path] {
            XCTAssertNotNil(ScriptDelivery.unavailableReason(path: path))
            do {
                try await ScriptDelivery.send(text: "text", to: path)
                XCTFail("Expected unavailable path: \(path)")
            } catch ScriptDelivery.Failure.unavailable(_) {}
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("must-not-run").path))
    }

    /// A nonzero exit (bounded details), a timeout and cancellation each run once and are never retried.
    func testNonzeroExitTimeoutAndCancellationAreBoundedAndNotRetried() async throws {
        let fixture = try ScriptFixture(body: "/bin/cat >/dev/null\nprintf 'attempt\\n' >> attempts.txt\n/usr/bin/head -c 5000 /dev/zero | /usr/bin/tr '\\0' E >&2\nexit 17\n")
        defer { fixture.remove() }
        do {
            try await ScriptDelivery.send(text: "literal", to: fixture.script.path)
            XCTFail("Expected script failure")
        } catch ScriptDelivery.Failure.exited(let status, let detail) {
            XCTAssertEqual(status, 17)
            XCTAssertEqual(detail.count, 300)
        }
        XCTAssertEqual(try fixture.read("attempts.txt"), "attempt\n")

        let slow = try ScriptFixture(body: "printf 'attempt\\n' >> attempts.txt\nexec /bin/sleep 30\n")
        defer { slow.remove() }
        let started = Date()
        do {
            // One second lets the script start even when parallel test clones load the Mac.
            try await ScriptDelivery.send(text: "text", to: slow.script.path, timeout: 1)
            XCTFail("Expected timeout")
        } catch ScriptDelivery.Failure.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(try slow.read("attempts.txt"), "attempt\n")

        let cancelled = try ScriptFixture(body: "printf 'attempt\\n' >> attempts.txt\nexec /bin/sleep 30\n")
        defer { cancelled.remove() }
        let task = Task { try await ScriptDelivery.send(text: "text", to: cancelled.script.path) }
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: cancelled.directory.appendingPathComponent("attempts.txt").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(try cancelled.read("attempts.txt"), "attempt\n")
    }
}

private struct ScriptFixture {
    let directory: URL
    let script: URL

    init(body: String, name: String = "delivery.sh", executable: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-script-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        script = directory.appendingPathComponent(name)
        try Data(("#!/bin/sh\nset -eu\n" + body).utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o700 : 0o600], ofItemAtPath: script.path)
    }

    func read(_ name: String) throws -> String { try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
