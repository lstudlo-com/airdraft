import XCTest
@testable import AirdraftCore

final class ScriptDeliveryTests: XCTestCase {
    func testTextAndPathAreLiteralAndWorkingDirectoryIsScriptParent() async throws {
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

    func testNonzeroExitHasBoundedDetailsAndIsNotRetried() async throws {
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
    }

    func testTimeoutIsBoundedAndNotRetried() async throws {
        let fixture = try ScriptFixture(body: "printf 'attempt\\n' >> attempts.txt\nexec /bin/sleep 30\n")
        defer { fixture.remove() }
        let started = Date()
        do {
            try await ScriptDelivery.send(text: "text", to: fixture.script.path, timeout: 0.2)
            XCTFail("Expected timeout")
        } catch ScriptDelivery.Failure.timeout {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(try fixture.read("attempts.txt"), "attempt\n")
    }

    func testCancellationIsPreservedAndNotRetried() async throws {
        let fixture = try ScriptFixture(body: "printf 'attempt\\n' >> attempts.txt\nexec /bin/sleep 30\n")
        defer { fixture.remove() }
        let task = Task { try await ScriptDelivery.send(text: "text", to: fixture.script.path) }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("attempts.txt").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(try fixture.read("attempts.txt"), "attempt\n")
    }

    func testSuccessfulNoisyScriptMayDiscardBoundedOutput() async throws {
        let fixture = try ScriptFixture(body: "/bin/cat > received.txt\n/usr/bin/head -c 2000000 /dev/zero\n")
        defer { fixture.remove() }
        try await ScriptDelivery.send(text: "received exactly once", to: fixture.script.path)
        XCTAssertEqual(try fixture.read("received.txt"), "received exactly once")
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
