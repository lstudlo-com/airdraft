import Foundation

/// Reviewed choices supported by the pinned transcribe.cpp distribution.
/// Each choice has one quantization, an immutable Hub revision and a digest.
/// Published benchmark scores are deliberately not copied into app ratings.
public struct GGUFModel: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let family: String
    public let creator: String
    public let brand: String
    public let repository: String
    public let revision: String
    public let filename: String
    public let quantization: String
    public let bytes: Int64
    public let sha256: String
    public let languages: [String]
    public let automatic: Bool
    public let manualControl: String
    public let license: String
    public let documentation: String

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(filename)")!
    }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
    public var config: ASRConfig { ASRConfig(kind: .transcribeCpp, model: id) }
    public var supportedLanguages: [String] {
        Array(Set(languages.compactMap { try? SpeechLanguagePolicy.canonicalLanguage($0) })).sorted()
    }
    public var languageCapabilities: SpeechLanguageCapabilities {
        let control: SpeechLanguageManualControl = manualControl == "automatic" ? .notApplied : .forced
        let summary: String
        if supportedLanguages.count == 1 {
            summary = "Recognizes \(SpeechLanguagePolicy.languageName(supportedLanguages[0])) only."
        } else if control == .notApplied {
            summary = "Automatically recognizes \(supportedLanguages.count) supported languages; selection has no effect."
        } else if automatic {
            summary = "\(supportedLanguages.count) languages. Auto Detect or a selected language."
        } else {
            summary = "\(supportedLanguages.count) languages. Select a language; Auto Detect is unavailable."
        }
        return .init(modelName: title, supportedLanguages: supportedLanguages,
                     supportsAutomatic: automatic, manualControl: control, summary: summary)
    }

    /// Preserve the vocabulary advertised by the native artifact (including
    /// regional BCP-47 tags), while validating the shared normalized preference.
    func nativeLanguage(_ resolved: String?) -> String? {
        guard let resolved else { return nil }
        return languages.first { $0 == resolved }
            ?? languages.first { (try? SpeechLanguagePolicy.canonicalLanguage($0)) == resolved }
    }
}

public enum GGUFModelCatalog {
    public static let models: [GGUFModel] = {
        guard let url = Bundle.module.url(forResource: "local-gguf-models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([GGUFModel].self, from: data) else {
            preconditionFailure("The bundled local speech catalogue is missing or invalid.")
        }
        return models
    }()
    private static let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    public static func model(_ id: String) -> GGUFModel? { byID[id] }
}
