import Foundation

public enum AppIdentity {
    public static let bundleID = "com.lstudlo.app.airdraft"
    public static let legacyBundleID = "com.lightiichen.transcribar"
    private static let migrationKey = "airdraft.legacyDefaultsImported"

    /// Copy once, preserving any values already saved under the new identity.
    public static func importLegacyDefaults(into defaults: UserDefaults, legacy: [String: Any]) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
    }
}
