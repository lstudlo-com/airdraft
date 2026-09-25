import AppKit
import ApplicationServices
import XCTest
@testable import AirdraftCore

@MainActor
final class TextInsertionTests: XCTestCase {
    func testUnknownAndChangedSelectionCannotAuthorizeInsertion() {
        let original = CFRange(location: 2, length: 3)
        XCTAssertTrue(TextInserter.selectionMatches(original, original))
        XCTAssertFalse(TextInserter.selectionMatches(nil, original))
        XCTAssertFalse(TextInserter.selectionMatches(original, nil))
        XCTAssertFalse(TextInserter.selectionMatches(nil, nil))
        XCTAssertFalse(TextInserter.selectionMatches(original, CFRange(location: 1, length: 3)))
        XCTAssertFalse(TextInserter.selectionMatches(original, CFRange(location: 2, length: 0)))
        XCTAssertFalse(TextInserter.selectionMatches(CFRange(location: -1, length: 0), CFRange(location: -1, length: 0)))
    }

    func testUTF16ReplacementPreservesMultilingualTextAndRejectsInvalidRanges() {
        let text = "A😀中文e\u{301}Z"
        XCTAssertEqual(TextInserter.replacing(text, range: CFRange(location: 1, length: 2), with: "🙂"), "A🙂中文e\u{301}Z")
        XCTAssertEqual(TextInserter.replacing(text, range: CFRange(location: 3, length: 2), with: "繁體"), "A😀繁體e\u{301}Z")
        XCTAssertEqual(TextInserter.replacing(text, range: CFRange(location: 8, length: 0), with: "!"), text + "!")
        XCTAssertEqual(TextInserter.replacing(text, range: CFRange(location: 0, length: 8), with: ""), "")
        for range in [CFRange(location: -1, length: 0), CFRange(location: 0, length: -1),
                      CFRange(location: Int.max, length: 1), CFRange(location: 1, length: Int.max)] {
            XCTAssertNil(TextInserter.replacing(text, range: range, with: "invalid"))
        }
    }

    func testFocusChangeBeforeAccessibilityWritePreventsTheWrite() {
        var writes = 0
        let result = TextInserter.verifiedWrite(expected: "replacement", isCurrent: { false }, write: {
            writes += 1
            return true
        }, read: { XCTFail("An unattempted write must not be verified"); return nil })

        XCTAssertEqual(result, .notAttempted)
        XCTAssertEqual(writes, 0)
    }

    func testUncertainAccessibilityWriteIsNeverRepeated() {
        for response in [false, true] {
            var writes = 0
            let result = TextInserter.verifiedWrite(expected: "dog", isCurrent: { true }, write: {
                writes += 1
                return response
            }, read: { "cat" })

            XCTAssertEqual(result, .uncertain)
            XCTAssertEqual(writes, 1)
        }
        XCTAssertEqual(TextInserter.verifiedWrite(expected: "dog", isCurrent: { true },
            write: { true }, read: { "dog" }), .inserted)
    }

    func testPasteRestoresAllOriginalItemsAndFormats() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("Original clipboard", forType: .string)
        original.setData(Data([0, 10, 255]), forType: .init("airdraft.test.binary"))
        let second = NSPasteboardItem()
        second.setString("Second item", forType: .string)
        XCTAssertTrue(pasteboard.writeObjects([original, second]))
        let inserter = TextInserter()
        inserter.restoreDelay = 0.02
        var posts = 0

        let success = await inserter.insertViaPaste("Dictated 中文🙂", pasteboard: pasteboard, postPaste: {
            posts += 1
            XCTAssertEqual(pasteboard.string(forType: .string), "Dictated 中文🙂")
            XCTAssertNotNil(pasteboard.data(forType: .init("org.nspasteboard.TransientType")))
            return true
        })

        XCTAssertTrue(success)
        XCTAssertEqual(posts, 1)
        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].string(forType: .string), "Original clipboard")
        XCTAssertEqual(restored[0].data(forType: .init("airdraft.test.binary")), Data([0, 10, 255]))
        XCTAssertEqual(restored[1].string(forType: .string), "Second item")
    }

    func testPasteDoesNotOverwriteNewClipboardOwnership() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Old clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.restoreDelay = 0.02
        let success = await inserter.insertViaPaste("Dictation", pasteboard: pasteboard, postPaste: {
            pasteboard.clearContents()
            pasteboard.setString("User copied something newer", forType: .string)
            return true
        })

        XCTAssertTrue(success)
        XCTAssertEqual(pasteboard.string(forType: .string), "User copied something newer")
    }

    func testFailedPasteKeepsTextAvailableWithoutRetry() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Old clipboard", forType: .string)
        let inserter = TextInserter()
        var posts = 0
        let success = await inserter.insertViaPaste("Recoverable text", pasteboard: pasteboard, postPaste: {
            posts += 1
            return false
        })

        XCTAssertFalse(success)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "Recoverable text")
    }

    func testEmptyClipboardIsRestoredAfterPaste() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let inserter = TextInserter()
        inserter.restoreDelay = 0
        let success = await inserter.insertViaPaste("Dictation", pasteboard: pasteboard, postPaste: { true })

        XCTAssertTrue(success)
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }
}
