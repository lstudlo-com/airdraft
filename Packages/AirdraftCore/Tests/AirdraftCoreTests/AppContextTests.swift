import Foundation
import XCTest
@testable import AirdraftCore

@MainActor
final class AppContextTests: XCTestCase {
    func testContextBoundsPreserveWholeUnicodeCharacters() throws {
        let context = try XCTUnwrap(AppContextReader.surroundingText("🙂abcSELECTxyz🚀",
            range: CFRange(location: 5, length: 6), maxBefore: 4, maxAfter: 4))
        XCTAssertEqual(context.before, "🙂abc")
        XCTAssertEqual(context.after, "xyz🚀")
        XCTAssertFalse(context.before.contains("\u{FFFD}"))
        XCTAssertFalse(context.after.contains("\u{FFFD}"))
    }

    func testContextExcludesSelectionAndHonorsBounds() throws {
        let context = try XCTUnwrap(AppContextReader.surroundingText("beforeSELECTafter",
            range: CFRange(location: 6, length: 6), maxBefore: 3, maxAfter: 2))
        XCTAssertEqual(context.before, "ore")
        XCTAssertEqual(context.after, "af")
        let empty = try XCTUnwrap(AppContextReader.surroundingText("text",
            range: CFRange(location: 2, length: 0), maxBefore: -1, maxAfter: 0))
        XCTAssertEqual(empty.before, "")
        XCTAssertEqual(empty.after, "")
    }

    func testMalformedAXRangesDoNotOverflowOrExposeText() {
        for range in [CFRange(location: -1, length: 0), CFRange(location: 0, length: -1),
                      CFRange(location: Int.max, length: 1), CFRange(location: 1, length: Int.max),
                      CFRange(location: 9, length: 0)] {
            XCTAssertNil(AppContextReader.surroundingText("text", range: range, maxBefore: 1000, maxAfter: 300))
        }
    }

    func testWhitespaceSelectionDoesNotEnableSelectionSpecificRefinement() {
        XCTAssertFalse(AppContext(selectedText: " \n\t ").hasSelection)
        XCTAssertTrue(AppContext(selectedText: " 中文🙂 ").hasSelection)
        XCTAssertFalse(AppContext.empty.hasSelection)
    }
}
