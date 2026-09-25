import XCTest
@testable import AirdraftCore

final class SpeechPresetTests: XCTestCase {
    func testSixCurrentProvidersWithOpenRouterReusingItsRefinementCredential() {
        let presets = EndpointPreset.asr
        XCTAssertEqual(presets.count, 6)
        XCTAssertEqual(Set(presets.map(\.kind)), [.openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox])
        XCTAssertEqual(Set(presets.map(\.keyRef)).count, 6)
        XCTAssertEqual(ASRProviderKind.openRouter.preset?.keyRef, LLMProviderKind.openRouter.keyRef)
        XCTAssertEqual(Set(presets.map(\.purpose)).count, 6)
        for preset in presets {
            var config = ASRConfig()
            config.select(preset.kind)
            XCTAssertFalse(config.kind.isLocal)
            XCTAssertEqual(config.keyRef, preset.keyRef)
            XCTAssertEqual(config.model, preset.defaultModel)
            XCTAssertTrue(ModelCatalog.transcriptionModels(for: preset.kind).contains(config.model))
            XCTAssertTrue(LocalModels.isInstalled(config))
            XCTAssertNil(LocalModels.folder(for: config))
        }
        XCTAssertEqual(ModelCatalog.transcriptionModels(for: .openAI), ["gpt-transcribe", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"])
        XCTAssertEqual(ModelCatalog.transcriptionModels(for: .elevenLabs), ["scribe_v2", "scribe_v2_medical"])
        XCTAssertEqual(ModelCatalog.transcriptionModels(for: .soniox), ["stt-async-v5"])
        XCTAssertEqual(ASRProviderKind.openRouter.preset?.defaultModel, "openai/whisper-1")
    }

    func testEveryModelSurvivesProviderSwitchesAndSettingsReload() throws {
        for preset in EndpointPreset.asr {
            for model in SpeechModelInfo.models(for: preset.kind) {
                var config = ASRConfig()
                config.select(preset.kind)
                config.selectModel(model.id)
                config.select(preset.kind) // Clicking an already selected row must not reset it.
                XCTAssertEqual(config.selectedSpeechModel, model)
                config.select(.whisperKit)
                config.select(preset.kind)
                for other in EndpointPreset.asr where other.kind != preset.kind { config.select(other.kind) }
                config = try JSONDecoder().decode(ASRConfig.self, from: JSONEncoder().encode(config))
                config.select(preset.kind)
                XCTAssertEqual(config.model, model.id)
                XCTAssertEqual(config.selectedSpeechModel, model)
                XCTAssertEqual(config.keyRef, preset.keyRef)
                XCTAssertFalse(model.price.isEmpty)
                XCTAssertFalse(model.qualityDetail.isEmpty)
                XCTAssertFalse(model.speedDetail.isEmpty)
            }
        }
    }

    func testLegacySupportedModelsArePreservedAndRetiredModelsFallBack() throws {
        for (kind, model) in [(ASRProviderKind.openAI, "gpt-4o-mini-transcribe"), (.groq, "whisper-large-v3"), (.elevenLabs, "scribe_v2_medical")] {
            let data = try JSONSerialization.data(withJSONObject: ["kind": kind.rawValue, "model": model])
            let config = try JSONDecoder().decode(ASRConfig.self, from: data)
            XCTAssertEqual(config.selectedSpeechModel?.id, model)
        }
        var config = ASRConfig(kind: .soniox, model: "stt-async-v4", modelByProvider: ["soniox": "stt-async-v4"])
        config.select(.soniox)
        XCTAssertEqual(config.model, "stt-async-v5")
    }

    func testOldOpenAIAndGroqSettingsMigrateWithoutLosingLanguageOrLocalModels() throws {
        for (url, key, expected) in [("https://api.openai.com/v1/", "asr.openai", ASRProviderKind.openAI),
                                     ("https://api.groq.com/openai/v1", "asr.groq", .groq)] {
            let data = try JSONSerialization.data(withJSONObject: ["kind": "openAICompatible", "baseURL": url,
                "apiKeyRef": key, "model": "whisper-1", "language": "zh", "chineseScript": "traditional", "qwen3Model": "saved-local-model"])
            let config = try JSONDecoder().decode(ASRConfig.self, from: data)
            XCTAssertEqual(config.kind, expected)
            XCTAssertEqual(config.keyRef, key)
            XCTAssertEqual(config.model, expected.preset?.defaultModel)
            XCTAssertEqual(config.language, "zh")
            XCTAssertEqual(config.chineseScript, .traditional)
            XCTAssertEqual(config.qwen3Model, "saved-local-model")
        }
    }

    func testCustomEndpointsAndCredentialsAreNeverRedirected() throws {
        for (url, key) in [("https://api.openai.com.example.org/v1", "asr.openai"),
                           ("https://proxy.example.com/v1", "asr.custom"),
                           ("https://api.openai.com/v1", "my-custom-key")] {
            let original = ASRConfig(kind: .openAICompatible, baseURL: url, model: "my-model", apiKeyRef: key)
            let restored = try JSONDecoder().decode(ASRConfig.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(restored, original)
        }
    }

    func testScribeV1SettingsMigrateAndCurrentConfigsRoundTrip() throws {
        let old = ASRConfig(kind: .elevenLabs, elevenLabsModel: "scribe_v1")
        let migrated = try JSONDecoder().decode(ASRConfig.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(migrated.elevenLabsModel, "scribe_v2")
        XCTAssertEqual(migrated.keyRef, "asr.elevenlabs")
        for preset in EndpointPreset.asr {
            var config = ASRConfig()
            config.select(preset.kind)
            let restored = try JSONDecoder().decode(ASRConfig.self, from: JSONEncoder().encode(config))
            XCTAssertEqual(restored, config)
        }
    }

    func testOpenRouterDynamicModelSurvivesProviderSwitchAndReload() throws {
        var config = ASRConfig()
        config.select(.openRouter)
        config.selectModel("vendor/new-speech-model")
        XCTAssertEqual(config.model, "vendor/new-speech-model")
        XCTAssertEqual(config.selectedSpeechModel?.id, config.model)
        XCTAssertEqual(config.engineID, "openRouter:vendor/new-speech-model")
        XCTAssertEqual(config.keyRef, "llm.openrouter")
        config.select(.openAI)
        config.select(.openRouter)
        XCTAssertEqual(config.model, "vendor/new-speech-model")
        let restored = try JSONDecoder().decode(ASRConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored.model, "vendor/new-speech-model")
        XCTAssertEqual(restored.selectedSpeechModel?.id, restored.model)
        XCTAssertTrue(restored.engineLabel.contains("vendor/new-speech-model"))
    }

    @MainActor
    func testFactoryBuildsEachNativeAdapterWithMatchingIdentity() async {
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in nil })
        for (kind, type) in [(ASRProviderKind.openAI, "OpenAITranscriber"), (.openRouter, "OpenRouterTranscriber"), (.groq, "OpenAICompatibleTranscriber"),
                             (.elevenLabs, "ElevenLabsTranscriber"), (.deepgram, "DeepgramTranscriber"), (.soniox, "SonioxTranscriber")] {
            var config = ASRConfig()
            config.select(kind)
            for model in ModelCatalog.transcriptionModels(for: kind) {
                config.selectModel(model)
                let engine = await factory.transcriber(for: config)
                XCTAssertEqual(String(describing: Swift.type(of: engine)), type)
                XCTAssertEqual(engine.id, config.engineID)
                switch engine {
                case let e as OpenAITranscriber: XCTAssertEqual(e.model, model)
                case let e as OpenRouterTranscriber: XCTAssertEqual(e.model, model)
                case let e as OpenAICompatibleTranscriber: XCTAssertEqual(e.model, model)
                case let e as ElevenLabsTranscriber: XCTAssertEqual(e.modelId, model)
                case let e as DeepgramTranscriber: XCTAssertEqual(e.model, model)
                default: break
                }
            }
        }
    }
}
