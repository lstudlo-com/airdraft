import XCTest
@testable import AirdraftCore

@MainActor
final class DataCleanupTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-cleanup-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testInterruptedScopeResumesOnlyIncompleteStepsAfterRelaunch() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = DataCleanupCoordinator(directory: directory)
        var dataCalls = 0, permissionCalls = 0
        let data = DataCleanupCoordinator.Step("data", title: "Data") { dataCalls += 1 }
        await first.execute(.reset, prepare: {}, steps: [data, .init("permissions", title: "Permissions") {
            permissionCalls += 1; throw PermissionResetError(message: "Injected refusal")
        }])
        XCTAssertTrue(first.blocksWork)
        XCTAssertEqual(first.completedSteps, ["data"])
        let resumed = DataCleanupCoordinator(directory: directory)
        await resumed.execute(.audio, prepare: {}, steps: [])
        XCTAssertEqual(resumed.pendingScope, .reset, "Retry cannot broaden or replace the recorded scope")
        await resumed.execute(.reset, prepare: {}, steps: [data, .init("permissions", title: "Permissions") { permissionCalls += 1 }])
        XCTAssertEqual(dataCalls, 1)
        XCTAssertEqual(permissionCalls, 2)
        XCTAssertEqual(resumed.finishedScope, .reset)
        XCTAssertFalse(resumed.blocksWork)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cleanup.json").path))
    }

    func testBusyPreparationNeverExecutesDeletionOrCreatesJournal() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cleanup = DataCleanupCoordinator(directory: directory)
        var called = false
        await cleanup.execute(.history, prepare: { throw CleanupError.busy }, steps: [.init("data", title: "Data") { called = true }])
        XCTAssertFalse(called)
        XCTAssertFalse(cleanup.blocksWork)
        XCTAssertNil(cleanup.finishedScope)
        XCTAssertNotNil(cleanup.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cleanup.json").path))
    }

    func testCorruptJournalFailsClosed() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not JSON".utf8).write(to: directory.appendingPathComponent("cleanup.json"))
        let cleanup = DataCleanupCoordinator(directory: directory)
        var called = false
        await cleanup.execute(.reset, prepare: { called = true }, steps: [])
        XCTAssertTrue(cleanup.blocksWork)
        XCTAssertFalse(called)
    }

    func testResetContentsPreservesJournalLockAndExternalSymlinkTarget() throws {
        let directory = try root(), outside = try root()
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: outside) }
        for name in ["history.sqlite", "dictionary.json", "cleanup.json", ".airdraft-data.lock"] {
            try Data(name.utf8).write(to: directory.appendingPathComponent(name))
        }
        let original = outside.appendingPathComponent("original.wav")
        try Data([1, 2, 3]).write(to: original)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("external"), withDestinationURL: outside)
        try ManagedDataFiles.resetContents(in: directory)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(["cleanup.json", ".airdraft-data.lock"]))
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
        let link = directory.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try ManagedDataFiles.resetContents(in: link))
    }

    func testLifetimeLeaseRejectsSecondWriterUntilOwnerIsReleased() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner: DataDirectoryLease? = try DataDirectoryLease(directory: directory)
        XCTAssertEqual(owner?.holdsLease, true)
        XCTAssertThrowsError(try DataDirectoryLease(directory: directory))
        try ManagedDataFiles.resetContents(in: directory)
        XCTAssertThrowsError(try DataDirectoryLease(directory: directory), "Reset must retain the same exclusive lock inode")
        owner = nil
        let replacement = try DataDirectoryLease(directory: directory)
        XCTAssertTrue(replacement.holdsLease)
        XCTAssertThrowsError(try DataDirectoryLease(directory: directory))
    }

    func testDistinctDirectoriesCanHaveIndependentWriters() throws {
        let firstRoot = try root(), secondRoot = try root()
        defer { try? FileManager.default.removeItem(at: firstRoot); try? FileManager.default.removeItem(at: secondRoot) }
        let first = try DataDirectoryLease(directory: firstRoot)
        let second = try DataDirectoryLease(directory: secondRoot)
        XCTAssertTrue(first.holdsLease && second.holdsLease)
    }

    func testPreferenceResetUsesOnlyDisposableDomainAndBlocksLegacyReimport() {
        let suite = "airdraft.cleanup-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("private settings", forKey: "settings.asr")
        defaults.set("window location", forKey: "NSWindow Frame Test")
        AppResetAdapters.resetPreferences(in: defaults, domains: [suite])
        AppIdentity.importLegacyDefaults(into: defaults, legacy: ["settings.asr": "must not return"])
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?.keys.sorted(), ["airdraft.legacyDefaultsImported"])
    }

}
