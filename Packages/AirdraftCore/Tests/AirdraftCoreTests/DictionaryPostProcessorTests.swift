import XCTest
@testable import AirdraftCore

final class DictionaryPostProcessorTests: XCTestCase {
    func testLatinAliasReplacedOnWordBoundary() {
        let entries = [DictionaryEntry(term: "Floze", aliases: ["flows", "flow's"])]
        XCTAssertEqual(DictionaryPostProcessor.apply("open flows now", entries: entries), "open Floze now")
        XCTAssertEqual(DictionaryPostProcessor.apply("workflows", entries: entries), "workflows")
    }

    func testTermCasingIsFixed() {
        let entries = [DictionaryEntry(term: "Floze")]
        XCTAssertEqual(DictionaryPostProcessor.apply("I use floze daily", entries: entries), "I use Floze daily")
    }

    func testCaseSensitiveEntryLeavesOtherCasing() {
        let entries = [DictionaryEntry(term: "iOS", aliases: ["IOS"], caseSensitive: true)]
        XCTAssertEqual(DictionaryPostProcessor.apply("IOS and ios", entries: entries), "iOS and ios")
    }

    func testCJKAliasLiteralReplacement() {
        let entries = [DictionaryEntry(term: "浮洛茲", aliases: ["浮落資", "福洛斯"])]
        XCTAssertEqual(DictionaryPostProcessor.apply("今天用浮落資寫故事", entries: entries), "今天用浮洛茲寫故事")
    }

    func testSingleCJKCharacterAliasIsIgnored() {
        let entries = [DictionaryEntry(term: "陳", aliases: ["成"])]
        XCTAssertEqual(DictionaryPostProcessor.apply("完成了", entries: entries), "完成了")
    }

    func testChineseScriptConversion() {
        XCTAssertEqual(ChineseScriptConverter.convert("我们今天要讨论三件事", to: .traditional), "我們今天要討論三件事")
        XCTAssertEqual(ChineseScriptConverter.convert("軟體測試", to: .simplified), "软体测试")
        XCTAssertEqual(ChineseScriptConverter.convert("hello world", to: .traditional), "hello world")
        XCTAssertEqual(ChineseScriptConverter.convert("我们", to: .auto), "我们")
    }

    func testWhisperPromptLeadsWithScriptHint() {
        let hints = TranscriptionHints(vocabulary: ["Floze"], chineseScript: .traditional)
        XCTAssertEqual(hints.promptText, "以下是繁體中文的內容。 Floze")
        XCTAssertNil(TranscriptionHints().promptText)
    }

    func testVocabularyAndCorrectionLines() {
        let entries = [DictionaryEntry(term: "Printage", aliases: ["print age"])]
        XCTAssertEqual(DictionaryPostProcessor.vocabulary(entries), ["Printage"])
        XCTAssertEqual(DictionaryPostProcessor.correctionLines(entries), ["print age -> Printage"])
    }
}
