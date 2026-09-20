import Security
import XCTest
@testable import AirdraftCore

final class AppIdentityTests: XCTestCase {
    func testDefaultsMigrationPreservesNewValuesAndRunsOnlyOnce() {
        let suite = "airdraft.identity-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("new", forKey: "alreadySet")
        AppIdentity.importLegacyDefaults(into: defaults, legacy: ["alreadySet": "old", "setting": "saved"])
        XCTAssertEqual(defaults.string(forKey: "alreadySet"), "new")
        XCTAssertEqual(defaults.string(forKey: "setting"), "saved")
        defaults.removeObject(forKey: "setting")
        AppIdentity.importLegacyDefaults(into: defaults, legacy: ["setting": "saved"])
        XCTAssertNil(defaults.object(forKey: "setting"))
    }

    func testLegacyCredentialMigratesAndDeletionDoesNotResurrectIt() throws {
        let account = "identity-test.\(UUID().uuidString)"
        defer { Keychain.delete(account) }
        let old: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppIdentity.legacyBundleID,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("fixture-only".utf8),
        ]
        XCTAssertEqual(SecItemAdd(old as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(Keychain.get(account), "fixture-only")
        XCTAssertTrue(Keychain.set("replacement", for: account))
        XCTAssertEqual(Keychain.get(account), "replacement")
        XCTAssertTrue(Keychain.delete(account))
        XCTAssertNil(Keychain.get(account))
    }
}
