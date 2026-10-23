import XCTest
@testable import AirdraftCore

/// AD-082: SenseVoice/FireRedASR2 write English in capitals and never punctuate.
final class SpokenTextNormalizerTests: XCTestCase {
    private func cased(_ text: String, _ vocabulary: [String] = []) -> String {
        SpokenTextNormalizer.naturalCase(text, vocabulary: vocabulary)
    }

    func testCapitalizedEnglishBecomesNaturalCase() {
        XCTAssertEqual(cased("先跑一下 UNIT TEST再 DEPLOY"), "先跑一下 unit test再 deploy")
        XCTAssertEqual(cased("我等一下把 PR MERGE 到 MAIN BRANCH"), "我等一下把 PR merge 到 main branch")
        XCTAssertEqual(cased("這個 API 的 RESPONSE TIME 有點太慢"), "這個 API 的 response time 有點太慢")
        XCTAssertEqual(cased("我們下禮拜要 RELEASE 新版本的 IOS APP"), "我們下禮拜要 release 新版本的 iOS app")
        XCTAssertEqual(cased("我的 MACBOOK 記憶體不夠用了"), "我的 MacBook 記憶體不夠用了")
        XCTAssertEqual(cased("我們用 REACT 跟 TYPESCRIPT 重寫前端"), "我們用 React 跟 TypeScript 重寫前端")
        XCTAssertEqual(cased("幫我確認一下 SERVER 的 CPU 使用率"), "幫我確認一下 server 的 CPU 使用率")
    }

    func testEnglishSentencesStartWithACapital() {
        XCTAssertEqual(cased("CAN YOU REVIEW MY CODE BEFORE LUNCH"), "Can you review my code before lunch")
        XCTAssertEqual(cased("I'M NOT SURE IT WORKS ON MACOS"), "I'm not sure it works on macOS")
        XCTAssertEqual(cased("SO WE ASKED A FRIEND"), "So we asked a friend")
    }

    func testDictionaryTermsKeepTheirSpelling() {
        XCTAssertEqual(cased("記得在 NOTION 上面更新 MEETING NOTES", ["Meeting Notes"]), "記得在 Notion 上面更新 Meeting Notes")
        XCTAssertEqual(cased("把 SUPABASE 的 KEY 換掉", ["Supabase"]), "把 Supabase 的 key 換掉")
        XCTAssertEqual(cased("用 POSTHOG 看一下", ["PostHog", "posthog"]), "用 PostHog 看一下")
    }

    func testAcronymsSpelledLettersAndAmbiguousWords() {
        XCTAssertEqual(cased("那個 I G I N G 是不是"), "那個 I G I N G 是不是")
        XCTAssertEqual(cased("我們的 KPI 這一季"), "我們的 KPI 這一季")
        XCTAssertEqual(cased("請把這份 SLIDE 寄給 PM"), "請把這份 slide 寄給 PM")
        XCTAssertEqual(cased("用 SQL 跟 HTML 寫"), "用 SQL 跟 HTML 寫")
        XCTAssertEqual(cased("找 IT 部門"), "找 IT 部門")
        XCTAssertEqual(cased("I THINK IT IS FINE"), "I think it is fine")
        XCTAssertEqual(cased("A 方案比較好"), "A 方案比較好")
        XCTAssertEqual(cased("連上 WI-FI 再說"), "連上 Wi-Fi 再說")
        XCTAssertEqual(cased("HMM 我想一下"), "hmm 我想一下")
    }

    func testMixedCaseOutputIsLeftAlone() {
        for text in ["記得把 Docker Image Push 到 Registry。", "我等一下把 PR merge 到 main branch", "那個 OK 吧", "沒有英文"] {
            XCTAssertEqual(cased(text), text)
        }
    }

    func testTerminalPunctuationIsConservative() {
        XCTAssertEqual(SpokenTextNormalizer.addTerminalPunctuation("先跑一下 unit test再 deploy"), "先跑一下 unit test再 deploy。")
        XCTAssertEqual(SpokenTextNormalizer.addTerminalPunctuation("你可以先 review 一下我的 code 嗎"), "你可以先 review 一下我的 code 嗎？")
        XCTAssertEqual(SpokenTextNormalizer.addTerminalPunctuation("Can you review my code before lunch"), "Can you review my code before lunch?")
        XCTAssertEqual(SpokenTextNormalizer.addTerminalPunctuation("The deployment failed again"), "The deployment failed again.")
        // Already punctuated, too short to be a sentence, or ending in a symbol.
        for text in ["好的。", "OK", "好", "main branch", "Done!", "版本 2.0)", "我覺得，"] {
            XCTAssertEqual(SpokenTextNormalizer.addTerminalPunctuation(text), text)
        }
    }

    func testNormalizationReportsItsAdjustments() {
        let result = SpokenTextNormalizer.normalizeCapitalizedOutput("先跑一下 UNIT TEST再 DEPLOY")
        XCTAssertEqual(result.text, "先跑一下 unit test再 deploy。")
        XCTAssertEqual(result.adjustments, [.casingNormalized, .punctuationAdded])
        XCTAssertEqual(SpokenTextNormalizer.normalizeCapitalizedOutput("好的。").adjustments, [])
    }

    func testNormalizedTextStillReachesTheDictionaryAndScriptConverterUnchanged() {
        // The normalizer only changes Latin letter case and the final mark; the
        // script converter and dictionary still run afterwards in the pipeline.
        let normalized = SpokenTextNormalizer.normalizeCapitalizedOutput("这个 BUG 我已经 FIX 好了").text
        XCTAssertEqual(normalized, "这个 bug 我已经 fix 好了。")
        XCTAssertEqual(ChineseScriptConverter.convert(normalized, to: .traditional), "這個 bug 我已經 fix 好了。")
    }
}
