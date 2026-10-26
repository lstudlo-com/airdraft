import XCTest
@testable import AirdraftCore

final class SettingsSearchIndexTests: XCTestCase {
    private let documents: [SettingsSearchDocument] = [
        .init(section: "Permissions", title: "Accessibility", detail: "Cursor insertion, app context, modifier shortcuts and Trigger Delay"),
        .init(section: "Keyboard shortcuts", title: "Trigger Delay", detail: "Short presses keep their normal action; 0 = off"),
        .init(section: "Audio history", title: "Keep recordings", detail: "Local playback and retry. Off deletes audio, keeps text."),
        .init(section: "Updates", title: "Check automatically", detail: "Once a day"),
        .init(section: "Updates", title: "Download updates automatically", detail: "Installs when you quit")
    ]

    /// Section, title and full-description matching; exact names first; every term must
    /// match; whitespace is ignored.
    func testMatchesAllTermsAcrossSectionTitleAndDescriptionWithExactNamesFirst() {
        let index = SettingsSearchIndex(documents)
        XCTAssertEqual(index.matches("updates").map(\.title), ["Check automatically", "Download updates automatically"])
        XCTAssertEqual(index.matches("recordings").map(\.title), ["Keep recordings"])
        XCTAssertEqual(index.matches("when you quit").map(\.title), ["Download updates automatically"])
        XCTAssertEqual(index.matches("audio retry").map(\.title), ["Keep recordings"])

        XCTAssertEqual(index.matches("trigger delay").map(\.title), ["Trigger Delay", "Accessibility"])

        XCTAssertEqual(index.matches("  KEYBOARD\n delay  ").map(\.title), ["Trigger Delay"])
        XCTAssertTrue(index.matches("keyboard impossible").isEmpty)
        XCTAssertTrue(index.matches(" \n\t").isEmpty)
        XCTAssertTrue(index.matches("").isEmpty)
        XCTAssertTrue(index.matches(String(repeating: "no match ", count: 500)).isEmpty)
    }

    /// Unicode folding, literal punctuation and localized Chinese copy without spaces.
    func testUnicodeLiteralPunctuationAndLocalizedChineseCopy() {
        let index = SettingsSearchIndex([
            .init(section: "輸入", title: "Café 麥克風", detail: "ＡＢＣ 0 = off 🎙️ [input]")
        ])
        for query in ["cafe", "CAFÉ", "cafe\u{301}", "麥克", "abc", "🎙️", "[input]", "0 = off"] {
            XCTAssertEqual(index.matches(query).count, 1, query)
        }
        XCTAssertTrue(index.matches(".*").isEmpty, "Search must not interpret regex syntax")

        let chinese = SettingsSearchIndex([
            .init(section: "鍵盤快速鍵", title: "觸發延遲", detail: "短按保持原本的動作；0 = 關閉"),
            .init(section: "音訊記錄", title: "保留錄音", detail: "供本機播放與重試。關閉會刪除音訊，保留文字。"),
        ])
        XCTAssertEqual(chinese.matches("延遲").map(\.title), ["觸發延遲"])
        XCTAssertEqual(chinese.matches("錄音 重試").map(\.title), ["保留錄音"])
        XCTAssertEqual(chinese.matches("保留錄音").map(\.title), ["保留錄音"])
    }

    /// Same titles keep identity and reading order; rebuilding drops removed rows and old descriptions.
    func testIdentityReadingOrderAndRebuilding() {
        let rows: [SettingsSearchDocument] = [
            .init(section: "Input", title: "Language"), .init(section: "Preview", title: "Language")
        ]
        XCTAssertEqual(SettingsSearchIndex(rows + rows).matches("language"), rows)

        let before = SettingsSearchIndex([.init(section: "Permissions", title: "Microphone", detail: "Denied")])
        let after = SettingsSearchIndex([.init(section: "Permissions", title: "Microphone", detail: "Granted")])
        XCTAssertEqual(before.matches("denied").count, 1)
        XCTAssertTrue(after.matches("denied").isEmpty)
        XCTAssertEqual(after.matches("granted").count, 1)
        XCTAssertTrue(SettingsSearchIndex([]).matches("microphone").isEmpty)
    }
}
