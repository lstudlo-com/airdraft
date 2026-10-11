import XCTest
import TranscribeCppKit
@testable import AirdraftCore

final class GGUFModelTests: XCTestCase {
    func testCatalogArtifactsArePinnedAndCoverCompetitorFamilies() throws {
        let models = GGUFModelCatalog.models
        XCTAssertEqual(models.count, 69)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for model in models {
            XCTAssertNotNil(model.revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression), model.id)
            XCTAssertNotNil(model.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression), model.id)
            XCTAssertGreaterThan(model.bytes, 0)
            XCTAssertTrue(model.filename.hasSuffix(".gguf"))
            XCTAssertFalse(model.filename.contains("/"))
            XCTAssertFalse(model.id.contains("/"))
            XCTAssertTrue(model.downloadURL.path.contains(model.revision))
            XCTAssertFalse(model.supportedLanguages.isEmpty)
            XCTAssertEqual(model.downloadURL.host, "huggingface.co")
        }
        for id in ["whisper-tiny", "whisper-large-v3", "breeze-asr-25", "moonshine-base-zh",
                   "canary-1b-v2", "gigaam-v3-rnnt", "fun-asr-mlt-nano-2512",
                   "nemotron-3.5-asr-streaming-0.6b", "voxtral-mini-4b-realtime-2602",
                   "granite-speech-4.1-2b", "moss-transcribe-diarize"] {
            XCTAssertNotNil(GGUFModelCatalog.model(id), id)
        }
    }

    @MainActor
    func testEveryModelRetainsItsIdentityThroughFactoryProfilesAndMeetings() async throws {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in XCTFail("Local models need no key"); return nil })
        for model in GGUFModelCatalog.models {
            var config = model.config
            config.language = model.supportedLanguages[0]
            let engine = await factory.transcriber(for: config)
            XCTAssertEqual(engine.id, config.engineID)
            let binding = ProfileSpeechModel(config: config)
            let restored = try JSONDecoder().decode(ProfileSpeechModel.self, from: JSONEncoder().encode(binding))
            let applied = restored.applying(to: ASRConfig(kind: .groq, language: "zh", chineseScript: .simplified))
            XCTAssertEqual(applied.model, model.id)
            XCTAssertEqual(applied.language, "zh", "Bindings must preserve the shared language, even when incompatible")
            XCTAssertEqual(applied.chineseScript, .simplified)
            XCTAssertNil(binding.unavailableReason)

            var meeting = MediaConfiguration(language: model.supportedLanguages[0])
            meeting.selectModelChoice("gguf:\(model.id)")
            try meeting.validate()
            XCTAssertEqual(meeting.asr.engineID, config.engineID)
            XCTAssertTrue(meeting.usesSegmentTiming)
            XCTAssertEqual(meeting.selectedModelTitle, model.title)
            XCTAssertEqual(try JSONDecoder().decode(MediaConfiguration.self, from: JSONEncoder().encode(meeting)), meeting)
        }
        let choices = MediaConfiguration.modelChoices
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
    }

    func testExplicitLanguageRequirementsAndJointDecoders() throws {
        for id in ["canary-180m-flash", "canary-1b-v2", "cohere-transcribe-03-2026", "granite-speech-4.1-2b"] {
            let model = try XCTUnwrap(GGUFModelCatalog.model(id))
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(model.config), id)
            var config = model.config
            config.language = "en"
            XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "en")
        }
        let breeze = try XCTUnwrap(GGUFModelCatalog.model("breeze-asr-25"))
        var config = breeze.config
        config.language = "zh-TW"
        XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "zh")
        config.language = "yue"
        XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(config))
        config = try XCTUnwrap(GGUFModelCatalog.model("nemotron-3.5-asr-streaming-0.6b")).config
        config.language = "zh"
        XCTAssertNil(try SpeechLanguagePolicy.resolve(config).language, "Joint decoders must not receive a ignored forcing flag")
        config = try XCTUnwrap(GGUFModelCatalog.model("moonshine-tiny")).config
        config.language = "zh"
        XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(config))
    }

    func testUnknownSavedModelsNeverFallbackOrEscapeStorage() throws {
        var meeting = MediaConfiguration()
        meeting.selectModelChoice("gguf:../../elsewhere")
        XCTAssertThrowsError(try meeting.validate())
        XCTAssertNil(LocalModels.ggufFolder(for: "../../elsewhere"))
        XCTAssertNil(LocalModels.folder(for: ASRConfig(kind: .transcribeCpp, model: "retired")))
        XCTAssertFalse(LocalModels.isInstalled(meeting.asr))
        XCTAssertNotNil(ProfileSpeechModel(config: meeting.asr).unavailableReason)
    }

    func testNativeDistributionMatchesItsABI() {
        XCTAssertEqual(String(cString: transcribe_version()), "0.2.4")
        XCTAssertEqual(transcribe_abi_struct_size(TRANSCRIBE_ABI_RUN_PARAMS), MemoryLayout<transcribe_run_params>.size)
        var params = transcribe_run_params()
        transcribe_run_params_init(&params)
        XCTAssertEqual(params.struct_size, UInt64(MemoryLayout<transcribe_run_params>.size))
    }

    func testAdapterRejectsInvalidInputBeforeLoading() async {
        let engine = GGUFTranscriber(modelID: "canary-180m-flash")
        do { _ = try await engine.transcribe(samples: [0.2], hints: .init()); XCTFail("Auto must fail before native loading") }
        catch { XCTAssertTrue(error is SpeechLanguageError) }
        do { _ = try await engine.transcribe(samples: [], hints: .init(language: "en")); XCTFail("Empty input must fail") }
        catch { XCTAssertTrue(error is TranscriberError) }
        let task = Task {
            try await Task.sleep(for: .milliseconds(10))
            try Task.checkCancellation()
            return try await engine.transcribe(samples: [0.2], hints: .init(language: "en"))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled input must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
