import XCTest
@testable import AirdraftCore

final class AppleIntelligenceTests: XCTestCase {
    private let request = RefineRequest(transcript: "um meet tomorrow", profile: RefinementProfile.defaults[0],
                                        context: .empty, family: .general, dictionary: [])

    @MainActor
    func testFactoryNeverReadsCredentialsForAppleIntelligence() async throws {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("On-device cleanup must not read any credentials")
            throw CocoaError(.fileReadNoPermission)
        })
        var config = LLMConfig()
        config.select(.appleIntelligence)
        config.baseURL = "invalid endpoint"
        let engine = await factory.refiner(for: config)
        XCTAssertTrue(engine is AppleIntelligenceRefiner)
        XCTAssertFalse(config.kind.isCloud)
        XCTAssertFalse(config.kind.requiresKey)
        XCTAssertEqual(try JSONDecoder().decode(LLMConfig.self, from: JSONEncoder().encode(config)), config)
    }

    func testUsesExistingPromptAndRejectsEmptyOutput() async throws {
        let expectedSystem = PromptBuilder.systemPrompt(for: request)
        let expectedUser = PromptBuilder.userMessage(for: request)
        let engine = AppleIntelligenceRefiner(timeout: 2, availability: { nil }) { instructions, prompt in
            XCTAssertEqual(instructions, expectedSystem)
            XCTAssertEqual(prompt, expectedUser)
            return "  Meet tomorrow.  "
        }
        let result = try await engine.refine(request)
        XCTAssertEqual(result.text, "Meet tomorrow.")
        XCTAssertEqual(result.promptVersion, PromptBuilder.version)
        let empty = AppleIntelligenceRefiner(timeout: 2, availability: { nil }) { _, _ in " " }
        do { _ = try await empty.refine(request); XCTFail("Empty output must fall back") }
        catch RefinerError.emptyOutput {}
    }

    func testUnavailableDoesNotStartGeneration() async {
        let engine = AppleIntelligenceRefiner(timeout: 2, availability: { "Enable Apple Intelligence" }) { _, _ in
            XCTFail("Unavailable model must not be invoked"); return ""
        }
        do { _ = try await engine.refine(request); XCTFail("Must report availability") }
        catch { XCTAssertEqual(error.localizedDescription, "Enable Apple Intelligence") }
    }

    func testDeadlineRejectsLateGeneration() async {
        let engine = AppleIntelligenceRefiner(timeout: 0.01, availability: { nil }) { _, _ in
            try await Task.sleep(for: .seconds(5)); return "Late text"
        }
        do { _ = try await engine.refine(request); XCTFail("Must time out") }
        catch { XCTAssertTrue(error is RefinerError) }
    }
}
