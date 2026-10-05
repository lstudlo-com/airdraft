import Foundation
import Security

public enum AppResetAdapters {
    /// Only these app-owned domains are reset. Mark legacy import complete so
    /// an old preference domain cannot resurrect a deleted configuration.
    public static let preferenceDomains = [AppIdentity.bundleID, AppIdentity.bundleID + ".debug", AppIdentity.legacyBundleID]

    public static func resetPreferences(in defaults: UserDefaults, domains: [String]) {
        for domain in domains {
            defaults.removePersistentDomain(forName: domain)
            defaults.setPersistentDomain(["airdraft.legacyDefaultsImported": true], forName: domain)
        }
    }

    /// Metadata-only enumeration, never a password read. License/trial receipts
    /// have their own account prefix and are preserved across every service.
    public static func removeProviderCredentials() throws {
        try ProviderCredentialRemoval().run()
    }

    public static func removeAppCaches() throws {
        let manager = FileManager.default
        guard let cacheRoot = manager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        for domain in preferenceDomains {
            let url = cacheRoot.appendingPathComponent(domain, isDirectory: true)
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        }
        URLCache.shared.removeAllCachedResponses()
    }

    public static func resetPermissions(bundleID: String) async throws {
        guard preferenceDomains.contains(bundleID) else { throw CleanupError.unsafeRoot }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "All", bundleID]
        let output = try await CLIProcess.run(process, input: "", timeout: 10)
        guard output.status == 0 else {
            throw PermissionResetError(message: "macOS could not reset this app’s permissions. " + output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

public struct PermissionResetError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Narrow Security seam: tests inject metadata and deletion results, with no
/// access to any real service. Current and legacy keys are removed together.
struct ProviderCredentialRemoval {
    var services = [AppIdentity.legacyBundleID, Keychain.service, AppIdentity.bundleID + ".provider-keys"]
    var list: ([String: Any]) -> (OSStatus, Any?) = { query in
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
    var remove: ([String: Any]) -> OSStatus = { SecItemDelete($0 as CFDictionary) }
    func run() throws {
        try CredentialStore.withInteraction(false) {
            for service in services {
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                           kSecAttrService as String: service,
                                           kSecMatchLimit as String: kSecMatchLimitAll,
                                           kSecReturnAttributes as String: true]
                let (status, result) = list(query)
                if status == errSecItemNotFound { continue }
                guard status == errSecSuccess else { throw PermissionResetError(message: "Some provider keys could not be removed (Keychain status \(status)). Completed removals stay removed; unlock Keychain and retry.") }
                let rows = result as? [[String: Any]] ?? (result as? [String: Any]).map { [$0] } ?? []
                for row in rows {
                    guard let account = row[kSecAttrAccount as String] as? String,
                          !account.hasPrefix("license.") else { continue }
                    let status = remove([kSecClass as String: kSecClassGenericPassword,
                                         kSecAttrService as String: service, kSecAttrAccount as String: account])
                    guard status == errSecSuccess || status == errSecItemNotFound else { throw PermissionResetError(message: "Some provider keys could not be removed (Keychain status \(status)). Completed removals stay removed; unlock Keychain and retry.") }
                }
            }
        }
    }
}
