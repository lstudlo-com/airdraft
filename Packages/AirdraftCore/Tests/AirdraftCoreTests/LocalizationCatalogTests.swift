import Foundation
import XCTest
@testable import AirdraftCore

/// Every interface string ships in Traditional Chinese (Taiwan). New or changed English
/// copy fails here until `scripts/localization.py sync` adds it and it is translated.
final class LocalizationCatalogTests: XCTestCase {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let catalogs = [
        "Sources/App/Localizable.xcstrings",
        "Sources/App/InfoPlist.xcstrings",
        "Packages/AirdraftCore/Sources/AirdraftCore/Resources/Localizable.xcstrings",
    ]

    func testEveryCatalogKeyHasCurrentTraditionalChineseTranslation() throws {
        var problems: [String] = []
        for path in Self.catalogs {
            let url = Self.repository.appendingPathComponent(path)
            let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], path)
            XCTAssertEqual(catalog["sourceLanguage"] as? String, "en", path)
            let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]], path)
            XCTAssertFalse(strings.isEmpty, path)
            for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false
                && !key.trimmingCharacters(in: .whitespaces).isEmpty {
                if entry["extractionState"] as? String == "stale" {
                    problems.append("\(path): stale \(key)")
                    continue
                }
                let localizations = entry["localizations"] as? [String: Any]
                let unit = (localizations?["zh-Hant"] as? [String: Any])?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String, unit?["state"] as? String == "translated",
                      !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                    problems.append("\(path): missing zh-Hant \(key)")
                    continue
                }
                let source = (((localizations?["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String) ?? key
                if Self.placeholders(value) != Self.placeholders(source) {
                    problems.append("\(path): placeholders differ for \(key) -> \(value)")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }

    func testCoreBundleResolvesTraditionalChinese() throws {
        XCTAssertTrue(Bundle.module.localizations.contains("zh-Hant"), "\(Bundle.module.localizations)")
        let path = try XCTUnwrap(Bundle.module.path(forResource: "zh-Hant", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(chinese.localizedString(forKey: "Off", value: nil, table: nil), "關閉")
        XCTAssertEqual(chinese.localizedString(forKey: "Copied to clipboard", value: nil, table: nil), "已拷貝到剪貼板")
        // The test process runs in English: Core copy keeps its exact source wording.
        XCTAssertEqual(HotkeyBehavior.hold.instructionVerb, "Hold")
    }

    /// Argument types in order, ignoring positional reordering such as %2$@ before %1$@.
    private static func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDuUxXoOfeEgGcCsSpaAF%])"#)
        var found: [Int: String] = [:]
        var position = 0
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let kind = String(text[Range(match.range(at: 2), in: text)!])
            guard kind != "%" else { continue }
            position += 1
            let index = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? position
            found[index] = "dioux".contains(kind.lowercased()) ? "d" : kind.lowercased()
        }
        return found.keys.sorted().map { found[$0]! }
    }
}
