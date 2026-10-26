import LocalAuthentication
import Security
import XCTest
@testable import AirdraftCore

/// Reads the file-based keychain's process-wide switch that `CredentialStore`
/// scopes; the API has no non-deprecated equivalent for file-based items.
@diagnose(DeprecatedDeclaration, as: ignored)
private func fileKeychainInteractionAllowed() -> Bool {
    var allowed: DarwinBoolean = true
    XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
    return allowed.boolValue
}

private func forbidsInteraction(_ query: [String: Any]) -> Bool {
    (query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true
}

final class KeychainAccessTests: XCTestCase {
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

    func testPassiveReadsForbidUINeverFallBackOrMutateAndOnlyExplicitAccessMayAuthorize() throws {
        // Presence uses only metadata and never migrates.
        do {
            var calls = 0
            let store = CredentialStore(copy: { query in
                calls += 1
                XCTAssertNil(query[kSecReturnData as String])
                XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
                XCTAssertFalse(fileKeychainInteractionAllowed())
                XCTAssertTrue(forbidsInteraction(query), "Metadata queries must carry a no-UI context")
                XCTAssertNil(query[kSecUseDataProtectionKeychain as String], "Items stay in the file-based login keychain")
                return (errSecSuccess, [:])
            }, add: { _ in XCTFail("No migration during inspection"); return errSecSuccess })
            XCTAssertEqual(store.presence("llm.example"), .saved)
            XCTAssertEqual(calls, 1)
        }

        // A denied current key never falls back or mutates.
        do {
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

        // A malformed current key does not fall back.
        do {
            var calls = 0
            let store = CredentialStore(copy: { _ in calls += 1; return (errSecSuccess, Data([0xff])) })
            XCTAssertThrowsError(try store.read("llm.example"))
            XCTAssertEqual(calls, 1)
        }

        // Only explicit access reads may show authorization UI.
        do {
            var contexts: [Bool] = []
            let store = CredentialStore(copy: { query in
                contexts.append(forbidsInteraction(query))
                XCTAssertEqual(fileKeychainInteractionAllowed(), !forbidsInteraction(query))
                return (errSecSuccess, Data("fixture".utf8))
            })
            XCTAssertEqual(try store.read("llm.example"), "fixture")
            XCTAssertEqual(try store.read("llm.example", allowInteraction: true), "fixture")
            XCTAssertEqual(contexts, [true, false], "Passive reads forbid UI; Allow access may authorize")
        }
    }

    func testLegacyImportAddsOnlyOnExplicitReadAndNeverOverwritesACurrentKey() throws {
        // A passive legacy read does not write; explicit import adds only.
        do {
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

        // A concurrent current key wins over legacy import.
        do {
            var reads = 0
            let store = CredentialStore(copy: { _ in
                reads += 1
                return reads == 1 ? (errSecItemNotFound, nil) : (errSecSuccess, Data((reads == 2 ? "old" : "new").utf8))
            }, add: { _ in errSecDuplicateItem },
            update: { _, _ in XCTFail("Must never overwrite raced key"); return errSecSuccess })
            XCTAssertEqual(try store.read("llm.example", allowInteraction: true), "new")
        }
    }

    func testWritesAndDeletesNeverAllowInteractionOrReplaceOnFailure() throws {
        // A failed update does not create a replacement.
        do {
            let store = CredentialStore(add: { _ in XCTFail("Must not add after denied update"); return errSecSuccess },
                                        update: { _, _ in errSecAuthFailed })
            XCTAssertFalse(store.set("replacement", for: "llm.example"))
        }

        // Passive writes never allow interaction for update, add or delete.
        do {
            func assertNoInteraction() { XCTAssertFalse(fileKeychainInteractionAllowed()) }
            // All credential operations are injected. No real item is read or changed.
            let store = CredentialStore(add: { attributes in
                    assertNoInteraction()
                    XCTAssertNil(attributes[kSecUseAuthenticationContext as String], "Add takes attributes, not a search context")
                    return errSecSuccess
                },
                update: { query, _ in assertNoInteraction(); XCTAssertTrue(forbidsInteraction(query)); return errSecItemNotFound },
                remove: { query in assertNoInteraction(); XCTAssertTrue(forbidsInteraction(query)); return errSecSuccess })
            XCTAssertTrue(store.set("receipt", for: "fixture", allowInteraction: false))
            XCTAssertTrue(store.delete("fixture", allowInteraction: false))
            let denied = CredentialStore(add: { _ in XCTFail("Must not add after denied update"); return errSecSuccess },
                update: { _, _ in assertNoInteraction(); return errSecInteractionNotAllowed })
            XCTAssertFalse(denied.set("receipt", for: "fixture", allowInteraction: false))
        }

        // A failed legacy delete preserves the current key.
        do {
            var services: [String] = []
            let store = CredentialStore(remove: { query in
                services.append(query[kSecAttrService as String] as! String)
                return errSecAuthFailed
            })
            XCTAssertFalse(store.delete("llm.example"))
            XCTAssertEqual(services, [AppIdentity.legacyBundleID])
        }

        // The interaction policy is restored even when the operation throws.
        do {
            let before = fileKeychainInteractionAllowed()
            XCTAssertThrowsError(try CredentialStore.withInteraction(false) {
                throw Keychain.AccessError.failure(errSecDecode)
            })
            XCTAssertEqual(before, fileKeychainInteractionAllowed())
        }
    }
}

@MainActor
final class CredentialEditorTests: XCTestCase {
    func testDeniedReadExplicitApprovalAndSaveFailureKeepEditorStateHonest() async {
        // A denied read is not missing, and an empty save cannot delete.
        do {
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

        // Explicit approval requests only the selected account.
        do {
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

        // A save failure keeps the draft and does not claim success.
        do {
            let editor = CredentialEditor(read: { _, _ in "original" }, write: { _, _ in false })
            await editor.load(account: "llm.example")
            editor.value = "replacement"
            await editor.save()
            XCTAssertTrue(editor.failed)
            XCTAssertEqual(editor.savedValue, "original")
            XCTAssertEqual(editor.value, "replacement")
            XCTAssertTrue(editor.canSave)
        }
    }

    func testProviderSwitchAndCancellationDiscardLateReads() async {
        // A provider switch rejects a late read.
        do {
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

        // Cancellation discards the read result.
        do {
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
}

private actor ReadGate {
    private var continuation: CheckedContinuation<String?, Never>?
    func wait() async -> String? { await withCheckedContinuation { continuation = $0 } }
    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }
    func finish() { continuation?.resume(returning: "old-key"); continuation = nil }
}
