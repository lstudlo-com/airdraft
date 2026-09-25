import XCTest
@testable import AirdraftCore

@MainActor
final class LocalPersistenceTests: XCTestCase {
    func testAliasUndoPreservesAliasesAndEditsAddedAfterRemoval() throws {
        try withFolder { folder in
            let store = DictionaryStore(directory: folder)
            let snapshot = DictionaryEntry(term: "Airdraft", aliases: ["a", "b"])
            store.add(snapshot)
            store.removeAlias("a", from: snapshot.id)
            var edited = try XCTUnwrap(store.entries.first)
            edited.aliases.append("c")
            edited.term = "AIRDRAFT"
            edited.caseSensitive = true
            store.update(edited)
            store.restore(snapshot)
            let restored = try XCTUnwrap(DictionaryStore(directory: folder).entries.first)
            XCTAssertEqual(restored.aliases, ["a", "b", "c"])
            XCTAssertEqual(restored.term, "AIRDRAFT")
            XCTAssertTrue(restored.caseSensitive)
        }
    }

    func testVocabularyCreateEditDeleteRestorePersistsExactUnicodeAndCase() throws {
        try withFolder { folder in
            let store = DictionaryStore(directory: folder)
            var entry = DictionaryEntry(term: "Airdraft 測試", aliases: ["air draft", "氣流"], caseSensitive: true)
            store.add(entry)
            XCTAssertEqual(DictionaryStore(directory: folder).entries, [entry])
            entry.term = "測試 $1 \\ text"
            entry.aliases = ["air draft", "air draught"]
            entry.caseSensitive = false
            store.update(entry)
            XCTAssertEqual(DictionaryStore(directory: folder).entries, [entry])
            store.removeAlias("air draft", from: entry.id)
            XCTAssertEqual(DictionaryStore(directory: folder).entries[0].aliases, ["air draught"])
            store.restore(entry)
            XCTAssertEqual(DictionaryStore(directory: folder).entries, [entry])
            store.remove(id: entry.id)
            XCTAssertTrue(DictionaryStore(directory: folder).entries.isEmpty)
            store.restore(entry)
            XCTAssertEqual(DictionaryStore(directory: folder).entries, [entry])
            XCTAssertNil(store.persistenceError)
        }
    }

    func testUnreadableVocabularyIsPreservedBeforeNewEntriesAreSaved() throws {
        try withFolder { folder in
            let original = Data("malformed vocabulary fixture".utf8)
            let file = folder.appendingPathComponent("dictionary.json")
            try original.write(to: file)
            let store = DictionaryStore(directory: folder)
            XCTAssertNotNil(store.persistenceError)
            let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            XCTAssertEqual(backups.count, 1)
            XCTAssertNotEqual(backups[0], file)
            XCTAssertEqual(try Data(contentsOf: backups[0]), original)
            let entry = DictionaryEntry(term: "Recovered")
            store.add(entry)
            XCTAssertNil(store.persistenceError)
            XCTAssertEqual(DictionaryStore(directory: folder).entries, [entry])
            XCTAssertEqual(try Data(contentsOf: backups[0]), original)
        }
    }

    func testUnreadableProfilesPreserveOriginalAndResetCanPersist() throws {
        try withFolder { folder in
            let original = Data("malformed profile fixture".utf8)
            let file = folder.appendingPathComponent("profiles.json")
            try original.write(to: file)
            let store = ProfileStore(directory: folder)
            XCTAssertNotNil(store.persistenceError)
            XCTAssertEqual(store.profiles, RefinementProfile.defaults)
            let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            XCTAssertEqual(backups.count, 1)
            XCTAssertNotEqual(backups[0], file)
            XCTAssertEqual(try Data(contentsOf: backups[0]), original)
            store.resetAll()
            XCTAssertNil(store.persistenceError)
            XCTAssertEqual(ProfileStore(directory: folder).profiles, RefinementProfile.defaults)
            XCTAssertEqual(try Data(contentsOf: backups[0]), original)
        }
    }

    func testProfileCreationNamesAndSelectionSurviveResetAndReload() throws {
        try withFolder { folder in
            let store = ProfileStore(directory: folder)
            let first = store.addNew()
            let second = store.addNew()
            XCTAssertEqual(first.name, "Clean copy")
            XCTAssertEqual(second.name, "Clean copy 2")
            store.setActive(RefinementProfile.verbatimID)
            let fromRaw = store.addNew()
            XCTAssertEqual(fromRaw.name, "New profile")
            XCTAssertTrue(fromRaw.usesLLM)
            store.setActive(first.id)
            store.resetProfile(id: RefinementProfile.cleanID)
            let reloaded = ProfileStore(directory: folder)
            XCTAssertEqual(reloaded.activeProfileID, first.id)
            XCTAssertEqual(reloaded.profiles.filter { !$0.isBuiltIn }, [first, second, fromRaw])
            reloaded.setActive(UUID())
            XCTAssertEqual(reloaded.activeProfileID, first.id)
        }
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-persistence-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }
}
