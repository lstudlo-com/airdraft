import XCTest
@testable import AirdraftCore

final class CoreMLSpeechModelTests: XCTestCase {
    /// Every Core ML variant is pinned with a saved identity; Distil-Whisper, Orukeet and retired Core ML choices follow their directory, archive and language rules.
    @MainActor func testCoreMLDistilOrukeetAndRetiredChoicesKeepPinnedArtifactsAndLanguagePolicies() async throws {
        // EveryCoreMLVariantHasCompletePinnedArtifactsAndSavedIdentity
        do {
            let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in XCTFail("Local engines use no key"); return nil })
            XCTAssertEqual(CoreMLSpeechModelCatalog.models.count, 8)
            for entry in CoreMLSpeechModelCatalog.models {
                XCTAssertNotNil(entry.revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression))
                XCTAssertTrue(entry.files.contains { $0.path.contains("weight.bin") })
                XCTAssertTrue(entry.files.contains { $0.path.hasSuffix("vocab.json") })
                XCTAssertEqual(Set(entry.files.map(\.path)).count, entry.files.count)
                for file in entry.files {
                    XCTAssertGreaterThan(file.bytes, 0)
                    XCTAssertNotNil(file.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression))
                    XCTAssertFalse(file.path.hasPrefix("/"))
                    XCTAssertFalse(file.path.split(separator: "/").contains(".."))
                }
                let engine = await factory.transcriber(for: entry.config)
                XCTAssertEqual(engine.id, entry.config.engineID)
                var meeting = MediaConfiguration(language: entry.languages[0])
                meeting.selectModelChoice("coreml:\(entry.id)")
                try meeting.validate()
                XCTAssertEqual(meeting.asr.engineID, entry.config.engineID)
                XCTAssertTrue(meeting.usesSegmentTiming)
                XCTAssertEqual(try JSONDecoder().decode(MediaConfiguration.self, from: JSONEncoder().encode(meeting)), meeting)
                let binding = ProfileSpeechModel(config: entry.config)
                let applied = binding.applying(to: ASRConfig(kind: .groq, language: "zh", chineseScript: .traditional))
                XCTAssertEqual(applied.engineID, entry.config.engineID)
                XCTAssertEqual(applied.language, "zh")
                XCTAssertNil(binding.unavailableReason)
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(applied), "These European/Japanese models must reject Chinese")
            }
        }
        // DistilWhisperUsesItsExactDirectoryAndFixedEnglishPolicy
        do {
            let distilled = WhisperModelVariant.allCases.filter(\.isEnglishOnly)
            XCTAssertEqual(distilled.count, 4)
            for variant in distilled {
                var config = ASRConfig(kind: .whisperKit, whisperModel: variant.rawValue)
                XCTAssertEqual(LocalModels.whisperFolder(for: variant.rawValue).lastPathComponent, variant.directoryName)
                XCTAssertTrue(variant.directoryName.hasPrefix("distil-whisper_"))
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "en")
                config.language = "zh"
                XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(config))
                config.language = "en-US"
                XCTAssertEqual(try SpeechLanguagePolicy.resolve(config).language, "en")
            }
        }
        // RetiredCoreMLChoiceRequiresSetup
        do {
            var meeting = MediaConfiguration()
            meeting.selectModelChoice("coreml:retired")
            XCTAssertThrowsError(try meeting.validate())
            XCTAssertFalse(LocalModels.isInstalled(meeting.asr))
            XCTAssertNil(LocalModels.coreMLSpeechFolder(for: "../outside"))
            XCTAssertNotNil(ProfileSpeechModel(config: meeting.asr).unavailableReason)
        }
        // OrukeetUsesVerifiedArchiveAndTheParakeetTransducerLayout
        do {
            let model = SherpaTranscriber.Model.orukeet
            XCTAssertTrue(model.archiveURL.path.contains("55a984d46f68323301837194ce647c702f55facc"))
            XCTAssertEqual(model.archiveSHA256, "f9191f30178cc9122ce2f023bf9fefafc822028307b0efa4caff645ba3fe8d0a")
            let configuration = try SherpaTranscriber.RecognizerConfiguration(model: model, hints: .init(language: "en"))
            configuration.withCConfiguration(folder: URL(fileURLWithPath: "/isolated"), files: ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]) { native in
                XCTAssertEqual(String(cString: native.model_config.model_type), "nemo_transducer")
                XCTAssertEqual(String(cString: native.model_config.transducer.encoder), "/isolated/encoder.int8.onnx")
                XCTAssertNil(native.model_config.sense_voice.language)
            }
            XCTAssertThrowsError(try SpeechLanguagePolicy.resolve(ASRConfig(kind: .orukeet, language: "zh")))
        }
    }

}
