import AppKit
import SwiftUI
import XCTest

/// Right-to-left layout contracts: the page mirrors, while key order, the light and
/// the window button inset keep their physical meaning.
@MainActor
final class RightToLeftLayoutTests: XCTestCase {
    func testWindowControlsKeepTheirLeadingInsetInBothDirections() {
        let ltr = WindowChromeView.BackingView.windowControlOrigins(containerWidth: 784, buttonWidth: 14, spacing: 20,
                                                                    rightToLeft: false)
        XCTAssertEqual(ltr.close, Theme.windowControlsInset)
        XCTAssertEqual(ltr.minimize, Theme.windowControlsInset + 20)

        // AppKit mirrors the titlebar: Close is outermost at the right, Minimize to its left.
        let rtl = WindowChromeView.BackingView.windowControlOrigins(containerWidth: 784, buttonWidth: 14, spacing: 20,
                                                                    rightToLeft: true)
        XCTAssertEqual(784 - (rtl.close + 14), Theme.windowControlsInset)
        XCTAssertEqual(rtl.minimize, rtl.close - 20)
    }

    /// Writing direction follows the first letter; isolates wrap text without changing it.
    func testWritingDirectionFollowsTheFirstLetterAndIsolatesKeepText() {
        XCTAssertEqual(WritingDirection.of("Send the report"), .leftToRight)
        XCTAssertEqual(WritingDirection.of("أرسل التقرير غدًا"), .rightToLeft)
        XCTAssertEqual(WritingDirection.of("שלום"), .rightToLeft)
        // Digits, punctuation and symbols are neutral; the first letter decides.
        XCTAssertEqual(WritingDirection.of("12:30 — أرسل Report"), .rightToLeft)
        XCTAssertEqual(WritingDirection.of("“Airdraft” يعمل"), .leftToRight)
        XCTAssertEqual(WritingDirection.of("寄出報告"), .leftToRight)
        XCTAssertNil(WritingDirection.of(""))
        XCTAssertNil(WritingDirection.of("42 · 7.5 → ⌥"))
        // Arabic-Indic digits do not make a number right to left.
        XCTAssertNil(WritingDirection.of("٤٢"))
        XCTAssertEqual(WritingDirection.paragraphDirection(of: "Report"), .leftToRight)
        XCTAssertEqual(WritingDirection.paragraphDirection(of: "تقرير"), .rightToLeft)
        XCTAssertEqual(WritingDirection.paragraphDirection(of: "2026"), .natural)

        let isolated = WritingDirection.isolated("LM Studio")
        XCTAssertEqual(isolated.unicodeScalars.first?.value, 0x2068)
        XCTAssertEqual(isolated.unicodeScalars.last?.value, 0x2069)
        XCTAssertEqual(String(isolated.dropFirst().dropLast()), "LM Studio")
    }
}
