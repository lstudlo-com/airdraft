import Security
import XCTest
@testable import AirdraftCore

final class KeychainAccessTests: XCTestCase {
    func testPresenceUsesOnlyMetadataAndNeverMigrates() {
        var calls = 0
        let store = CredentialStore(copy: { query in
            calls += 1
            XCTAssertNil(query[kSecReturnData as String])
            XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
            var allowed: DarwinBoolean = true
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertFalse(allowed.boolValue)
            return (errSecSuccess, [:])
        }, add: { _ in XCTFail("No migration during inspection"); return errSecSuccess })
        XCTAssertEqual(store.presence("llm.example"), .saved)
        XCTAssertEqual(calls, 1)
    }

    func testDeniedCurrentKeyNeverFallsBackOrMutates() {
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled, errSecNotAvailable] {
            var calls = 0
            let store = CredentialStore(copy: { _ in calls += 1; return (status, nil) },
                                        add: { _ in XCTFail("Must not add"); return errSecSuccess },
                                        update: { _, _ in XCTFail("Must not overwrite"); return errSecSuccess })
            XCTAssertThrowsError(try store.read("llm.example"))
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(store.presence("llm.example"), .unavailable)
        }
    }

    func testPassiveLegacyReadDoesNotWriteAndExplicitImportAddsOnly() throws {
        var adds = 0
        let store = CredentialStore(copy: { query in
            let legacy = query[kSecAttrService as String] as? String == AppIdentity.legacyBundleID
            return legacy ? (errSecSuccess, Data("old-fixture".utf8)) : (errSecItemNotFound, nil)
        }, add: { _ in adds += 1; return errSecSuccess },
        update: { _, _ in XCTFail("Migration must not overwrite"); return errSecSuccess })
        XCTAssertEqual(try store.read("llm.example"), "old-fixture")
        XCTAssertEqual(adds, 0)
        XCTAssertEqual(try store.read("llm.example", allowInteraction: true), "old-fixture")
        XCTAssertEqual(adds, 1)
    }

    func testConcurrentCurrentKeyWinsOverLegacyImport() throws {
        var reads = 0
        let store = CredentialStore(copy: { _ in
            reads += 1
            return reads == 1 ? (errSecItemNotFound, nil) : (errSecSuccess, Data((reads == 2 ? "old" : "new").utf8))
        }, add: { _ in errSecDuplicateItem },
        update: { _, _ in XCTFail("Must never overwrite raced key"); return errSecSuccess })
        XCTAssertEqual(try store.read("llm.example", allowInteraction: true), "new")
    }

    func testFailedUpdateDoesNotCreateReplacement() {
        let store = CredentialStore(add: { _ in XCTFail("Must not add after denied update"); return errSecSuccess },
                                    update: { _, _ in errSecAuthFailed })
        XCTAssertFalse(store.set("replacement", for: "llm.example"))
    }

    func testFailedLegacyDeletePreservesCurrentKey() {
        var services: [String] = []
        let store = CredentialStore(remove: { query in
            services.append(query[kSecAttrService as String] as! String)
            return errSecAuthFailed
        })
        XCTAssertFalse(store.delete("llm.example"))
        XCTAssertEqual(services, [AppIdentity.legacyBundleID])
    }

    func testInteractionPolicyRestoredEvenWhenOperationThrows() throws {
        var before: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&before), errSecSuccess)
        XCTAssertThrowsError(try CredentialStore.withInteraction(false) {
            throw Keychain.AccessError.failure(errSecDecode)
        })
        var after: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&after), errSecSuccess)
        XCTAssertEqual(before.boolValue, after.boolValue)
    }

    func testMalformedCurrentKeyDoesNotFallBack() {
        var calls = 0
        let store = CredentialStore(copy: { _ in calls += 1; return (errSecSuccess, Data([0xff])) })
        XCTAssertThrowsError(try store.read("llm.example"))
        XCTAssertEqual(calls, 1)
    }

    func testDeniedCredentialEngineReportsRecoveryForBothStages() async {
        let engine = CredentialFailureEngine(id: "test", error: Keychain.AccessError.authorizationRequired)
        do {
            _ = try await engine.transcribe(samples: [0], hints: .init())
            XCTFail("Must not transcribe without access")
        } catch { XCTAssertEqual(error as? Keychain.AccessError, .authorizationRequired) }
        do {
            _ = try await engine.refine(.init(transcript: "sample", profile: RefinementProfile.defaults[0], context: .empty, family: .general, dictionary: []))
            XCTFail("Must report refinement failure to raw-transcript fallback")
        } catch { XCTAssertEqual(error as? Keychain.AccessError, .authorizationRequired) }
    }
}

@MainActor
final class CredentialEditorTests: XCTestCase {
    func testDeniedReadIsNotMissingAndEmptySaveCannotDelete() async {
        let editor = CredentialEditor(read: { _, allowed in
            XCTAssertFalse(allowed)
            throw Keychain.AccessError.authorizationRequired
        }, write: { _, _ in XCTFail("An unread key must not be deleted"); return true })
        await editor.load(account: "llm.example")
        XCTAssertTrue(editor.needsAccess)
        XCTAssertFalse(editor.canSave)
        await editor.save()
        XCTAssertTrue(editor.needsAccess)
    }

    func testExplicitApprovalRequestsOnlyTheSelectedAccount() async {
        let editor = CredentialEditor(read: { account, allowed in
            XCTAssertEqual(account, "llm.selected")
            if allowed { return "fixture" }
            throw Keychain.AccessError.authorizationRequired
        })
        await editor.load(account: "llm.selected")
        await editor.authorize()
        XCTAssertFalse(editor.needsAccess)
        XCTAssertEqual(editor.savedValue, "fixture")
    }

    func testSaveFailureKeepsDraftAndDoesNotClaimSuccess() async {
        let editor = CredentialEditor(read: { _, _ in "original" }, write: { _, _ in false })
        await editor.load(account: "llm.example")
        editor.value = "replacement"
        await editor.save()
        XCTAssertTrue(editor.failed)
        XCTAssertEqual(editor.savedValue, "original")
        XCTAssertEqual(editor.value, "replacement")
        XCTAssertTrue(editor.canSave)
    }

    func testProviderSwitchRejectsLateRead() async {
        let gate = ReadGate()
        let editor = CredentialEditor(read: { account, _ in
            if account == "old" { return await gate.wait() }
            return "new-key"
        })
        let old = Task { await editor.load(account: "old") }
        await gate.waitUntilStarted()
        await editor.load(account: "new")
        await gate.finish()
        await old.value
        XCTAssertEqual(editor.value, "new-key")
        XCTAssertFalse(editor.isBusy)
    }

    func testCancellationDiscardsReadResult() async {
        let gate = ReadGate()
        let editor = CredentialEditor(read: { _, _ in await gate.wait() })
        let load = Task { await editor.load(account: "old") }
        await gate.waitUntilStarted()
        editor.cancel()
        await gate.finish()
        await load.value
        XCTAssertEqual(editor.value, "")
        XCTAssertFalse(editor.isBusy)
    }
}

private actor ReadGate {
    private var continuation: CheckedContinuation<String?, Never>?
    func wait() async -> String? { await withCheckedContinuation { continuation = $0 } }
    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() { continuation?.resume(returning: "old-key"); continuation = nil }
}
