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

    func testSearchesSectionTitleAndEntireDescription() {
        let index = SettingsSearchIndex(documents)
        XCTAssertEqual(index.matches("updates").map(\.title), ["Check automatically", "Download updates automatically"])
        XCTAssertEqual(index.matches("recordings").map(\.title), ["Keep recordings"])
        XCTAssertEqual(index.matches("when you quit").map(\.title), ["Download updates automatically"])
        XCTAssertEqual(index.matches("audio retry").map(\.title), ["Keep recordings"])
    }

    func testExactNamePrecedesIncidentalDescriptionMatch() {
        XCTAssertEqual(SettingsSearchIndex(documents).matches("trigger delay").map(\.title), ["Trigger Delay", "Accessibility"])
    }

    func testAllTermsMustMatchAndWhitespaceIsIgnored() {
        let index = SettingsSearchIndex(documents)
        XCTAssertEqual(index.matches("  KEYBOARD\n delay  ").map(\.title), ["Trigger Delay"])
        XCTAssertTrue(index.matches("keyboard impossible").isEmpty)
        XCTAssertTrue(index.matches(" \n\t").isEmpty)
        XCTAssertTrue(index.matches("").isEmpty)
        XCTAssertTrue(index.matches(String(repeating: "no match ", count: 500)).isEmpty)
    }

    func testUnicodeAndLiteralPunctuation() {
        let index = SettingsSearchIndex([
            .init(section: "輸入", title: "Café 麥克風", detail: "ＡＢＣ 0 = off 🎙️ [input]")
        ])
        for query in ["cafe", "CAFÉ", "cafe\u{301}", "麥克", "abc", "🎙️", "[input]", "0 = off"] {
            XCTAssertEqual(index.matches(query).count, 1, query)
        }
        XCTAssertTrue(index.matches(".*").isEmpty, "Search must not interpret regex syntax")
    }

    func testSameTitleInDifferentSectionsRetainsIdentityAndReadingOrder() {
        let rows: [SettingsSearchDocument] = [
            .init(section: "Input", title: "Language"), .init(section: "Preview", title: "Language")
        ]
        XCTAssertEqual(SettingsSearchIndex(rows + rows).matches("language"), rows)
    }

    func testRebuildingDropsRemovedRowsAndOutdatedDescriptions() {
        let before = SettingsSearchIndex([.init(section: "Permissions", title: "Microphone", detail: "Denied")])
        let after = SettingsSearchIndex([.init(section: "Permissions", title: "Microphone", detail: "Granted")])
        XCTAssertEqual(before.matches("denied").count, 1)
        XCTAssertTrue(after.matches("denied").isEmpty)
        XCTAssertEqual(after.matches("granted").count, 1)
        XCTAssertTrue(SettingsSearchIndex([]).matches("microphone").isEmpty)
    }
}
