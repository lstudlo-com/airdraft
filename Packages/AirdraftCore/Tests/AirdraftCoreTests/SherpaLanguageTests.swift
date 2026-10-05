import XCTest
@testable import AirdraftCore

final class SherpaLanguageTests: XCTestCase {
    private typealias Configuration = SherpaTranscriber.RecognizerConfiguration
    private let fixtureFolder = URL(fileURLWithPath: "/airdraft-language-contract-fixture", isDirectory: true)

    func testSenseVoicePassesSelectedLanguageToNativeConfiguration() throws {
        // Read the actual C field used by recognizer creation. A hard-coded
        // "auto" would fail every fixed-language case without loading any model.
        let cases: [(String?, String)] = [
            (nil, "auto"), ("", "auto"), ("auto", "auto"),
            ("zh", "zh"), ("zh-Hant", "zh"), ("zh_TW", "zh"),
            ("en-US", "en"), ("yue", "yue"), ("ja", "ja"), ("ko", "ko"),
        ]
        for (requested, expected) in cases {
            let configuration = try Configuration(model: .senseVoice, hints: .init(language: requested))
            try configuration.withCConfiguration(folder: fixtureFolder, files: ["model.int8.onnx", "tokens.txt"]) { native in
                let language = try XCTUnwrap(native.model_config.sense_voice.language)
                XCTAssertEqual(String(cString: language), expected, "Requested: \(requested ?? "nil")")
                XCTAssertEqual(native.model_config.sense_voice.use_itn, 1)
            }
        }
    }

    func testSenseVoiceCacheIdentityChangesWithLanguageButNotLocaleSpelling() throws {
        let automatic = try Configuration(model: .senseVoice)
        let chinese = try Configuration(model: .senseVoice, hints: .init(language: "zh"))
        let english = try Configuration(model: .senseVoice, hints: .init(language: "en"))
        let cantonese = try Configuration(model: .senseVoice, hints: .init(language: "yue"))
        XCTAssertNotEqual(automatic, chinese, "An auto recognizer must be rebuilt for fixed Chinese")
        XCTAssertNotEqual(chinese, english, "Changing languages must not reuse the previous recognizer")
        XCTAssertNotEqual(chinese, cantonese, "Cantonese must remain distinct from Mandarin")
        XCTAssertEqual(chinese, try Configuration(model: .senseVoice, hints: .init(language: "zh-TW")))
        XCTAssertEqual(automatic, try Configuration(model: .senseVoice, hints: .init(language: "auto")))
    }

    func testJointLanguageDecodersDoNotGetSenseVoiceLanguageControls() throws {
        for (model, languages) in [(SherpaTranscriber.Model.fireRed, ["zh", "en"]), (.parakeet, ["en", "de"])] {
            let automatic = try Configuration(model: model)
            for language in languages {
                let selected = try Configuration(model: model, hints: .init(language: language))
                XCTAssertNil(selected.language, "An ignored language hint is not detected-language metadata")
                XCTAssertEqual(selected, automatic, "Joint-language recognizers need no rebuild for a supported hint")
                selected.withCConfiguration(folder: fixtureFolder, files: []) { native in
                    XCTAssertNil(native.model_config.sense_voice.language)
                }
            }
        }
    }

    func testUnsupportedLanguageIsRejectedByTheAdapterBeforeModelAccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-sherpa-language-\(UUID().uuidString)")
        for (model, language) in [(SherpaTranscriber.Model.senseVoice, "fr"), (.fireRed, "ja"), (.parakeet, "zh")] {
            let engine = SherpaTranscriber(model: model, modelDirectory: directory)
            do {
                _ = try await engine.transcribe(samples: [0.1], hints: .init(language: language))
                XCTFail("Unsupported \(language) must be rejected for \(model)")
            } catch TranscriberError.modelNotDownloaded {
                XCTFail("Language validation must happen before model access for \(model)")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
            let ready = await engine.isReady()
            XCTAssertFalse(ready)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Validation must not create a model directory")
    }

    @MainActor
    func testSenseVoiceEngineIdentityRemainsStableAcrossLanguageChanges() async {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("Local speech must not read credentials")
            return nil
        })
        let chinese = ASRConfig(kind: .senseVoice, language: "zh")
        let english = ASRConfig(kind: .senseVoice, language: "en")
        let first = await factory.transcriber(for: chinese)
        let second = await factory.transcriber(for: english)
        XCTAssertEqual(chinese.engineID, "sherpa-onnx:senseVoice")
        XCTAssertEqual(first.id, chinese.engineID)
        XCTAssertEqual(second.id, english.engineID)
        XCTAssertTrue((first as AnyObject) === (second as AnyObject), "The actor reconfigures its recognizer; model identity stays stable")
    }
}
