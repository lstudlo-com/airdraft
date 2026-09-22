import XCTest
@testable import AirdraftCore

@MainActor
final class ProfileStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stt-profiles-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testDefaultsAndActive() {
        let store = ProfileStore(directory: tempDir())
        XCTAssertEqual(store.profiles.map(\.name), ["Clean", "Concise", "Summary", "Verbatim"])
        XCTAssertEqual(store.activeProfile.id, RefinementProfile.cleanID)
        XCTAssertTrue(store.baseRulesAreDefault)
    }

    func testEditPersistsAndResetRestores() {
        let dir = tempDir()
        let store = ProfileStore(directory: dir)
        var concise = store.profiles[1]
        concise.instructions = "Shorter."
        store.update(concise)
        store.setBaseRules("custom base")
        store.setActive(RefinementProfile.summaryID)

        let reloaded = ProfileStore(directory: dir)
        XCTAssertEqual(reloaded.profiles[1].instructions, "Shorter.")
        XCTAssertEqual(reloaded.baseRules, "custom base")
        XCTAssertEqual(reloaded.activeProfileID, RefinementProfile.summaryID)
        XCTAssertFalse(reloaded.isDefault(reloaded.profiles[1]))

        reloaded.resetProfile(id: RefinementProfile.conciseID)
        XCTAssertTrue(reloaded.isDefault(reloaded.profiles[1]))
        reloaded.resetBaseRules()
        XCTAssertTrue(reloaded.baseRulesAreDefault)
    }

    func testUserProfilesCanBeAddedAndRemovedButBuiltInsCannot() {
        let store = ProfileStore(directory: tempDir())
        let custom = store.add(RefinementProfile(name: "Email", instructions: "Write an email."))
        XCTAssertEqual(store.profiles.count, 5)
        XCTAssertFalse(custom.isBuiltIn)
        store.setActive(custom.id)
        store.remove(id: custom.id)
        XCTAssertEqual(store.profiles.count, 4)
        XCTAssertEqual(store.activeProfileID, RefinementProfile.cleanID)
        store.remove(id: RefinementProfile.cleanID)
        XCTAssertEqual(store.profiles.count, 4)
    }

    func testResetAllRemovesUserProfilesAndRestoresDefaults() {
        let store = ProfileStore(directory: tempDir())
        store.add(RefinementProfile(name: "X", instructions: "x"))
        var clean = store.profiles[0]
        clean.name = "Renamed"
        store.update(clean)
        store.resetAll()
        XCTAssertEqual(store.profiles, RefinementProfile.defaults)
        XCTAssertEqual(store.activeProfileID, RefinementProfile.cleanID)
    }

    func testDuplicateUsesSelectedProfileAndPreservesRawBehaviorAfterReload() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        var source = store.profiles[3]
        source.task = "Remembered task"
        source.instructions = "Remembered instructions"
        source.symbol = "doc.text"
        store.update(source)

        let copy = try XCTUnwrap(store.duplicate(id: source.id))
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertFalse(copy.isBuiltIn)
        XCTAssertFalse(copy.usesLLM)
        XCTAssertEqual(copy.task, source.task)
        XCTAssertEqual(copy.instructions, source.instructions)
        XCTAssertEqual(copy.symbol, source.symbol)
        XCTAssertEqual(copy.name, "Verbatim copy")
        XCTAssertEqual(store.duplicate(id: source.id)?.name, "Verbatim copy 2")
        XCTAssertEqual(store.activeProfileID, RefinementProfile.cleanID)
        XCTAssertEqual(ProfileStore(directory: dir).profiles.first { $0.id == copy.id }, copy)
        XCTAssertNil(store.duplicate(id: UUID()))
    }
}
