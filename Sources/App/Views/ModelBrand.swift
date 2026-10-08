import AirdraftCore
import SwiftUI

/// Model identity belongs to its creator, independently of the hosting service.
enum ModelBrand: String {
    case qwen = "Qwen", alibaba = "Alibaba", fireRed = "FireRed", cohere = "Cohere"
    case nvidia = "NVIDIA", openAI = "OpenAI", apple = "Apple"
    case soniox = "Soniox", groq = "Groq", elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram", openRouter = "OpenRouter"
    case cartesia = "Cartesia", speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI", fishAudio = "FishAudio", google = "Google", gemini = "Gemini"
    case meta = "Meta", microsoft = "Microsoft", mistral = "Mistral", xAI = "xAI"

    static func speech(_ model: SpeechModelInfo, hostedBy provider: ASRProviderKind) -> ModelBrand {
        let id = model.id.lowercased()
        let name = id.split(separator: "/").last.map(String.init) ?? id
        if id.hasPrefix("openai/") || name.hasPrefix("whisper") || name.hasPrefix("gpt-") { return .openAI }
        if id.hasPrefix("qwen/") || name.hasPrefix("qwen") { return .qwen }
        if id.hasPrefix("nvidia/") || name.hasPrefix("parakeet") { return .nvidia }
        if id.hasPrefix("cohere/") { return .cohere }
        if id.hasPrefix("deepgram/") { return .deepgram }
        if id.hasPrefix("elevenlabs/") { return .elevenLabs }
        if id.hasPrefix("assemblyai/") { return .assemblyAI }
        if id.hasPrefix("fish-audio/") || id.hasPrefix("fishaudio/") { return .fishAudio }
        if id.hasPrefix("google/") { return name.hasPrefix("gemini") ? .gemini : .google }
        if id.hasPrefix("meta/") || id.hasPrefix("meta-llama/") { return .meta }
        if id.hasPrefix("microsoft/") || id.hasPrefix("microsoft-ai/") { return .microsoft }
        if id.hasPrefix("mistralai/") || id.hasPrefix("mistral/") { return .mistral }
        if id.hasPrefix("x-ai/") || id.hasPrefix("xai/") || id.hasPrefix("spacexai/") { return .xAI }
        switch provider {
        case .soniox: return .soniox
        case .assemblyAI: return .assemblyAI
        case .cartesia: return .cartesia
        case .speechmatics: return .speechmatics
        case .xAI: return .xAI
        case .mistral: return .mistral
        case .gemini: return .gemini
        case .groq: return .groq
        case .elevenLabs: return .elevenLabs
        case .deepgram: return .deepgram
        case .openRouter: return .openRouter
        default: return .openAI
        }
    }
}

struct ModelBrandIcon: View {
    let brand: ModelBrand

    var body: some View {
        Group {
            if brand == .apple {
                Image(systemName: "apple.logo")
                    .font(.system(size: 22))
                    .foregroundStyle(.black)
            } else {
                Image("ModelBrand\(brand.rawValue)")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 24, height: 24)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}
