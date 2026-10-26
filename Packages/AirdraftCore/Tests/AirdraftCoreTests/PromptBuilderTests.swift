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

    /// Section order, a TASK-led Summary profile, edited profile/base rules and selected-text edit mode.
    func testSystemPromptAssemblesSectionsProfilesEditedRulesAndEditMode() {
        let prompt = PromptBuilder.systemPrompt(for: request(profile: profile(RefinementProfile.conciseID)))
        let fidelity = prompt.range(of: "FIDELITY")!.lowerBound
        let dictionary = prompt.range(of: "DICTIONARY")!.lowerBound
        let mode = prompt.range(of: "PROFILE Concise")!.lowerBound
        let destination = prompt.range(of: "Destination:")!.lowerBound
        XCTAssertLessThan(fidelity, dictionary)
        XCTAssertLessThan(dictionary, mode)
        XCTAssertLessThan(mode, destination)
        XCTAssertTrue(prompt.contains("flows -> Floze"))

        // Summary leads with its TASK; Clean does not.
        let summary = PromptBuilder.systemPrompt(for: request(profile: profile(RefinementProfile.summaryID)))
        XCTAssertTrue(summary.hasPrefix("TASK: Summarize"))
        XCTAssertTrue(summary.contains("PROFILE Summary"))
        XCTAssertFalse(PromptBuilder.systemPrompt(for: request()).hasPrefix("TASK:"))

        // Edited profile instructions and base rules reach the prompt.
        var p = profile(RefinementProfile.conciseID)
        p.instructions = "Cut everything to one sentence."
        var req = request(profile: p)
        req.baseRules = "BASE RULES OVERRIDE"
        let edited = PromptBuilder.systemPrompt(for: req)
        XCTAssertTrue(edited.hasPrefix("BASE RULES OVERRIDE"))
        XCTAssertTrue(edited.contains("PROFILE Concise"))
        XCTAssertTrue(edited.contains("Cut everything to one sentence."))
        XCTAssertFalse(edited.contains("You are a dictation post-processor"))

        // Selected text switches to edit mode.
        let ctx = AppContext(bundleId: "com.apple.Notes", selectedText: "hello world")
        XCTAssertTrue(PromptBuilder.systemPrompt(for: request(context: ctx)).contains("SELECTED TEXT MODE"))
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

    /// Sanitizing strips thinking, fences and quotes; word counts mix CJK and Latin.
    func testSanitizeStripsThinkingAndFencesAndWordCountMixesCJKAndLatin() {
        XCTAssertEqual(PromptBuilder.sanitize("<think>reasoning</think>\n```\nHello\n```"), "Hello")
        XCTAssertEqual(PromptBuilder.sanitize("\"quoted\""), "quoted")
        XCTAssertEqual(DictationPipeline.approximateWordCount("hello world"), 2)
        XCTAssertEqual(DictationPipeline.approximateWordCount("今天很好"), 4)
        XCTAssertEqual(DictationPipeline.approximateWordCount("用 Floze 寫"), 3)
    }
}
