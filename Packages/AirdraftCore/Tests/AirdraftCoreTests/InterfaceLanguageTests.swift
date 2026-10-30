import XCTest
@testable import AirdraftCore

/// AD-137: the per-app interface language and the Mac's languages stay separate.
final class InterfaceLanguageTests: XCTestCase {
    /// A stored per-app list maps to a shipped language by its first entry; anything else follows the Mac.
    func testStoredPerAppLanguagesMapToShippedChoices() {
        let cases: [([String]?, String?)] = [
            (nil, nil), ([], nil), (["ja"], "ja"), (["ja-JP"], "ja"), (["zh-Hant-TW", "en"], "zh-Hant"),
            (["zh-Hans"], "zh-Hans"), (["zh-HK"], "zh-Hant"), (["es-419"], "es"), (["en-GB"], "en"), (["fr"], nil),
        ]
        for (stored, expected) in cases {
            XCTAssertEqual(InterfaceLanguage.choice(forStored: stored)?.code, expected, "\(String(describing: stored))")
        }
        XCTAssertEqual(InterfaceLanguage.resolved(["en-TW", "zh-Hant-TW"]), "en")
        XCTAssertEqual(InterfaceLanguage.resolved(["fr-FR", "ja-JP"]), "ja")
        XCTAssertEqual(InterfaceLanguage.shipped.first?.code, "en")
    }

    /// Speech follows the Mac's languages when only Airdraft's interface language was
    /// chosen; a launch argument or a missing global list keeps `Locale.preferredLanguages`.
    func testSpeechLanguagesIgnoreAPerAppInterfaceLanguage() {
        let mac = ["zh-Hant-TW", "en-TW"]
        XCTAssertEqual(SystemLanguages.preferred(locale: ["en"], launchArgument: false, appOverride: ["en"], global: mac), mac)
        XCTAssertEqual(SystemLanguages.preferred(locale: mac, launchArgument: false, appOverride: nil, global: mac), mac)
        XCTAssertEqual(SystemLanguages.preferred(locale: ["ja"], launchArgument: true, appOverride: ["en"], global: mac), ["ja"])
        XCTAssertEqual(SystemLanguages.preferred(locale: ["en"], launchArgument: false, appOverride: ["en"], global: nil), ["en"])
        XCTAssertEqual(SystemLanguages.preferred(locale: ["en"], launchArgument: false, appOverride: ["en"], global: []), ["en"])
    }
}
