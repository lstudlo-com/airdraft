import XCTest
import Security
@testable import AirdraftCore

// Excluded from the credential-free allowlist, including synthetic credential fixtures.
final class CredentialRemovalTests: XCTestCase {
    func testCredentialRemovalNeverReadsValuesOrDeletesLicenseAndIsRetryable() throws {
        var removed: [String] = []
        var removal = ProviderCredentialRemoval()
        removal.services = ["fixture.current", "fixture.legacy"]
        removal.list = { query in
            XCTAssertNil(query[kSecReturnData as String])
            XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
            return (errSecSuccess, [[kSecAttrAccount as String: "provider-token"], [kSecAttrAccount as String: "license.fixture.v1"]])
        }
        removal.remove = { query in
            removed.append(query[kSecAttrAccount as String] as! String)
            XCTAssertTrue((query[kSecAttrService as String] as! String).hasPrefix("fixture."))
            return errSecSuccess
        }
        try removal.run()
        XCTAssertEqual(removed, ["provider-token", "provider-token"])
        removal.remove = { _ in errSecInteractionNotAllowed }
        XCTAssertThrowsError(try removal.run())
        removal.remove = { _ in errSecItemNotFound }
        XCTAssertNoThrow(try removal.run())
    }
}
