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
        XCTAssertGreaterThanOrEqual(reads, 5, "The newly exposed editor must remain stable across run-loop turns")
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
        }, confirmation: { true }, onDelivered: {
            deliveryEvents += 1
            XCTAssertEqual(posts, 1)
            XCTAssertEqual(pasteboard.string(forType: .string), "Dictated 中文🙂",
                           "Delivery feedback must precede clipboard restoration")
        })

        XCTAssertTrue(success.didInsert)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(deliveryEvents, 1)
        XCTAssertTrue(inserter.hasPendingClipboardRestoration,
                      "Delivery returns before the restore delay so the next dictation can start")
        await inserter.finishClipboardRestoration()
        XCTAssertFalse(inserter.hasPendingClipboardRestoration)
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
        }, confirmation: { true })

        XCTAssertTrue(success.didInsert)
        await inserter.finishClipboardRestoration()
        XCTAssertEqual(pasteboard.string(forType: .string), "User copied something newer")
    }

    func testNewerPasteTakesOverPendingRestoreWithoutClobbering() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("User clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.restoreDelay = 0.15
        let first = await inserter.insertViaPaste("First dictation", pasteboard: pasteboard,
                                                  postPaste: { true }, confirmation: { true })
        XCTAssertTrue(first.didInsert)
        XCTAssertTrue(inserter.hasPendingClipboardRestoration)
        XCTAssertEqual(pasteboard.string(forType: .string), "First dictation")
        // The next dictation pastes before the first restore is due.
        inserter.restoreDelay = 0.4
        var pastedSecond: String?
        let second = await inserter.insertViaPaste("Second dictation", pasteboard: pasteboard, postPaste: {
            pastedSecond = pasteboard.string(forType: .string)
            return true
        }, confirmation: { true })
        XCTAssertTrue(second.didInsert)
        XCTAssertEqual(pastedSecond, "Second dictation")
        // Past the first restore's deadline, the newer paste still owns the clipboard.
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(pasteboard.string(forType: .string), "Second dictation",
                       "An earlier restore must never replace a newer dictation's paste")
        await inserter.finishClipboardRestoration()
        XCTAssertEqual(pasteboard.string(forType: .string), "User clipboard",
                       "The user's clipboard returns, not the earlier transcript")
    }

    /// P3: an unverified paste cannot prove its receiver read the clipboard.
    /// A slow terminal that reads it late must still get that dictation, so the
    /// next paste waits out the receiver window before replacing the clipboard.
    func testNextPasteWaitsOutAnUnverifiedReceiverWindow() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("User clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.restoreDelay = 0
        inserter.unverifiedRestoreDelay = 0.4
        let first = await inserter.insertViaPaste("First dictation", pasteboard: pasteboard,
                                                  postPaste: { true }, unverifiable: true)
        XCTAssertEqual(first.delivery, .sentUnverified)
        let firstPosted = ContinuousClock.now
        // The slow receiver handles its paste event 300 ms later.
        var lateRead: String?
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            lateRead = pasteboard.string(forType: .string)
        }
        var secondPostedAfter: Duration?
        let second = await inserter.insertViaPaste("Second dictation", pasteboard: pasteboard, postPaste: {
            secondPostedAfter = firstPosted.duration(to: .now)
            return true
        }, confirmation: { true })
        XCTAssertTrue(second.didInsert)
        XCTAssertEqual(lateRead, "First dictation", "The late reader gets its own dictation, not the newer one")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(secondPostedAfter), .milliseconds(350),
                                    "The newer paste waits for the unverified receiver window")
        XCTAssertLessThan(try XCTUnwrap(secondPostedAfter), .seconds(2), "The wait stays bounded by that window")
        await inserter.finishClipboardRestoration()
        XCTAssertEqual(pasteboard.string(forType: .string), "User clipboard", "The user's clipboard still returns")
    }

    /// A confirmed paste, or an unverified one whose clipboard the user already
    /// replaced, leaves no receiver to protect: the next paste does not wait.
    func testNextPasteDoesNotWaitWithoutAnUnverifiedReceiver() async throws {
        for replacedByUser in [false, true] {
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            pasteboard.setString("User clipboard", forType: .string)
            let inserter = TextInserter()
            inserter.restoreDelay = 5
            inserter.unverifiedRestoreDelay = 5
            _ = await inserter.insertViaPaste("First dictation", pasteboard: pasteboard, postPaste: { true },
                                              confirmation: replacedByUser ? nil : { true }, unverifiable: replacedByUser)
            if replacedByUser {
                pasteboard.clearContents()
                pasteboard.setString("Copied by the user", forType: .string)
            }
            let started = ContinuousClock.now
            let second = await inserter.insertViaPaste("Second dictation", pasteboard: pasteboard,
                                                       postPaste: { true }, confirmation: { true })
            XCTAssertTrue(second.didInsert)
            XCTAssertLessThan(started.duration(to: .now), .milliseconds(500), "replaced=\(replacedByUser)")
            await inserter.finishClipboardRestoration(immediately: true)
            XCTAssertEqual(pasteboard.string(forType: .string), replacedByUser ? "Copied by the user" : "User clipboard")
        }
    }

    /// Cancellation while waiting posts nothing and leaves the first restore intact.
    func testCancellationWhileWaitingForUnverifiedReceiverPostsNothing() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("User clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.unverifiedRestoreDelay = 0.4
        _ = await inserter.insertViaPaste("First dictation", pasteboard: pasteboard, postPaste: { true }, unverifiable: true)
        var posts = 0
        let task = Task { @MainActor in
            await inserter.insertViaPaste("Second dictation", pasteboard: pasteboard, postPaste: {
                posts += 1
                return true
            }, confirmation: { true })
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result.method, .clipboardOnly)
        XCTAssertEqual(posts, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "First dictation")
        await inserter.finishClipboardRestoration()
        XCTAssertEqual(pasteboard.string(forType: .string), "User clipboard")
    }

    func testPendingRestoreKeepsAClipboardCopiedBeforeTheNextPaste() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("User clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.restoreDelay = 5
        _ = await inserter.insertViaPaste("First dictation", pasteboard: pasteboard,
                                          postPaste: { true }, confirmation: { true })
        pasteboard.clearContents()
        pasteboard.setString("Copied after first dictation", forType: .string)
        inserter.restoreDelay = 0
        _ = await inserter.insertViaPaste("Second dictation", pasteboard: pasteboard,
                                          postPaste: { true }, confirmation: { true })
        await inserter.finishClipboardRestoration()
        XCTAssertEqual(pasteboard.string(forType: .string), "Copied after first dictation")
    }

    func testQuitRestoresConfirmedPasteClipboardWithoutWaitingForDelay() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("User clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.restoreDelay = 30
        _ = await inserter.insertViaPaste("Dictation", pasteboard: pasteboard,
                                          postPaste: { true }, confirmation: { true })
        let started = ContinuousClock.now
        await inserter.finishClipboardRestoration(immediately: true)
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
        XCTAssertFalse(inserter.hasPendingClipboardRestoration)
        XCTAssertEqual(pasteboard.string(forType: .string), "User clipboard")
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

        XCTAssertFalse(success.didInsert)
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
            }, confirmation: { true })
        }
        await fulfillment(of: [posted], timeout: 1)
        task.cancel()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictation",
                       "Cancelling a posted paste must not replace the receiving app's input")
        let succeeded = await task.value
        XCTAssertTrue(succeeded.didInsert)
        XCTAssertEqual(posts, 1)
        await inserter.finishClipboardRestoration()
        XCTAssertEqual(pasteboard.string(forType: .string), "Old clipboard")
    }

    func testEmptyClipboardIsRestoredAfterPaste() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let inserter = TextInserter()
        inserter.restoreDelay = 0
        let success = await inserter.insertViaPaste("Dictation", pasteboard: pasteboard,
                                                  postPaste: { true }, confirmation: { true })

        XCTAssertTrue(success.didInsert)
        await inserter.finishClipboardRestoration()
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    func testUnconfirmedPasteDoesNotOverwriteNewClipboardOrClaimItKeptText() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let inserter = TextInserter()
        inserter.confirmationTimeout = .milliseconds(25)
        let result = await inserter.insertViaPaste("Dictation", pasteboard: pasteboard, postPaste: {
            pasteboard.clearContents()
            pasteboard.setString("Newer copy", forType: .string)
            return true
        }, confirmation: { false })
        XCTAssertFalse(result.didInsert)
        XCTAssertEqual(result.notice, "Paste couldn't be confirmed. Clipboard changed; recover your text from History.")
        XCTAssertEqual(pasteboard.string(forType: .string), "Newer copy")
    }

    func testCancellationAfterUnconfirmedPasteKeepsRecoveryText() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Old clipboard", forType: .string)
        let inserter = TextInserter()
        inserter.confirmationTimeout = .milliseconds(100)
        let posted = expectation(description: "Paste posted")
        var posts = 0
        let task = Task { @MainActor in
            await inserter.insertViaPaste("Dictation", pasteboard: pasteboard, postPaste: {
                posts += 1
                posted.fulfill()
                return true
            }, confirmation: { false }, onDelivered: { XCTFail("No acknowledgement") })
        }
        await fulfillment(of: [posted], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.didInsert)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "Dictation")
    }
}
