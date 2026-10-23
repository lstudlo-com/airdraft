import Foundation
import XCTest
@testable import AirdraftCore

/// AD-083 follow-up: Airdraft ships two SenseVoice artifacts. The original
/// multilingual SenseVoiceSmall is "SenseVoice"; the 2025-09-09 WSYue Cantonese
/// fine-tune, the only SenseVoice through 0.11.0, keeps its exact IDs as
/// "SenseVoice Cantonese" so existing selections never change model.
final class SenseVoiceArtifactTests: XCTestCase {
    func testExistingSelectionsKeepTheirExactEngineIDAndArtifact() throws {
        // A 0.11.0 settings blob: kind "senseVoice", no artifact field.
        let legacy = try JSONDecoder().decode(ASRConfig.self, from: Data(#"{"kind":"senseVoice","language":"zh"}"#.utf8))
        XCTAssertEqual(legacy.kind, .senseVoice)
        XCTAssertEqual(legacy.engineID, "sherpa-onnx:senseVoice")
        XCTAssertEqual(LocalModels.folder(for: legacy)?.lastPathComponent,
                       "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09")
        XCTAssertEqual(legacy.modelDisplayName, "SenseVoice Cantonese")
        XCTAssertEqual(SherpaTranscriber(model: .senseVoice).id, legacy.engineID)

        // A profile binding saved by 0.11.0 resolves to the same artifact.
        let binding = try JSONDecoder().decode(ProfileSpeechModel.self,
                                               from: Data(#"{"kind":"senseVoice","model":""}"#.utf8))
        XCTAssertEqual(binding.applying(to: ASRConfig(kind: .qwen3)).engineID, "sherpa-onnx:senseVoice")

        // Meetings documents and settings saved with "senseVoice" keep the Cantonese engine.
        let media = try JSONDecoder().decode(MediaConfiguration.self,
                                             from: Data(#"{"engine":"local","whisperModel":"large-v3-v20240930_turbo","language":"","identifySpeakers":false,"localModel":"senseVoice"}"#.utf8))
        XCTAssertEqual(media.selectedLocalModel.kind, .senseVoice)
        XCTAssertEqual(media.asr.engineID, "sherpa-onnx:senseVoice")
        XCTAssertEqual(media.selectedModelTitle, "SenseVoice Cantonese")
    }

    func testMultilingualArtifactHasItsOwnIdentityFolderAndBinding() throws {
        let config = ASRConfig(kind: .senseVoiceMultilingual)
        XCTAssertEqual(config.engineID, "sherpa-onnx:senseVoiceMultilingual")
        XCTAssertEqual(SherpaTranscriber(model: .senseVoiceMultilingual).id, config.engineID)
        XCTAssertEqual(LocalModels.folder(for: config)?.lastPathComponent,
                       "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17")
        XCTAssertNotEqual(LocalModels.folder(for: config), LocalModels.folder(for: ASRConfig(kind: .senseVoice)))
        XCTAssertEqual(config.modelDisplayName, "SenseVoice")
        XCTAssertTrue(ModelSpeechPreview.supports(config))

        let binding = ProfileSpeechModel(config: config)
        let decoded = try JSONDecoder().decode(ProfileSpeechModel.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(decoded.applying(to: ASRConfig(kind: .senseVoice)).kind, .senseVoiceMultilingual)

        var media = MediaConfiguration()
        media.selectModelChoice(MediaConfiguration.LocalModel.senseVoiceMultilingual.rawValue)
        XCTAssertEqual(media.asr.kind, .senseVoiceMultilingual)
        XCTAssertEqual(media.asr.engineID, "sherpa-onnx:senseVoiceMultilingual")
        XCTAssertEqual(MediaConfiguration.LocalModel.senseVoice.rawValue, "senseVoice")
    }

    func testMultilingualArchiveIsPinnedByURLBytesAndDigest() {
        let model = SherpaTranscriber.Model.senseVoiceMultilingual
        XCTAssertEqual(model.archiveURL.absoluteString,
                       "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2")
        XCTAssertEqual(model.archiveBytes, 163_002_883)
        XCTAssertEqual(model.archiveSHA256, "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e")
        XCTAssertEqual(model.sizeLabel, "163 MB")
        XCTAssertEqual(SherpaTranscriber.Model.senseVoice.archiveBytes, 165_783_878)
        for model in SherpaTranscriber.Model.allCases { XCTAssertGreaterThan(model.archiveBytes, 100_000_000) }
        XCTAssertTrue(model.isSenseVoice && SherpaTranscriber.Model.senseVoice.isSenseVoice)
        XCTAssertFalse(SherpaTranscriber.Model.fireRed.isSenseVoice)
    }

    /// A download with the wrong size is rejected before hashing or unpacking.
    func testArchiveWithDifferentSizeNeverReachesTheModelFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-sensevoice-size-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let candidate = root.appendingPathComponent("candidate")
        try Data("short archive".utf8).write(to: candidate)
        do {
            try await ModelDownloader.installSherpaArchive(candidate, model: .senseVoiceMultilingual,
                                                           root: root.appendingPathComponent("models")) { _ in }
            XCTFail("A size mismatch must fail")
        } catch ModelDownloader.DownloadError.checksumMismatch {
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("models").path))
    }

    /// Both artifacts run the SenseVoice decoder with the selected language token.
    func testBothArtifactsUseTheSenseVoiceNativeConfiguration() throws {
        for model in [SherpaTranscriber.Model.senseVoice, .senseVoiceMultilingual] {
            let configuration = try SherpaTranscriber.RecognizerConfiguration(model: model, hints: .init(language: "yue"))
            try configuration.withCConfiguration(folder: URL(fileURLWithPath: "/fixture"), files: ["model.int8.onnx"]) { native in
                XCTAssertEqual(String(cString: try XCTUnwrap(native.model_config.model_type)), "sense_voice")
                XCTAssertEqual(String(cString: try XCTUnwrap(native.model_config.sense_voice.language)), "yue")
                XCTAssertEqual(String(cString: try XCTUnwrap(native.model_config.sense_voice.model)), "/fixture/model.int8.onnx")
            }
        }
    }

    func testMeetingsOfferTheCantoneseArtifactOnlyWhenItIsAlreadySelected() {
        let offered = MediaConfiguration.modelChoices.map(\.id)
        XCTAssertTrue(offered.contains("senseVoiceMultilingual"))
        XCTAssertFalse(offered.contains("senseVoice"))
        XCTAssertTrue(MediaConfiguration.modelChoices(keeping: "senseVoice").map(\.id).contains("senseVoice"))
        XCTAssertEqual(MediaConfiguration.modelChoices(keeping: "senseVoice").first { $0.id == "senseVoice" }?.title,
                       "SenseVoice Cantonese")
    }

    func testChineseRecommendationPointsAtTheMultilingualArtifact() {
        XCTAssertEqual(LocalSpeechRecommendation.Model.senseVoice.catalogueID, "sherpa:senseVoiceMultilingual")
        let small = LocalModelShortlist.make(languageCode: "zh-Hant-TW", physicalMemory: 8 << 30)
        XCTAssertEqual(small.picks.first?.id, "sherpa:senseVoiceMultilingual")
        for code in ["zh-Hant-TW", "zh-Hans", "ja", "ko", "en"] {
            XCTAssertFalse(LocalModelShortlist.make(languageCode: code, physicalMemory: 8 << 30).ids.contains("sherpa:senseVoice"), code)
            XCTAssertFalse(LocalModelShortlist.make(languageCode: code, physicalMemory: 32 << 30).ids.contains("sherpa:senseVoice"), code)
        }
    }
}

/// AD-083 follow-up: a cold prepare builds the SenseVoice recognizer for the
/// language the recording will use, not Auto, so the first dictation after a
/// load no longer rebuilds it (about 350 ms). A language change still rebuilds.
final class SenseVoicePreparationTests: XCTestCase {
    private typealias Configuration = SherpaTranscriber.RecognizerConfiguration

    override func tearDown() {
        SherpaTranscriber.anticipate(TranscriptionHints())
        super.tearDown()
    }

    func testPreparationBuildsTheAnticipatedLanguage() throws {
        SherpaTranscriber.anticipate(TranscriptionHints(language: "ja"))
        let prepared = try SherpaTranscriber.anticipatedConfiguration(for: .senseVoiceMultilingual)
        XCTAssertEqual(prepared.language, "ja")
        XCTAssertEqual(prepared, try Configuration(model: .senseVoiceMultilingual, hints: .init(language: "ja")),
                       "The dictation's own configuration must equal the prewarmed one")

        SherpaTranscriber.anticipate(TranscriptionHints(language: "zh"))
        XCTAssertEqual(try SherpaTranscriber.anticipatedConfiguration(for: .senseVoice).language, "zh")
        SherpaTranscriber.anticipate(TranscriptionHints(language: nil))
        XCTAssertNil(try SherpaTranscriber.anticipatedConfiguration(for: .senseVoiceMultilingual).language)
    }

    func testLanguageTheModelCannotUseFallsBackToAutoInsteadOfFailing() throws {
        // The Cantonese artifact does not offer Japanese; Parakeet takes no language.
        SherpaTranscriber.anticipate(TranscriptionHints(language: "ja"))
        XCTAssertNil(try SherpaTranscriber.anticipatedConfiguration(for: .senseVoice).language)
        XCTAssertNil(try SherpaTranscriber.anticipatedConfiguration(for: .parakeet).language)
        XCTAssertNil(try SherpaTranscriber.anticipatedConfiguration(for: .fireRed).language)
    }

    func testAnticipationKeepsTheVocabularyChoiceWithTheLanguage() throws {
        SherpaTranscriber.anticipate(TranscriptionHints(language: "en", vocabulary: ["Supabase"]))
        XCTAssertTrue(try SherpaTranscriber.anticipatedConfiguration(for: .parakeet).hotwordDecoding)
        XCTAssertFalse(try SherpaTranscriber.anticipatedConfiguration(for: .senseVoiceMultilingual).hotwordDecoding)
        XCTAssertEqual(try SherpaTranscriber.anticipatedConfiguration(for: .senseVoiceMultilingual).language, "en")
    }

    func testChangingLanguageStillRequiresARebuild() throws {
        SherpaTranscriber.anticipate(TranscriptionHints(language: "ja"))
        let prepared = try SherpaTranscriber.anticipatedConfiguration(for: .senseVoiceMultilingual)
        XCTAssertNotEqual(prepared, try Configuration(model: .senseVoiceMultilingual, hints: .init(language: "ko")))
        XCTAssertNotEqual(prepared, try Configuration(model: .senseVoiceMultilingual))
    }
}

/// Review follow-ups: live preview after the first prewarm, and optional
/// vocabulary bias that must never fail a dictation.
final class SherpaPrewarmAndHotwordFallbackTests: XCTestCase {
    private typealias Configuration = SherpaTranscriber.RecognizerConfiguration

    override func tearDown() {
        SherpaTranscriber.anticipate(TranscriptionHints())
        super.tearDown()
    }

    /// Live preview compares the loaded recognizer with the recording's own
    /// hints (`isWarm`). The prewarm now builds exactly that configuration, so
    /// the first session's preview is not skipped for an explicit language.
    func testPrewarmConfigurationMatchesTheFirstSessionsPreviewHints() throws {
        for (model, language) in [(SherpaTranscriber.Model.senseVoiceMultilingual, "ja"), (.senseVoiceMultilingual, "ko"),
                                  (.senseVoice, "yue"), (.senseVoice, "zh")] {
            let hints = TranscriptionHints(language: language)
            SherpaTranscriber.anticipate(hints)
            XCTAssertEqual(try SherpaTranscriber.anticipatedConfiguration(for: model), try Configuration(model: model, hints: hints),
                           "\(model) \(language)")
        }
    }

    func testGreedyFallbackKeepsLanguageAndDropsOnlyTheHotwordDecoder() throws {
        let hotwords = try Configuration(model: .parakeet, hints: .init(language: "en", vocabulary: ["Supabase"]))
        XCTAssertTrue(hotwords.hotwordDecoding)
        let greedy = hotwords.withoutHotwords
        XCTAssertFalse(greedy.hotwordDecoding)
        XCTAssertEqual(greedy, try Configuration(model: .parakeet, hints: .init(language: "en")))
        try greedy.withCConfiguration(folder: URL(fileURLWithPath: "/fixture"), files: ["encoder.int8.onnx"]) { native in
            XCTAssertEqual(String(cString: try XCTUnwrap(native.decoding_method)), "greedy_search")
        }
    }

    /// Native, model-gated: set AIRDRAFT_SENSEVOICE_TEST_MODEL_DIR to an installed
    /// sherpa-onnx SenseVoice folder (either artifact; Japanese needs the multilingual one).
    func testNativePrewarmIsWarmForTheFirstExplicitLanguageSession() async throws {
        guard let path = ProcessInfo.processInfo.environment["AIRDRAFT_SENSEVOICE_TEST_MODEL_DIR"] else {
            throw XCTSkip("Set AIRDRAFT_SENSEVOICE_TEST_MODEL_DIR to an installed SenseVoice folder")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let model: SherpaTranscriber.Model = directory.lastPathComponent.contains("2024-07-17") ? .senseVoiceMultilingual : .senseVoice
        let language = model == .senseVoiceMultilingual ? "ja" : "yue"
        let engine = SherpaTranscriber(model: model, modelDirectory: directory)
        let hints = TranscriptionHints(language: language)
        SherpaTranscriber.anticipate(hints)
        try await engine.prepare()
        let warm = await engine.isWarm(for: hints)
        XCTAssertTrue(warm, "The first session's preview must find the prewarmed recognizer")
        let loaded = await engine.loadedConfiguration
        XCTAssertEqual(loaded?.language, language)
        await engine.unload()
    }

    /// Native, model-gated (the same variable as ParakeetTests): an unreadable
    /// vocabulary falls back to greedy decoding and the dictation still transcribes.
    func testNativeUnreadableHotwordVocabularyFallsBackToGreedyDecoding() async throws {
        guard let path = ProcessInfo.processInfo.environment["AIRDRAFT_PARAKEET_TEST_MODEL_DIR"] else {
            throw XCTSkip("Set AIRDRAFT_PARAKEET_TEST_MODEL_DIR to an installed Parakeet INT8 folder")
        }
        struct Unreadable: Error {}
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let engine = SherpaTranscriber(model: .parakeet, modelDirectory: directory)
        await engine.setHotwordVocabularyReader { _ in throw Unreadable() }
        let samples = try AudioFile.load(path: directory.appendingPathComponent("test_wavs/en.wav").path)
        let result = try await engine.transcribe(samples: samples, hints: .init(language: "en", vocabulary: ["Supabase"]))
        XCTAssertFalse(result.text.isEmpty)
        let loaded = await engine.loadedConfiguration
        XCTAssertEqual(loaded?.hotwordDecoding, false)
        // A later dictation with the same vocabulary reuses the greedy recognizer.
        _ = try await engine.transcribe(samples: samples, hints: .init(language: "en", vocabulary: ["Supabase"]))
        await engine.unload()
    }
}
