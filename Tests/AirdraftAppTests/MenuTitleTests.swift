import XCTest

/// Native menu items never wrap, so every dynamic title must fit the measured
/// 190-point limit that keeps the menu-bar menu about 270 points wide.
@MainActor
final class MenuTitleTests: XCTestCase {
    func testLimitKeepsTheMenuNarrow() {
        XCTAssertEqual(MenuTitle.maxWidth, 190)
    }

    func testShortTitlesAreUnchanged() {
        XCTAssertEqual(MenuTitle.fit("Start Dictation"), "Start Dictation")
        XCTAssertEqual(MenuTitle.fit(""), "")
    }

    func testLineBreaksBecomeSpaces() {
        XCTAssertEqual(MenuTitle.fit("Speech\nready"), "Speech ready")
        XCTAssertEqual(MenuTitle.fit("One\r\nTwo"), "One Two")
    }

    func testLongDiagnosticKeepsItsFirstSentence() {
        let text = "Microphone unavailable. The selected input disappeared while the recorder was starting, so check the device."
        XCTAssertEqual(MenuTitle.fit(text), "Microphone unavailable.")
    }

    func testChineseKeepsItsFirstSentenceAtTheFullWidthStop() {
        let text = "麥克風無法使用。所選的輸入裝置在錄音開始時中斷連線，請檢查裝置與系統設定後再試一次。"
        XCTAssertEqual(MenuTitle.fit(text), "麥克風無法使用。")
    }

    func testOtherScriptsKeepTheirFirstSentence() {
        let spanish = "Micrófono no disponible. La entrada seleccionada se desconectó al empezar a grabar; revisa el dispositivo."
        XCTAssertEqual(MenuTitle.fit(spanish), "Micrófono no disponible.")
        let japanese = "マイクを使用できません。選択した入力装置が録音開始時に切断されました。装置とシステム設定を確認してください。"
        XCTAssertEqual(MenuTitle.fit(japanese), "マイクを使用できません。")
        // The Devanagari danda ends a sentence like a full stop.
        let hindi = "माइक्रोफ़ोन उपलब्ध नहीं है। चुना गया इनपुट डिवाइस रिकॉर्डिंग शुरू होते समय डिस्कनेक्ट हो गया, कृपया डिवाइस जाँचें।"
        XCTAssertEqual(MenuTitle.fit(hindi), "माइक्रोफ़ोन उपलब्ध नहीं है।")
    }

    func testQuestionAndExclamationMarksOfOtherScriptsEndASentence() {
        let arabic = "هل الميكروفون متصل؟ انقطع جهاز الإدخال المحدد عند بدء التسجيل، لذا تحقق من الجهاز وإعدادات النظام."
        XCTAssertEqual(MenuTitle.fit(arabic), "هل الميكروفون متصل؟")
        let fullWidth = "マイクが見つかりません！選択した入力装置が録音開始時に切断されました。装置とシステム設定を確認してください。"
        XCTAssertEqual(MenuTitle.fit(fullWidth), "マイクが見つかりません！")
        let question = "麥克風是否已連接？選取的輸入裝置在開始錄音時中斷了連線，請檢查裝置與系統設定，然後再試一次。"
        XCTAssertEqual(MenuTitle.fit(question), "麥克風是否已連接？")
    }

    func testLongTextIsTruncatedAtAWordWithAnEllipsis() {
        let text = String(repeating: "transcription ", count: 20).trimmingCharacters(in: .whitespaces)
        let fitted = MenuTitle.fit(text)
        XCTAssertTrue(MenuTitle.fits(fitted), fitted)
        XCTAssertTrue(fitted.hasSuffix("…"))
        XCTAssertTrue(fitted.hasPrefix("transcription"))
        // Broken at a word boundary, not inside one.
        XCTAssertTrue(fitted.dropLast().split(separator: " ").allSatisfy { $0 == "transcription" }, fitted)
    }

    func testTextWithoutSpacesIsCutAtTheLimit() {
        let text = String(repeating: "語音", count: 60)
        let fitted = MenuTitle.fit(text)
        XCTAssertTrue(MenuTitle.fits(fitted), fitted)
        XCTAssertTrue(fitted.hasSuffix("…"))
        XCTAssertFalse(MenuTitle.fits(String(fitted.dropLast()) + "語…"), "the cut should use the available width")
    }

    func testProfileWithoutAutomaticAppNamesOnlyTheProfile() {
        XCTAssertEqual(MenuTitle.profile("Clean", app: nil), "Profile: Clean")
    }

    func testAutomaticProfileNamesItsApp() {
        XCTAssertEqual(MenuTitle.profile("Clean", app: "Notes"), "Profile: Clean (auto: Notes)")
    }

    func testAutomaticProfileShortensTheAppBeforeTheProfile() {
        let app = "An Extremely Long Application Name For Testing"
        let title = MenuTitle.profile("Clean", app: app)
        XCTAssertTrue(MenuTitle.fits(title), title)
        XCTAssertTrue(title.hasPrefix("Profile: Clean (auto: An"), title)
        XCTAssertTrue(title.hasSuffix("…)"), title)
    }

    func testEveryProfileTitleFits() {
        let long = String(repeating: "Meeting Notes Profile ", count: 6)
        for app in [nil, "Mail", String(repeating: "Very Long App ", count: 8)] {
            let title = MenuTitle.profile(long, app: app)
            XCTAssertTrue(MenuTitle.fits(title), title)
        }
    }
}
