import AppKit
import ApplicationServices
import XCTest
@testable import AirdraftCore

@MainActor
final class TextInsertionTests: XCTestCase {
    func testEditorWithOnlySelectedTextRangesStillExposesItsCaret() throws {
        var caret = CFRange(location: 7, length: 0)
        let range = try XCTUnwrap(AXValueCreate(.cfRange, &caret))
        let selection = TextInserter.selection { attribute in
            if attribute as String == kAXSelectedTextRangesAttribute as String {
                return (.success, [range] as CFArray)
            }
            return (.attributeUnsupported, nil)
        }
        XCTAssertTrue(TextInserter.selectionMatches(caret, selection),
                      "An editor's supported selection must not be reported as a changed destination")
    }

    func testSelectionFallbackRejectsMultipleCaretsMalformedRangesAndTransportErrors() throws {
        var caret = CFRange(location: 7, length: 0)
        let valid = try XCTUnwrap(AXValueCreate(.cfRange, &caret))
        var invalid = CFRange(location: Int.max, length: 1)
        let overflow = try XCTUnwrap(AXValueCreate(.cfRange, &invalid))
        let unusable: [CFTypeRef] = [[] as CFArray, [valid, valid] as CFArray, [overflow] as CFArray,
                                    ["not a range"] as CFArray, "not an array" as CFString]
        for ranges in unusable {
            let result = TextInserter.selection { attribute in
                attribute as String == kAXSelectedTextRangeAttribute as String
                    ? (.attributeUnsupported, nil) : (.success, ranges)
            }
            XCTAssertNil(result)
        }
        for status: AXError in [.cannotComplete, .failure, .apiDisabled, .invalidUIElement] {
            XCTAssertNil(TextInserter.selection { attribute in
                XCTAssertEqual(attribute as String, kAXSelectedTextRangeAttribute as String,
                               "A transport failure must not authorize insertion through a second attribute")
                return (status, nil)
            })
        }
    }

    func testCaptureWaitsForTheWebEditorToExposeItsRealFieldAndCaret() async throws {
        let field = AXUIElementCreateApplication(123)
        let caret = CFRange(location: 7, length: 0)
        var enabled = false
        var reads = 0
        let target = await TextInserter.captureTarget(processID: 123, bundleID: "test.editor", isFrontmost: { true },
            readFocus: {
                reads += 1
                return enabled && reads >= 3 ? (field, caret) : (nil, nil)
            }, enableWebAccessibility: {
                enabled = true
                return true
            })
        let captured = try XCTUnwrap(target)
        XCTAssertTrue(enabled)
        XCTAssertEqual(reads, 3)
        XCTAssertTrue(CFEqual(try XCTUnwrap(captured.element), field))
        XCTAssertTrue(TextInserter.selectionMatches(caret, captured.selection))
    }

    func testCaptureKeepsNativeSelectionAndDoesNotEnableWebAccessibility() async throws {
        let field = AXUIElementCreateApplication(123)
        let caret = CFRange(location: 2, length: 3)
        let target = await TextInserter.captureTarget(processID: 123, bundleID: "test.editor", isFrontmost: { true },
            readFocus: { (field, caret) }, enableWebAccessibility: {
                XCTFail("Native text fields need no web accessibility changes")
                return false
            })
        XCTAssertTrue(TextInserter.selectionMatches(caret, try XCTUnwrap(target).selection))
    }

    func testCaptureNeverSubstitutesAnotherAppOrAnUnknownSelection() async throws {
        var frontmost = true
        let target = await TextInserter.captureTarget(processID: 123, bundleID: "test.editor", isFrontmost: { frontmost },
            readFocus: { (nil, nil) }, enableWebAccessibility: {
                frontmost = false
                return false
            })
        XCTAssertNil(target)

        let unknown = await TextInserter.captureTarget(processID: 123, bundleID: "test.editor", isFrontmost: { true },
            readFocus: { (AXUIElementCreateApplication(123), nil) }, enableWebAccessibility: { false })
        XCTAssertFalse(TextInserter.selectionMatches(try XCTUnwrap(unknown).selection, nil))
    }

    func testFocusRestorationWaitsForTheFieldAndSelectionAfterAppActivation() async {
        var reads = 0
        let restored = await TextInserter.waitForMatch {
            reads += 1
            return reads == 3
        }
        XCTAssertTrue(restored)
        XCTAssertEqual(reads, 3)
        let changed = await TextInserter.waitForMatch(timeout: .milliseconds(25)) { false }
        XCTAssertFalse(changed)

        let cancelled = Task { @MainActor in
            await TextInserter.waitForMatch {
                XCTFail("Cancelled focus restoration must not inspect or authorize a destination")
                return true
            }
        }
        cancelled.cancel()
        let result = await cancelled.value
        XCTAssertFalse(result)
    }

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

    func testCancellationAfterPostingKeepsClipboardUntilReceiverCanRead() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Old clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.restoreDelay = 0.15
        let posted = expectation(description: "Paste posted")
        var posts = 0
        let task = Task { @MainActor in
            await inserter.insertViaPaste("Dictation", pasteboard: pasteboard, postPaste: {
                posts += 1
                posted.fulfill()
                return true
            })
        }
        await fulfillment(of: [posted], timeout: 1)
        task.cancel()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictation",
                       "Cancelling a posted paste must not replace the receiving app's input")
        let succeeded = await task.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "Old clipboard")
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
