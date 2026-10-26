import AirdraftCore
import XCTest

/// Settings search state: the delayed query, previous/next, clearing and the
/// rule that copy changes rebuild the index without moving a settled selection.
@MainActor
final class SettingsSearchStateTests: XCTestCase {
    private let documents: [SettingsSearchDocument] = [
        .init(section: "Keyboard shortcuts", title: "Trigger Delay", detail: "Short presses keep their normal action"),
        .init(section: "Updates", title: "Check automatically", detail: "Once a day"),
        .init(section: "Updates", title: "Download updates automatically", detail: "Installs when you quit"),
        .init(section: "Appearance", title: "Text size", detail: "Default, Large or Larger"),
    ]

    /// Typing does not search until the query is applied; a whitespace-only query is not a search.
    func testTypingSearchesOnlyOnceAppliedAndWhitespaceIsNotASearch() {
        do {
            let search = SettingsSearchState()
            search.replaceDocuments(documents)
            search.query = "updates"
            XCTAssertTrue(search.isSearching)
            XCTAssertTrue(search.matches.isEmpty)
            XCTAssertEqual(search.queryPasses, 1)
            search.applyQuery()
            XCTAssertEqual(search.matches.map(\.title), ["Check automatically", "Download updates automatically"])
            XCTAssertEqual(search.selectedID, documents[1].id)
            XCTAssertEqual(search.selectedIndex, 0)
            XCTAssertEqual(search.matchedIDs, [documents[1].id, documents[2].id])
            XCTAssertEqual(search.queryPasses, 2)
            // Applying the same query again does no work.
            search.applyQuery()
            XCTAssertEqual(search.queryPasses, 2)
        }

        do {
            let search = SettingsSearchState()
            search.query = "  \n"
            XCTAssertFalse(search.isSearching)
        }
    }

    /// Each phase has its own state: next/previous wrap and request scrolling, moving applies a
    /// pending query first, no match has no selection, and clearing ends the search.
    func testNavigationWrapsAppliesPendingQueriesHandlesNoMatchAndClears() {
        do {
            let search = SettingsSearchState()
            search.replaceDocuments(documents)
            search.query = "automatically"
            search.applyQuery()
            let scrolls = search.scrollRequest
            search.move(by: 1)
            XCTAssertEqual(search.selectedID, documents[2].id)
            search.move(by: 1)
            XCTAssertEqual(search.selectedID, documents[1].id)
            search.move(by: -1)
            XCTAssertEqual(search.selectedID, documents[2].id)
            XCTAssertEqual(search.scrollRequest, scrolls + 3)
        }

        do {
            let search = SettingsSearchState()
            search.replaceDocuments(documents)
            search.query = "text size"
            search.move(by: 1)
            XCTAssertEqual(search.appliedQuery, "text size")
            XCTAssertEqual(search.selectedID, documents[3].id)
        }

        do {
            let search = SettingsSearchState()
            search.replaceDocuments(documents)
            search.query = "impossible"
            search.applyQuery()
            XCTAssertTrue(search.matches.isEmpty)
            XCTAssertNil(search.selectedID)
            XCTAssertNil(search.selectedIndex)
            let scrolls = search.scrollRequest
            search.move(by: 1)
            XCTAssertEqual(search.scrollRequest, scrolls)
        }

        do {
            let search = SettingsSearchState()
            search.replaceDocuments(documents)
            search.query = "updates"
            search.applyQuery()
            search.clear()
            XCTAssertEqual(search.query, "")
            XCTAssertFalse(search.isSearching)
            XCTAssertTrue(search.matches.isEmpty)
            XCTAssertNil(search.selectedID)
        }
    }

    func testIndexRebuildsOnlyWhenCopyChangesAndKeepsTheSelection() {
        let search = SettingsSearchState()
        search.replaceDocuments(documents)
        XCTAssertEqual(search.indexBuilds, 1)
        search.replaceDocuments(documents)
        XCTAssertEqual(search.indexBuilds, 1, "identical copy must not rebuild the index")

        search.query = "automatically"
        search.applyQuery()
        search.move(by: 1)
        XCTAssertEqual(search.selectedID, documents[2].id)
        let scrolls = search.scrollRequest

        // Copy elsewhere changes: the settled selection stays and nothing scrolls.
        var changed = documents
        changed[0] = .init(section: "Keyboard shortcuts", title: "Trigger Delay", detail: "Hold to start")
        search.replaceDocuments(changed)
        XCTAssertEqual(search.indexBuilds, 2)
        XCTAssertEqual(search.selectedID, documents[2].id)
        XCTAssertEqual(search.scrollRequest, scrolls)

        // The selected setting disappears: selection falls back to the first match.
        search.replaceDocuments(Array(changed.prefix(2)))
        XCTAssertEqual(search.matches.map(\.title), ["Check automatically"])
        XCTAssertEqual(search.selectedID, documents[1].id)
    }
}
