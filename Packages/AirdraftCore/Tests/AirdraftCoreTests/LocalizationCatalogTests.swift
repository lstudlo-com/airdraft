import Foundation
import XCTest
@testable import AirdraftCore

/// Every interface string ships in each language of `Config/languages.json`. New or
/// changed English copy fails here until `scripts/localization.py sync` adds it and it
/// is translated into all of them.
final class LocalizationCatalogTests: XCTestCase {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    /// Shipped interface languages besides the English source (`Config/languages.json`).
    private static let languages: [String] = {
        let url = repository.appendingPathComponent("Config/languages.json")
        let config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        return ((config["languages"] as? [[String: Any]]) ?? []).compactMap { $0["code"] as? String }
    }()
    private static let catalogs = [
        "Sources/App/Localizable.xcstrings",
        "Sources/App/InfoPlist.xcstrings",
        "Sources/App/AppShortcuts.xcstrings",
        "Packages/AirdraftCore/Sources/AirdraftCore/Resources/Localizable.xcstrings",
    ]

    func testEveryCatalogKeyHasCurrentTranslations() throws {
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
                let source = (((localizations?["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String) ?? key
                for language in Self.languages {
                    let localization = localizations?[language] as? [String: Any]
                    let units = Self.units(localization)
                    guard !units.isEmpty, units.allSatisfy({ $0.state == "translated"
                        && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                        problems.append("\(path): missing \(language) \(key)")
                        continue
                    }
                    // A plural form may spell out its number ("one day"); `other` keeps every argument.
                    let expected = Self.placeholders(source)
                    for unit in units where unit.category == nil || unit.category == "other" {
                        if Self.placeholders(unit.value) != expected {
                            problems.append("\(path): \(language) placeholders differ for \(key) -> \(unit.value)")
                        }
                    }
                    for unit in units where unit.category != nil && unit.category != "other" {
                        if !Set(Self.placeholders(unit.value)).isSubset(of: expected) {
                            problems.append("\(path): \(language) plural form adds a placeholder for \(key) -> \(unit.value)")
                        }
                    }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }

    /// Siri and Shortcuts reject an App Shortcut phrase without the app name, in any language.
    func testAppShortcutPhrasesKeepTheApplicationName() throws {
        let url = Self.repository.appendingPathComponent("Sources/App/AppShortcuts.xcstrings")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        XCTAssertEqual(Set(strings.keys), ["Start dictation in ${applicationName}", "Stop dictation in ${applicationName}",
                                           "Cancel dictation in ${applicationName}"])
        for (key, entry) in strings {
            XCTAssertTrue(key.contains("${applicationName}"), key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]], key)
            XCTAssertTrue(Set(Self.languages).isSubset(of: localizations.keys), "\(key): \(localizations.keys.sorted())")
            for (language, localization) in localizations {
                let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
                XCTAssertEqual(value.components(separatedBy: "${applicationName}").count, 2, "\(language): \(value)")
            }
        }
    }

    func testShippedLanguagesMatchTheBundleLocalizations() throws {
        XCTAssertGreaterThanOrEqual(Self.languages.count, 10, "Config/languages.json lists \(Self.languages)")
        let project = try String(contentsOf: Self.repository.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try XCTUnwrap(project.split(separator: "\n").first { $0.contains("CFBundleLocalizations:") })
        let listed = line.split(separator: "[").last?.split(separator: "]").first?
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        XCTAssertEqual(Set(listed), Set(Self.languages + ["en"]))
        for language in Self.languages {
            XCTAssertTrue(Bundle.module.localizations.contains(language), "Core bundle lacks \(language): \(Bundle.module.localizations)")
        }
    }

    func testCoreBundleResolvesTraditionalChinese() throws {
        XCTAssertTrue(Bundle.module.localizations.contains("zh-Hant"), "\(Bundle.module.localizations)")
        let path = try XCTUnwrap(Bundle.module.path(forResource: "zh-Hant", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(chinese.localizedString(forKey: "Off", value: nil, table: nil), "關閉")
        XCTAssertEqual(chinese.localizedString(forKey: "Copied to clipboard", value: nil, table: nil), "已拷貝到剪貼簿")
        // Built-in profile names and a modifier key's side are shown in the interface language.
        XCTAssertEqual(chinese.localizedString(forKey: "Clean", value: nil, table: nil), "整理")
        XCTAssertEqual(chinese.localizedString(forKey: "Verbatim", value: nil, table: nil), "逐字")
        XCTAssertEqual(chinese.localizedString(forKey: "Right %@", value: nil, table: nil), "右 %@")
        // The test process runs in English: Core copy keeps its exact source wording.
        XCTAssertEqual(AppearanceMode.light.title, "Light")
    }

    func testCoreBundleResolvesSimplifiedChinese() throws {
        XCTAssertTrue(Bundle.module.localizations.contains("zh-Hans"), "\(Bundle.module.localizations)")
        let path = try XCTUnwrap(Bundle.module.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(chinese.localizedString(forKey: "Off", value: nil, table: nil), "关闭")
        XCTAssertEqual(chinese.localizedString(forKey: "Copied to clipboard", value: nil, table: nil), "已复制到剪贴板")
        // Built-in profile names and a modifier key's side are shown in the interface language.
        XCTAssertEqual(chinese.localizedString(forKey: "Clean", value: nil, table: nil), "整理")
        XCTAssertEqual(chinese.localizedString(forKey: "Verbatim", value: nil, table: nil), "逐字")
        XCTAssertEqual(chinese.localizedString(forKey: "Right %@", value: nil, table: nil), "右 %@")
        XCTAssertEqual(chinese.localizedString(forKey: "Microphone", value: nil, table: nil), "麦克风")
    }

    func testCoreBundleResolvesSpanishAndJapanese() throws {
        let expected: [String: [String: String]] = [
            "es": ["Off": "Desactivado", "Copied to clipboard": "Copiado al portapapeles", "Clean": "Limpio",
                   "Verbatim": "Literal", "Right %@": "%@ derecha", "Microphone": "Micrófono"],
            "ja": ["Off": "オフ", "Copied to clipboard": "クリップボードにコピーしました", "Clean": "クリーン",
                   "Verbatim": "逐語", "Right %@": "右 %@", "Microphone": "マイク"],
        ]
        for (language, values) in expected {
            XCTAssertTrue(Bundle.module.localizations.contains(language), "\(Bundle.module.localizations)")
            let path = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for (key, value) in values {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), value, "\(language): \(key)")
            }
        }
    }

    private struct Unit {
        let category: String?
        let state: String
        let value: String
    }

    /// The plain string unit, or every plural form of a language's localization.
    private static func units(_ localization: [String: Any]?) -> [Unit] {
        guard let localization else { return [] }
        if let unit = localization["stringUnit"] as? [String: Any] {
            return [Unit(category: nil, state: unit["state"] as? String ?? "", value: unit["value"] as? String ?? "")]
        }
        let plural = ((localization["variations"] as? [String: Any])?["plural"] as? [String: Any]) ?? [:]
        return plural.compactMap { category, form in
            guard let unit = (form as? [String: Any])?["stringUnit"] as? [String: Any] else { return nil }
            return Unit(category: category, state: unit["state"] as? String ?? "", value: unit["value"] as? String ?? "")
        }
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
