import XCTest
@testable import AirdraftCore

/// User-facing labels use catalogue names; raw IDs stay in `engineLabel`/`engineID`.
final class ModelDisplayNameTests: XCTestCase {
    func testLocalSpeechModelsUseCatalogueTitlesWithRuntime() {
        XCTAssertEqual(ASRConfig(kind: .whisperKit).displayName, "Whisper Large v3 Turbo · Core ML")
        XCTAssertEqual(ASRConfig(kind: .whisperKit, whisperModel: "distil-large-v3").displayName,
                       "Distil-Whisper Large v3 · Core ML")
        XCTAssertEqual(ASRConfig(kind: .qwen3).displayName, "Qwen3-ASR 1.7B · MLX")
        XCTAssertEqual(ASRConfig(kind: .qwen3, qwen3Model: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit").displayName,
                       "Qwen3-ASR 0.6B · MLX")
        XCTAssertEqual(ASRConfig(kind: .cohere).displayName, "Cohere Transcribe · MLX")
        XCTAssertEqual(ASRConfig(kind: .fireRed).displayName, "FireRedASR2 · ONNX")
        XCTAssertEqual(ASRConfig(kind: .senseVoice).displayName, "SenseVoice · ONNX")
        XCTAssertEqual(ASRConfig(kind: .parakeet).displayName, "Parakeet TDT v3 · ONNX")
        XCTAssertEqual(ASRConfig(kind: .orukeet).displayName, "Orukeet · ONNX")
        XCTAssertEqual(ASRConfig(kind: .apple).displayName, "Apple Speech")
    }

    func testEveryCatalogueModelHasItsTitle() {
        for variant in WhisperModelVariant.allCases {
            XCTAssertEqual(ASRConfig(kind: .whisperKit, whisperModel: variant.rawValue).modelDisplayName, variant.title)
        }
        for model in CoreMLSpeechModelCatalog.models {
            XCTAssertEqual(ASRConfig(kind: .fluidAudio, model: model.id).displayName, "\(model.title) · Core ML")
        }
        for model in GGUFModelCatalog.models {
            XCTAssertEqual(model.config.displayName, "\(model.title) · GGUF \(model.quantization)")
        }
    }

    func testSameFamilyVariantsStayDistinguishable() {
        let whisper = [ASRConfig(kind: .whisperKit).displayName,
                       ASRConfig(kind: .transcribeCpp, model: "whisper-large-v3-turbo").displayName]
        XCTAssertEqual(Set(whisper).count, 2, "\(whisper)")
        let qwen = [ASRConfig(kind: .qwen3).displayName,
                    ASRConfig(kind: .transcribeCpp, model: "qwen3-asr-1.7b").displayName]
        XCTAssertEqual(Set(qwen).count, 2, "\(qwen)")
    }

    func testCloudSpeechUsesModelTitleAndHost() {
        var config = ASRConfig()
        config.select(.openAI)
        config.selectModel("gpt-4o-mini-transcribe")
        XCTAssertEqual(config.displayName, "GPT-4o Mini Transcribe · OpenAI")
        for preset in EndpointPreset.asr {
            for model in SpeechModelInfo.models(for: preset.kind) {
                var cloud = ASRConfig()
                cloud.select(preset.kind)
                cloud.selectModel(model.id)
                XCTAssertEqual(cloud.displayName, "\(model.title) · \(preset.name)")
                XCTAssertFalse(cloud.engineID.isEmpty, "Display names never replace engine identity")
            }
        }
    }

    func testUnknownAndCustomModelsFallBackToRawIDs() {
        XCTAssertEqual(ASRConfig(kind: .fluidAudio, model: "vendor/unknown").modelDisplayName, "vendor/unknown")
        XCTAssertEqual(ASRConfig(kind: .transcribeCpp, model: "unlisted-gguf").displayName, "unlisted-gguf · GGUF")
        XCTAssertEqual(ASRConfig(kind: .whisperKit, whisperModel: "tiny").modelDisplayName, "Whisper tiny")
        XCTAssertEqual(ASRConfig(kind: .qwen3, qwen3Model: "me/Qwen3-ASR-custom").modelDisplayName, "Qwen3-ASR-custom")
        let custom = ASRConfig(kind: .openAICompatible, baseURL: "http://speech.local:9000/v1", model: "my-whisper")
        XCTAssertEqual(custom.displayName, "my-whisper · speech.local")
        var router = ASRConfig()
        router.select(.openRouter)
        router.selectModel("vendor/new-speech-model")
        XCTAssertTrue(router.displayName.contains("vendor/new-speech-model"))
    }

    func testDisplayNamesDoNotChangeIdentityOrStoredData() throws {
        let config = ASRConfig(kind: .whisperKit)
        XCTAssertEqual(config.engineID, "whisperkit:large-v3-v20240930_turbo")
        XCTAssertEqual(config.engineLabel, "WhisperKit · large-v3-v20240930_turbo")
        let encoded = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Whisper Large v3 Turbo"))
    }

    func testRefinementShowsProviderAndReadableModel() {
        XCTAssertEqual(LLMConfig().displayName, "LM Studio · Gemma 4 26B A4B QAT")
        XCTAssertEqual(LLMConfig().engineLabel, "localhost · google/gemma-4-26b-a4b-qat", "Raw identifiers stay available for help text")
        var ollama = LLMConfig(baseURL: "http://localhost:11434/v1", model: "qwen3:8b")
        XCTAssertEqual(ollama.displayName, "Ollama · Qwen3 8B")
        ollama.baseURL = "http://gpu-box.lan:8000/v1"
        ollama.model = "Qwen/Qwen3-30B-A3B"
        XCTAssertEqual(ollama.displayName, "gpu-box.lan · Qwen3-30B-A3B")

        var config = LLMConfig()
        config.select(.anthropic)
        XCTAssertEqual(config.displayName, "Anthropic · Claude Haiku 4.5")
        config.select(.openAI)
        XCTAssertEqual(config.displayName, "OpenAI · GPT-4.1 Mini")
        config.select(.groq)
        XCTAssertEqual(config.displayName, "Groq · GPT-OSS 20B")
        config.select(.gemini)
        XCTAssertEqual(config.displayName, "Gemini · Gemini 2.5 Flash")
        config.select(.claudeCode)
        XCTAssertEqual(config.displayName, "Claude Code · Sonnet")
        config.model = ""
        XCTAssertEqual(config.displayName, "Claude Code · Default model")
        config.select(.appleIntelligence)
        XCTAssertEqual(config.displayName, "Apple Intelligence")
        config.select(.none)
        XCTAssertEqual(config.displayName, "Off")
    }

    func testReadableModelNames() {
        let cases = [
            ("gemini-2.5-flash", "Gemini 2.5 Flash"),
            ("claude-sonnet-4-5-20250929", "Claude Sonnet 4.5"),
            ("gpt-5.1-codex-mini", "GPT-5.1 Codex Mini"),
            ("gemma-3-12b-it", "Gemma 3 12B IT"),
            ("meta-llama/llama-3.3-70b-instruct", "Llama 3.3 70B Instruct"),
            ("qwen-3.8-27b", "Qwen 3.8 27B"),
            ("llama3.2:latest", "Llama3.2"),
            ("Mixed-Case-ID", "Mixed-Case-ID"),
            ("", ""),
        ]
        for (id, expected) in cases {
            XCTAssertEqual(LLMConfig.readableModelName(id), expected, id)
        }
    }
}
