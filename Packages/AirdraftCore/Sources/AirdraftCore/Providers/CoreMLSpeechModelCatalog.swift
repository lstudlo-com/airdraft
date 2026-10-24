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
    /// Nil only for an entry that would fail catalogue review.
    public func downloadURL(for file: File) -> URL? {
        ModelCatalogueReview.downloadURL(repository: repository, revision: revision, path: file.path)
    }
    public var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
    public var languageCapabilities: SpeechLanguageCapabilities {
        .init(modelName: title, supportedLanguages: languages, supportsAutomatic: true,
              manualControl: .notApplied,
              summary: languages.count == 1 ? String(localized: "Recognizes \(SpeechLanguagePolicy.languageName(languages[0])) only.", bundle: .module)
                  : String(localized: "Automatically recognizes \(languages.count) European languages.", bundle: .module))
    }
}

public enum CoreMLSpeechModelCatalog {
    static let bundled = catalog(url: Bundle.module.url(forResource: "local-coreml-models", withExtension: "json"))

    /// Reviewed models; empty when the bundled catalogue is damaged.
    public static var models: [CoreMLSpeechModel] { bundled.models }
    /// Non-nil when the bundled catalogue is missing or fails review.
    public static var catalogueError: ModelCatalogueError? { bundled.error }
    public static func model(_ id: String) -> CoreMLSpeechModel? { bundled.model(id) }

    static func catalog(url: URL?) -> BundledModelCatalog<CoreMLSpeechModel> {
        BundledModelCatalog(url: url, catalogue: .coreML) { model in
            guard ModelCatalogueReview.isSafeComponent(model.id) else { return "unsafe ID" }
            guard ModelCatalogueReview.isRepository(model.repository) else { return "invalid repository" }
            guard ModelCatalogueReview.isRevision(model.revision) else { return "unpinned revision" }
            guard !model.languages.isEmpty else { return "no languages" }
            guard !model.files.isEmpty else { return "no files" }
            guard Set(model.files.map(\.path)).count == model.files.count else { return "duplicate files" }
            for file in model.files {
                guard ModelCatalogueReview.isSafeRelativePath(file.path) else { return "unsafe path \(file.path)" }
                guard file.bytes > 0 else { return "missing size for \(file.path)" }
                guard ModelCatalogueReview.isSHA256(file.sha256) else { return "invalid SHA-256 for \(file.path)" }
                guard model.downloadURL(for: file) != nil else { return "invalid download URL for \(file.path)" }
            }
            return nil
        }
    }
}
