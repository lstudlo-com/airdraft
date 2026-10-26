import XCTest
@testable import AirdraftCore

final class LiveTextOptionsTests: XCTestCase {
    func testDefaultsMatchTheOriginalCard() {
        let options = LiveTextOptions()
        XCTAssertEqual(options.style, .glass)
        XCTAssertEqual(options.lines, 2)
        XCTAssertEqual(options.textSize, .medium)
        XCTAssertEqual(options.textSize.points, 12.5)
    }

    func testLinesStayInRange() {
        XCTAssertEqual(LiveTextOptions(lines: 0).lines, 1)
        XCTAssertEqual(LiveTextOptions(lines: 9).lines, 4)
        var options = LiveTextOptions()
        options.lines = 7
        XCTAssertEqual(options.lines, 4)
    }

    /// A partial or partly unknown saved value keeps every field it can read.
    func testDecodingFallsBackPerField() throws {
        let decoded = try JSONDecoder().decode(LiveTextOptions.self,
            from: Data(#"{"style":"neon","lines":12,"textSize":"large"}"#.utf8))
        XCTAssertEqual(decoded, LiveTextOptions(style: .glass, lines: 4, textSize: .large))
        XCTAssertEqual(try JSONDecoder().decode(LiveTextOptions.self, from: Data("{}".utf8)), LiveTextOptions())
    }

    @MainActor
    func testSettingPersists() {
        let suite = "airdraft.live-text-options.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.liveText, LiveTextOptions())
        settings.liveText = LiveTextOptions(style: .subtitle, lines: 3, textSize: .small)
        XCTAssertEqual(AppSettings(defaults: defaults).liveText, LiveTextOptions(style: .subtitle, lines: 3, textSize: .small))
    }

    func testLiveTextModelsIncludeAppleSpeechAndExcludeAutoregressive() {
        XCTAssertTrue(ModelSpeechPreview.showsLiveText(ASRConfig(kind: .senseVoiceMultilingual)))
        XCTAssertTrue(ModelSpeechPreview.showsLiveText(ASRConfig(kind: .apple, appleLocale: "en-US", language: "")))
        XCTAssertFalse(ModelSpeechPreview.showsLiveText(ASRConfig(kind: .qwen3)))
        XCTAssertFalse(ModelSpeechPreview.showsLiveText(ASRConfig(kind: .whisperKit)))
    }
}
