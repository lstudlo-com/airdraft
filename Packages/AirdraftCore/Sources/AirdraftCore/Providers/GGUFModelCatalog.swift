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

    /// Nil only for an entry that would fail catalogue review.
    public var downloadURL: URL? {
        ModelCatalogueReview.downloadURL(repository: repository, revision: revision, path: filename)
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
            summary = String(localized: "Recognizes \(SpeechLanguagePolicy.languageName(supportedLanguages[0])) only.", bundle: .module)
        } else if control == .notApplied {
            summary = String(localized: "Automatically recognizes \(supportedLanguages.count) supported languages; selection has no effect.", bundle: .module)
        } else if automatic {
            summary = String(localized: "\(supportedLanguages.count) languages.", bundle: .module)
        } else {
            summary = String(localized: "\(supportedLanguages.count) languages. Choose one; automatic detection is unavailable.", bundle: .module)
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
    static let bundled = catalog(url: Bundle.module.url(forResource: "local-gguf-models", withExtension: "json"))

    /// Reviewed models; empty when the bundled catalogue is damaged.
    public static var models: [GGUFModel] { bundled.models }
    /// Non-nil when the bundled catalogue is missing or fails review.
    public static var catalogueError: ModelCatalogueError? { bundled.error }
    public static func model(_ id: String) -> GGUFModel? { bundled.model(id) }

    static func catalog(url: URL?) -> BundledModelCatalog<GGUFModel> {
        BundledModelCatalog(url: url, catalogue: .gguf) { model in
            guard ModelCatalogueReview.isSafeComponent(model.id) else { return "unsafe ID" }
            guard ModelCatalogueReview.isRepository(model.repository) else { return "invalid repository" }
            guard ModelCatalogueReview.isRevision(model.revision) else { return "unpinned revision" }
            guard ModelCatalogueReview.isSafeComponent(model.filename) else { return "unsafe file name" }
            guard model.bytes > 0 else { return "missing size" }
            guard ModelCatalogueReview.isSHA256(model.sha256) else { return "invalid SHA-256" }
            guard !model.languages.isEmpty else { return "no languages" }
            guard model.downloadURL != nil else { return "invalid download URL" }
            return nil
        }
    }
}
