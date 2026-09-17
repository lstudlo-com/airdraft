import XCTest
@testable import AirdraftCore

final class PromptBuilderTests: XCTestCase {
    private func profile(_ id: UUID) -> RefinementProfile {
        RefinementProfile.defaultProfile(id: id)!
    }

    private func request(profile: RefinementProfile = RefinementProfile.defaultProfile(id: RefinementProfile.cleanID)!, context: AppContext = .empty) -> RefineRequest {
        RefineRequest(
            transcript: "嗯 我們今天 要討論 三件事",
            profile: profile,
            context: context,
            family: AppFamily.classify(context),
            dictionary: [DictionaryEntry(term: "Floze", aliases: ["flows"])]
        )
    }

    func testSystemPromptContainsSectionsInStableOrder() {
        let prompt = PromptBuilder.systemPrompt(for: request(profile: profile(RefinementProfile.conciseID)))
        let fidelity = prompt.range(of: "FIDELITY")!.lowerBound
        let dictionary = prompt.range(of: "DICTIONARY")!.lowerBound
        let mode = prompt.range(of: "PROFILE Concise")!.lowerBound
        let destination = prompt.range(of: "Destination:")!.lowerBound
        XCTAssertLessThan(fidelity, dictionary)
        XCTAssertLessThan(dictionary, mode)
        XCTAssertLessThan(mode, destination)
        XCTAssertTrue(prompt.contains("flows -> Floze"))
    }

    func testSummaryProfileLeadsWithTask() {
        let prompt = PromptBuilder.systemPrompt(for: request(profile: profile(RefinementProfile.summaryID)))
        XCTAssertTrue(prompt.hasPrefix("TASK: Summarize"))
        XCTAssertTrue(prompt.contains("PROFILE Summary"))
        XCTAssertFalse(PromptBuilder.systemPrompt(for: request()).hasPrefix("TASK:"))
    }

    func testEditedProfileAndBaseRulesReachThePrompt() {
        var p = profile(RefinementProfile.conciseID)
        p.instructions = "Cut everything to one sentence."
        var req = request(profile: p)
        req.baseRules = "BASE RULES OVERRIDE"
        let prompt = PromptBuilder.systemPrompt(for: req)
        XCTAssertTrue(prompt.hasPrefix("BASE RULES OVERRIDE"))
        XCTAssertTrue(prompt.contains("PROFILE Concise"))
        XCTAssertTrue(prompt.contains("Cut everything to one sentence."))
        XCTAssertFalse(prompt.contains("You are a dictation post-processor"))
    }

    func testSelectedTextSwitchesToEditMode() {
        let ctx = AppContext(bundleId: "com.apple.Notes", selectedText: "hello world")
        let prompt = PromptBuilder.systemPrompt(for: request(context: ctx))
        XCTAssertTrue(prompt.contains("SELECTED TEXT MODE"))
        let user = PromptBuilder.userMessage(for: request(context: ctx))
        XCTAssertTrue(user.contains("<selected_text>"))
        XCTAssertTrue(user.contains("<transcription>"))
    }

    func testAppFamilyClassification() {
        XCTAssertEqual(AppFamily.classify(AppContext(bundleId: "com.tinyspeck.slackmacgap")), .workChat)
        XCTAssertEqual(AppFamily.classify(AppContext(bundleId: "com.google.Chrome", url: "https://mail.google.com/mail/u/0/#inbox")), .email)
        XCTAssertEqual(AppFamily.classify(AppContext(bundleId: "com.jetbrains.intellij")), .code)
        XCTAssertEqual(AppFamily.classify(AppContext(bundleId: "com.unknown.app")), .general)
    }

    func testSanitizeStripsThinkingAndFences() {
        XCTAssertEqual(PromptBuilder.sanitize("<think>reasoning</think>\n```\nHello\n```"), "Hello")
        XCTAssertEqual(PromptBuilder.sanitize("\"quoted\""), "quoted")
    }

    func testWordCountMixesCJKAndLatin() {
        XCTAssertEqual(DictationPipeline.approximateWordCount("hello world"), 2)
        XCTAssertEqual(DictationPipeline.approximateWordCount("今天很好"), 4)
        XCTAssertEqual(DictationPipeline.approximateWordCount("用 Floze 寫"), 3)
    }
}
