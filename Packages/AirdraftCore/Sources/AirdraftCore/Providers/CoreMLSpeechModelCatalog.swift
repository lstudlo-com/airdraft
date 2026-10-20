import Foundation

/// Exact FluidAudio component manifests. Files are loaded locally through
/// loadLocal, never through the SDK's automatic download/recovery helpers.
public struct CoreMLSpeechModel: Codable, Sendable, Identifiable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public let path: String
        public let bytes: Int64
        public let sha256: String
    }
    public let id: String
    public let title: String
    public let repository: String
    public let revision: String
    public let version: String
    public let precision: String
    public let creator: String
    public let languages: [String]
    public let files: [File]
    public var config: ASRConfig { ASRConfig(kind: .fluidAudio, model: id) }
    public var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
    public var languageCapabilities: SpeechLanguageCapabilities {
        .init(modelName: title, supportedLanguages: languages, supportsAutomatic: true,
              manualControl: .notApplied,
              summary: languages.count == 1 ? String(localized: "Recognizes \(SpeechLanguagePolicy.languageName(languages[0])) only.", bundle: .module)
                  : String(localized: "Automatically recognizes \(languages.count) European languages; no Chinese support.", bundle: .module))
    }
}

public enum CoreMLSpeechModelCatalog {
    public static let models: [CoreMLSpeechModel] = {
        guard let url = Bundle.module.url(forResource: "local-coreml-models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([CoreMLSpeechModel].self, from: data) else {
            preconditionFailure("The bundled Core ML speech catalogue is missing or invalid.")
        }
        return models
    }()
    private static let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    public static func model(_ id: String) -> CoreMLSpeechModel? { byID[id] }
}
