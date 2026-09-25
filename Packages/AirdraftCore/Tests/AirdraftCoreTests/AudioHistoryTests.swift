import Foundation
import GRDB
import XCTest
@testable import AirdraftCore

final class AudioHistoryTests: XCTestCase {
    private var directory: URL!
    private var recordings: URL { directory.appendingPathComponent("Recordings", isDirectory: true) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func record(date: Date = Date()) -> DictationRecord {
        DictationRecord(createdAt: date, mode: "clean", family: "document", rawTranscript: "original words",
                        refinedText: "Original words.", finalText: "Original words.", asrEngine: "test",
                        audioSeconds: 0.5, asrMs: 1, llmMs: 1, inserted: true)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: recordings.path).sorted()
    }

    private func changeReference(id: Int64, to filename: String) throws {
        let db = try DatabaseQueue(path: directory.appendingPathComponent("history.sqlite").path)
        try db.write { db in
            try db.execute(sql: "UPDATE dictation SET audioFilename = ? WHERE id = ?", arguments: [filename, id])
        }
    }

    func testV1MigrationPreservesTextAndStartsWithoutAudio() throws {
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        do {
            let db = try DatabaseQueue(path: databaseURL.path)
            var migration = DatabaseMigrator()
            migration.registerMigration("v1") { db in
                try db.execute(sql: """
                    CREATE TABLE dictation (
                        id INTEGER PRIMARY KEY AUTOINCREMENT, createdAt DATETIME NOT NULL,
                        appBundleId TEXT, appName TEXT, windowTitle TEXT, url TEXT,
                        mode TEXT NOT NULL, family TEXT NOT NULL, rawTranscript TEXT NOT NULL,
                        refinedText TEXT NOT NULL, finalText TEXT NOT NULL, language TEXT,
                        asrEngine TEXT NOT NULL, llmEngine TEXT, promptVersion TEXT,
                        audioSeconds DOUBLE NOT NULL, asrMs INTEGER NOT NULL,
                        llmMs INTEGER NOT NULL, inserted BOOLEAN NOT NULL, error TEXT
                    );
                    INSERT INTO dictation
                        (createdAt, mode, family, rawTranscript, refinedText, finalText,
                         asrEngine, audioSeconds, asrMs, llmMs, inserted)
                    VALUES ('2026-09-01 12:00:00.000', 'clean', 'document', 'old text',
                            'Old text.', 'Old text.', 'legacy', 1.5, 20, 30, 1);
                    """)
            }
            try migration.migrate(db)
        }
        let store = try HistoryStore(directory: directory)
        let migrated = try XCTUnwrap(store.recent().first)
        XCTAssertEqual(migrated.finalText, "Old text.")
        XCTAssertEqual(migrated.asrEngine, "legacy")
        XCTAssertEqual(migrated.audioSeconds, 1.5)
        XCTAssertNil(migrated.audioFilename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordings.path))
        let withAudio = try store.save(record(), samples: [0, 0.5, -0.5])
        XCTAssertNotNil(store.audioURL(for: withAudio))
        XCTAssertEqual(try store.count(), 2)
    }

    func testWAVRoundTripAndPrivatePermissions() throws {
        let store = try HistoryStore(directory: directory)
        let input: [Float] = [-1, -0.5, 0, 0.5, 1]
        let saved = try store.save(record(), samples: input)
        let url = try XCTUnwrap(store.audioURL(for: saved))
        XCTAssertNotNil(UUID(uuidString: url.deletingPathExtension().lastPathComponent))
        XCTAssertEqual(url.pathExtension, "wav")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, recordings.standardizedFileURL)
        XCTAssertEqual(try store.recent().first?.audioFilename, saved.audioFilename)
        let output = try store.audioSamples(for: saved)
        XCTAssertEqual(output.count, input.count)
        for (actual, expected) in zip(output, input) { XCTAssertEqual(actual, expected, accuracy: 0.0001) }
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: recordings.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual(try files(), [url.lastPathComponent], "No temporary write remains")
    }

    func testTextOnlyAndInMemorySavesDoNotAttachSuppliedPaths() throws {
        let store = try HistoryStore(directory: directory)
        var supplied = record()
        supplied.audioFilename = "\(UUID().uuidString).wav"
        XCTAssertNil(try store.save(supplied).audioFilename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordings.path))
        let memory = try HistoryStore(inMemory: true)
        let saved = try memory.save(supplied, samples: [0, 0.5])
        XCTAssertNil(saved.audioFilename)
        XCTAssertNil(memory.audioURL(for: saved))
        XCTAssertThrowsError(try memory.audioSamples(for: saved))
        try memory.pruneAudio(olderThan: nil)
        XCTAssertEqual(try memory.count(), 1)
    }

    func testMissingAudioReferencesAreClearedWithoutDeletingText() throws {
        let store = try HistoryStore(directory: directory)
        let saved = try store.save(record(), samples: [0, 0.5])
        try FileManager.default.removeItem(at: XCTUnwrap(store.audioURL(for: saved)))
        XCTAssertNil(store.audioURL(for: saved))
        XCTAssertThrowsError(try store.audioSamples(for: saved))
        try store.pruneAudio(olderThan: Date.distantPast)
        XCTAssertNil(try store.recent().first?.audioFilename)
        XCTAssertEqual(try store.recent().first?.finalText, saved.finalText)
    }

    func testTraversalAndSymlinkFilesAreNeverReadOrDeleted() throws {
        let store = try HistoryStore(directory: directory)
        let saved = try store.save(record(), samples: [0, 0.5])
        let outside = directory.appendingPathComponent("\(UUID().uuidString).wav")
        let contents = WAVEncoder.encode(samples: [0.25])
        try contents.write(to: outside)
        for filename in ["../\(outside.lastPathComponent)", outside.path, "sub/\(outside.lastPathComponent)"] {
            var forged = saved
            forged.audioFilename = filename
            XCTAssertNil(store.audioURL(for: forged))
            XCTAssertThrowsError(try store.audioSamples(for: forged))
        }
        let link = recordings.appendingPathComponent("\(UUID().uuidString).wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        var linked = saved
        linked.audioFilename = link.lastPathComponent
        XCTAssertNil(store.audioURL(for: linked))
        XCTAssertThrowsError(try store.audioSamples(for: linked))
        try changeReference(id: XCTUnwrap(saved.id), to: "../\(outside.lastPathComponent)")
        try store.pruneAudio(olderThan: nil)
        XCTAssertNil(try store.recent().first?.audioFilename)
        XCTAssertEqual(try Data(contentsOf: outside), contents)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), outside.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordings.appendingPathComponent(saved.audioFilename!).path))
    }

    func testSymlinkRecordingDirectoryCannotRedirectStorageOrCleanup() throws {
        let store = try HistoryStore(directory: directory)
        let outside = directory.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let protected = outside.appendingPathComponent("\(UUID().uuidString).wav")
        try Data([1, 2, 3]).write(to: protected)
        try FileManager.default.createSymbolicLink(at: recordings, withDestinationURL: outside)
        XCTAssertThrowsError(try store.save(record(), samples: [0, 0.5]))
        XCTAssertThrowsError(try store.pruneAudio(olderThan: nil))
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(try Data(contentsOf: protected), Data([1, 2, 3]))
    }

    func testRetentionRemovesOldAudioAndOrphansButPreservesUnrelatedFiles() throws {
        let store = try HistoryStore(directory: directory)
        let now = Date()
        let old = try store.save(record(date: now.addingTimeInterval(-100)), samples: [0, 0.5])
        let recent = try store.save(record(date: now), samples: [0, -0.5])
        let orphan = recordings.appendingPathComponent("\(UUID().uuidString).wav")
        let unfinished = recordings.appendingPathComponent("\(UUID().uuidString).pending")
        let unrelated = recordings.appendingPathComponent("notes.txt")
        for url in [orphan, unfinished, unrelated] { try Data([1]).write(to: url) }
        let unrelatedDirectory = recordings.appendingPathComponent("\(UUID().uuidString).wav", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: false)
        try Data([2]).write(to: unrelatedDirectory.appendingPathComponent("keep"))
        try store.pruneAudio(olderThan: now.addingTimeInterval(-50))
        XCTAssertNil(store.audioURL(for: old))
        XCTAssertNotNil(store.audioURL(for: recent))
        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try store.recent().filter { $0.audioFilename != nil }.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unfinished.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedDirectory.appendingPathComponent("keep").path))
        try store.pruneAudio(olderThan: nil)
        XCTAssertNil(store.audioURL(for: recent))
        XCTAssertEqual(try store.count(), 2)
        XCTAssertTrue(try store.recent().allSatisfy { $0.audioFilename == nil })
    }

    func testDeleteAndDeleteAllRemoveAudioAndRetainUnrelatedFiles() throws {
        let store = try HistoryStore(directory: directory)
        let first = try store.save(record(), samples: [0, 0.5])
        let second = try store.save(record(), samples: [0, -0.5])
        let unrelated = recordings.appendingPathComponent("keep.txt")
        try Data([42]).write(to: unrelated)
        try store.delete(id: XCTUnwrap(first.id))
        XCTAssertNil(store.audioURL(for: first))
        XCTAssertNotNil(store.audioURL(for: second))
        XCTAssertEqual(try store.count(), 1)
        try store.deleteAll()
        XCTAssertNil(store.audioURL(for: second))
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(try files(), ["keep.txt"])
    }

    func testFailedInsertCleansItsNewSidecar() throws {
        let store = try HistoryStore(directory: directory)
        let saved = try store.save(record(), samples: [0, 0.5])
        XCTAssertThrowsError(try store.save(saved, samples: [0, -0.5]), "Duplicate primary key must fail")
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try files(), [try XCTUnwrap(saved.audioFilename)])
        XCTAssertNotNil(store.audioURL(for: saved))
        XCTAssertThrowsError(try store.save(record(), samples: [.nan]))
        XCTAssertEqual(try files(), [try XCTUnwrap(saved.audioFilename)])
    }

    func testConcurrentStoresDoNotPruneAnInFlightSaveAsAnOrphan() throws {
        let first = try HistoryStore(directory: directory)
        let second = try HistoryStore(directory: directory)
        let input = record()
        let errorsLock = NSLock()
        var errors: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 60) { index in
            do {
                if index.isMultiple(of: 3) {
                    try second.pruneAudio(olderThan: Date.distantPast)
                } else {
                    let store = index.isMultiple(of: 2) ? first : second
                    try store.save(input, samples: [0, 0.5, -0.5])
                }
            } catch { errorsLock.withLock { errors.append(error) } }
        }
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        let saved = try first.recent()
        XCTAssertEqual(saved.count, 40)
        XCTAssertTrue(saved.allSatisfy { first.audioURL(for: $0) != nil })
        XCTAssertEqual(try files(), saved.compactMap(\.audioFilename).sorted())
    }

    func testDeletionFailureKeepsRecordAndCanBeRetried() throws {
        let store = try HistoryStore(directory: directory)
        let saved = try store.save(record(), samples: [0, 0.5])
        let url = try XCTUnwrap(store.audioURL(for: saved))
        let bytes = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let protected = url.appendingPathComponent("keep")
        try Data([42]).write(to: protected)
        XCTAssertThrowsError(try store.delete(id: XCTUnwrap(saved.id)))
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.recent().first?.audioFilename, saved.audioFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: protected.path))
        try FileManager.default.removeItem(at: url)
        try bytes.write(to: url)
        try store.delete(id: XCTUnwrap(saved.id))
        XCTAssertEqual(try store.count(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
