import AirdraftCore
import XCTest

/// Settings > Appearance > Language (AD-137). The store never touches the real
/// preference here: it writes the same value macOS keeps for a per-app language.
@MainActor
final class InterfaceLanguageStoreTests: XCTestCase {
    /// Following the Mac needs no relaunch; choosing another language stores it as the
    /// per-app list and asks for one; choosing the launch language again or System
    /// Default (when the Mac shows that language) clears the request.
    func testSelectionStoresThePerAppLanguageAndOffersRelaunchOnlyWhenItChanges() {
        var written: [[String]?] = []
        var stored: [String]?
        let storage = InterfaceLanguageStore.Storage(read: { stored }, write: { stored = $0; written.append($0) },
                                                     system: { ["en-TW", "zh-Hant-TW"] })
        let store = InterfaceLanguageStore(storage: storage, launchLanguage: "en")
        XCTAssertNil(store.selection)
        XCTAssertFalse(store.needsRelaunch, "System Default already shows English")

        let japanese = InterfaceLanguage.shipped.first { $0.code == "ja" }
        store.select(japanese)
        XCTAssertEqual(stored, ["ja"])
        XCTAssertEqual(store.nextLaunchLanguage, "ja")
        XCTAssertTrue(store.needsRelaunch)
        XCTAssertEqual(InterfaceLanguageStore(storage: storage, launchLanguage: "en").selection, japanese,
                       "The choice survives a relaunch")

        store.select(InterfaceLanguage.shipped.first { $0.code == "en" })
        XCTAssertEqual(stored, ["en"])
        XCTAssertFalse(store.needsRelaunch)

        store.select(nil)
        XCTAssertNil(stored, "System Default removes the per-app language")
        XCTAssertFalse(store.needsRelaunch)
        store.select(nil)
        XCTAssertEqual(written.count, 3, "An unchanged choice writes nothing")
    }

    /// A launch shown in Traditional Chinese because of an earlier per-app choice offers
    /// a relaunch when System Default would show the Mac's English.
    func testSystemDefaultAfterAPerAppChoiceOffersRelaunch() {
        var stored: [String]? = ["zh-Hant"]
        let storage = InterfaceLanguageStore.Storage(read: { stored }, write: { stored = $0 },
                                                     system: { ["en-US"] })
        let store = InterfaceLanguageStore(storage: storage, launchLanguage: "zh-Hant")
        XCTAssertEqual(store.selection?.code, "zh-Hant")
        XCTAssertFalse(store.needsRelaunch)
        store.select(nil)
        XCTAssertEqual(store.nextLaunchLanguage, "en")
        XCTAssertTrue(store.needsRelaunch)
    }

    /// Isolated containers keep the choice in memory and never offer a relaunch for System Default.
    func testIsolatedContainersUseMemoryStorage() {
        let isolated = IsolatedContainer()
        defer { isolated.tearDown() }
        let store = isolated.container.interfaceLanguage
        XCTAssertNil(store.selection)
        XCTAssertFalse(store.needsRelaunch)
        let memory = InterfaceLanguageStore(storage: .memory(launchLanguage: "es"), launchLanguage: "es")
        XCTAssertFalse(memory.needsRelaunch)
        memory.select(InterfaceLanguage.shipped.first { $0.code == "zh-Hans" })
        XCTAssertTrue(memory.needsRelaunch)
    }
}
