import Foundation
import Security

/// Login-keychain credentials. Passive access never opens an authorization dialog.
public enum Keychain {
    public static let service = AppIdentity.bundleID
    public static let didChange = Notification.Name("airdraft.credentialsChanged")
    public enum Presence: Sendable { case saved, missing, unavailable }

    public enum AccessError: Error, LocalizedError, Equatable, Sendable {
        case authorizationRequired
        case failure(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .authorizationRequired:
                return "Your saved API key needs access approval. Open Models and choose Allow access for this provider."
            case .failure(let status):
                return "Could not access Keychain (\(status)). Your saved key has not been removed."
            }
        }
    }

    private static let store = CredentialStore()

    /// Compatibility convenience for callers that only need an optional value.
    public static func get(_ account: String) -> String? { try? read(account) }

    /// Only a deliberate Allow access action may pass true. No migration writes
    /// happen during passive reads. Legacy keys stay usable until explicit import.
    public static func read(_ account: String, allowInteraction: Bool = false) throws -> String? {
        let value = try store.read(account, allowInteraction: allowInteraction)
        if allowInteraction { changed(account) }
        return value
    }

    /// Metadata only, never decrypts a password or attempts migration.
    public static func presence(_ account: String) -> Presence { store.presence(account) }

    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        let ok = value.isEmpty ? store.delete(account) : store.set(value, for: account)
        if ok { changed(account) }
        return ok
    }

    @discardableResult
    public static func delete(_ account: String) -> Bool {
        let ok = store.delete(account)
        if ok { changed(account) }
        return ok
    }

    private static func changed(_ account: String) {
        NotificationCenter.default.post(name: didChange, object: account)
    }
}

/// Test seam around Security.framework; contains the migration and failure rules.
struct CredentialStore {
    var copy: ([String: Any]) -> (OSStatus, Any?) = { query in
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item)
    }
    var add: ([String: Any]) -> OSStatus = { SecItemAdd($0 as CFDictionary, nil) }
    var update: ([String: Any], [String: Any]) -> OSStatus = { SecItemUpdate($0 as CFDictionary, $1 as CFDictionary) }
    var remove: ([String: Any]) -> OSStatus = { SecItemDelete($0 as CFDictionary) }

    // The file-based keychain ignores the SecItem/LAContext no-UI controls.
    // Scope its process-wide switch and serialize every operation using it.
    // See docs/keychain-access.md, including Chromium's FB16959400 workaround.
    private static let lock = NSRecursiveLock()

    static func withInteraction<T>(_ allowed: Bool, operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        var previous: DarwinBoolean = false
        try check(SecKeychainGetUserInteractionAllowed(&previous))
        try check(SecKeychainSetUserInteractionAllowed(allowed))
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }

    func presence(_ account: String) -> Keychain.Presence {
        guard !account.isEmpty else { return .missing }
        do {
            return try Self.withInteraction(false) {
                for service in [Keychain.service, AppIdentity.legacyBundleID] {
                    var query = match(account, service: service)
                    query[kSecReturnAttributes as String] = true
                    query[kSecMatchLimit as String] = kSecMatchLimitOne
                    let (status, _) = copy(query)
                    if status == errSecSuccess { return .saved }
                    if status != errSecItemNotFound { return .unavailable }
                }
                return .missing
            }
        } catch { return .unavailable }
    }

    func read(_ account: String, allowInteraction: Bool = false) throws -> String? {
        guard !account.isEmpty else { return nil }
        return try Self.withInteraction(allowInteraction) {
            if let current = try read(account, service: Keychain.service) { return current }
            // Only errSecItemNotFound reaches here. Denied/locked/current errors
            // must never fall through to a stale credential or overwrite it.
            guard let legacy = try read(account, service: AppIdentity.legacyBundleID) else { return nil }
            if allowInteraction {
                var attrs = match(account, service: Keychain.service)
                attrs[kSecValueData as String] = Data(legacy.utf8)
                let status = add(attrs)
                if status == errSecDuplicateItem {
                    return try read(account, service: Keychain.service)
                }
                try Self.check(status)
            }
            return legacy
        }
    }

    private func read(_ account: String, service: String) throws -> String? {
        var query = match(account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, item) = copy(query)
        if status == errSecItemNotFound { return nil }
        try Self.check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw Keychain.AccessError.failure(errSecDecode)
        }
        return value
    }

    func set(_ value: String, for account: String) -> Bool {
        guard !account.isEmpty else { return false }
        return (try? Self.withInteraction(true) {
            let query = match(account, service: Keychain.service)
            let values = [kSecValueData as String: Data(value.utf8)]
            let status = update(query, values)
            if status == errSecSuccess { return true }
            guard status == errSecItemNotFound else { return false }
            return add(query.merging(values) { _, new in new }) == errSecSuccess
        }) ?? false
    }

    func delete(_ account: String) -> Bool {
        guard !account.isEmpty else { return false }
        return (try? Self.withInteraction(true) {
            // Remove legacy first. If approval is denied, keep the current key;
            // otherwise a later read could resurrect the old legacy credential.
            for service in [AppIdentity.legacyBundleID, Keychain.service] {
                let status = remove(match(account, service: service))
                guard status == errSecSuccess || status == errSecItemNotFound else { return false }
            }
            return true
        }) ?? false
    }

    private func match(_ account: String, service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw Keychain.AccessError.authorizationRequired
        default: throw Keychain.AccessError.failure(status)
        }
    }
}
