import Foundation

/// Settings > Appearance > Language (AD-137). macOS keeps an app's own language as
/// `AppleLanguages` in that app's preferences domain; System Settings > General >
/// Language & Region > Applications writes the same value. The bundle resolves it
/// only at launch, so a change applies after relaunching.
public struct InterfaceLanguage: Hashable, Identifiable, Sendable {
    /// A bundle localization.
    public let code: String
    /// The language's own name, the same in every interface language.
    public let name: String
    public var id: String { code }

    /// The English source, then `Config/languages.json` order and names;
    /// `LocalizationCatalogTests` keeps them aligned.
    public static let shipped = [
        InterfaceLanguage(code: "en", name: "English"),
        InterfaceLanguage(code: "es", name: "Español"),
        InterfaceLanguage(code: "ja", name: "日本語"),
        InterfaceLanguage(code: "zh-Hans", name: "简体中文"),
        InterfaceLanguage(code: "zh-Hant", name: "繁體中文"),
    ]

    public static let preferenceKey = "AppleLanguages"

    /// The shipped language a stored per-app list names first, or nil when the app
    /// follows the Mac (nothing stored, or a language Airdraft does not ship).
    public static func choice(forStored languages: [String]?) -> InterfaceLanguage? {
        guard let first = languages?.first,
              let code = Bundle.preferredLocalizations(from: shipped.map(\.code), forPreferences: [first]).first,
              Locale.Language(identifier: code).languageCode == Locale.Language(identifier: first).languageCode
        else { return nil }
        return shipped.first { $0.code == code }
    }

    /// The localization a launch with these preferred languages shows, as `Bundle` resolves it.
    public static func resolved(_ preferred: [String], localizations: [String] = shipped.map(\.code)) -> String {
        Bundle.preferredLocalizations(from: localizations, forPreferences: preferred).first ?? "en"
    }
}

/// The languages the user set for the whole Mac. They choose speech defaults,
/// recommendations and expectations. An interface language chosen for Airdraft
/// alone narrows `Locale.preferredLanguages` to that one language; speech keeps
/// following the Mac. A `-AppleLanguages` launch argument, as renders use, still
/// stands in for the Mac's languages.
public enum SystemLanguages {
    public static var preferred: [String] {
        let key = InterfaceLanguage.preferenceKey as CFString
        let app = CFPreferencesCopyValue(key, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let global = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return preferred(locale: Locale.preferredLanguages,
                         launchArgument: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[InterfaceLanguage.preferenceKey] != nil,
                         appOverride: app as? [String], global: global as? [String])
    }

    static func preferred(locale: [String], launchArgument: Bool, appOverride: [String]?, global: [String]?) -> [String] {
        guard !launchArgument, appOverride != nil, let global, !global.isEmpty else { return locale }
        return global
    }
}
