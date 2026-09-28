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

    func testFocusChangeBeforeAccessibilityWritePreventsTheWrite() async {
        var writes = 0
        let result = await TextInserter.verifiedWrite(before: "original", expected: "replacement", isCurrent: { false }, write: {
            writes += 1
            return .success
        }, read: { XCTFail("An unattempted write must not be verified"); return nil })

        XCTAssertEqual(result, .notAttempted)
        XCTAssertEqual(writes, 0)
    }

    func testUncertainAccessibilityWriteIsNeverRepeated() async {
        for response: AXError in [.cannotComplete, .failure, .invalidUIElement, .apiDisabled, .illegalArgument, .success] {
            var writes = 0
            let result = await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: { true }, write: {
                writes += 1
                return response
            }, read: { "cat" }, verificationTimeout: .zero)

            XCTAssertEqual(result, .uncertain)
            XCTAssertEqual(writes, 1)
        }
        let inserted = await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: { true },
            write: { .success }, read: { "dog" })
        XCTAssertEqual(inserted, .inserted)
    }

    func testUnsupportedAccessibilityWriteAllowsPasteOnlyForAnUnchangedDestination() async {
        for response: AXError in [.attributeUnsupported, .notImplemented] {
            for unchangedFocus in [true, false] {
                for value: String? in ["cat", "dog", "edited", nil] {
                    var writes = 0
                    let result = await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: {
                        writes == 0 || unchangedFocus
                    }, write: {
                        writes += 1
                        return response
                    }, read: { value })

                    XCTAssertEqual(result, unchangedFocus && value == "cat" ? .rejected : .uncertain)
                    XCTAssertEqual(writes, 1)
                }
            }
        }
    }

    func testAccessibilityVerificationWaitsForTheValueWithoutRepeatingTheWrite() async {
        var writes = 0
        var reads = 0
        let result = await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: {
            // An accepted replacement moves the caret. The old selection only
            // authorizes the write; verification reads the captured element.
            writes == 0
        }, write: {
            writes += 1
            return .success
        }, read: {
            reads += 1
            switch reads {
            case 1: return "cat"
            case 2: return nil
            default: return "dog"
            }
        })

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(reads, 3)
    }

    func testAccessibilityVerificationDeadlineKeepsAnUnchangedWriteUncertain() async {
        let clock = ContinuousClock()
        let start = clock.now
        var writes = 0
        var reads = 0
        let result = await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: { true }, write: {
            writes += 1
            return .success
        }, read: {
            reads += 1
            return "cat"
        }, verificationTimeout: .milliseconds(50))

        XCTAssertEqual(result, .uncertain)
        XCTAssertEqual(writes, 1)
        XCTAssertGreaterThan(reads, 1)
        XCTAssertGreaterThanOrEqual(start.duration(to: clock.now), .milliseconds(50))
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
    }

    func testCancelledAccessibilityWriteDoesNotTouchTheDestination() async {
        let task = Task { @MainActor in
            await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: { true }, write: {
                XCTFail("Cancelled insertion must not write")
                return .success
            }, read: { XCTFail("Cancelled insertion must not read"); return nil })
        }
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .notAttempted)
    }

    func testCancellationStopsPendingVerificationWithoutAnotherWrite() async {
        let firstRead = expectation(description: "Accessibility value read")
        var writes = 0
        var reads = 0
        let task = Task { @MainActor in
            await TextInserter.verifiedWrite(before: "cat", expected: "dog", isCurrent: { true }, write: {
                writes += 1
                return .success
            }, read: {
                reads += 1
                if reads == 1 { firstRead.fulfill() }
                return "cat"
            }, verificationTimeout: .seconds(5))
        }
        await fulfillment(of: [firstRead], timeout: 1)
        task.cancel()
        let readsAtCancellation = reads

        let result = await task.value
        XCTAssertEqual(result, .uncertain)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(reads, readsAtCancellation)
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
        var deliveryEvents = 0

        let success = await inserter.insertViaPaste("Dictated 中文🙂", pasteboard: pasteboard, postPaste: {
            posts += 1
            XCTAssertEqual(pasteboard.string(forType: .string), "Dictated 中文🙂")
            XCTAssertNotNil(pasteboard.data(forType: .init("org.nspasteboard.TransientType")))
            return true
        }, onDelivered: {
            deliveryEvents += 1
            XCTAssertEqual(posts, 1)
            XCTAssertEqual(pasteboard.string(forType: .string), "Dictated 中文🙂",
                           "Delivery feedback must precede clipboard restoration")
        })

        XCTAssertTrue(success)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(deliveryEvents, 1)
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
        }, onDelivered: {
            XCTFail("Failed paste must not report delivery or dismiss the recovery HUD")
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
