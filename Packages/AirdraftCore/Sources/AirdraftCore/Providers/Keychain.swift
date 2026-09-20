import Foundation
import Security

/// Minimal generic-password wrapper. One service, many accounts.
public enum Keychain {
    public static let service = AppIdentity.bundleID

    public static func get(_ account: String) -> String? {
        if let value = read(account, service: service) { return value }
        guard let legacy = read(account, service: AppIdentity.legacyBundleID) else { return nil }
        // Keep the old item until the user explicitly removes the credential.
        _ = set(legacy, for: account)
        return legacy
    }

    private static func read(_ account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else { return delete(account) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let value = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        let attrs = query.merging(value) { _, new in new }
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public static func delete(_ account: String) -> Bool {
        let current = remove(account, service: service)
        let legacy = remove(account, service: AppIdentity.legacyBundleID)
        return current && legacy
    }

    private static func remove(_ account: String, service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
