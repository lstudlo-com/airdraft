// Rename the existing Keychain item in place. Never read or export its secret.
import Foundation
import Security

let service = "https://sparkle-project.org"
let account = "com.lstudlo.app.airdraft.sparkle"
func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: account]
}
let existing = SecItemCopyMatching(query(account) as CFDictionary, nil)
if existing == errSecSuccess {
    print("Sparkle signing account is already current.")
} else if existing == errSecItemNotFound {
    let status = SecItemUpdate(query("com.lightiichen.transcribar.sparkle") as CFDictionary,
                              [kSecAttrAccount as String: account] as CFDictionary)
    guard status == errSecSuccess else {
        fputs("Could not rename the Sparkle key: \(status). Restore the existing release key; do not generate a replacement.\n", stderr)
        exit(1)
    }
    print("Sparkle signing account renamed. Private key unchanged.")
} else {
    fputs("Could not access the Sparkle key: \(existing).\n", stderr)
    exit(1)
}
