import Foundation

/// A bundled speech catalogue (`local-gguf-models.json` or
/// `local-coreml-models.json`) that is missing, unreadable or fails review:
/// the app bundle is damaged. Its models are unavailable and nothing is
/// downloaded from it; every other engine and catalogue keeps working.
public struct ModelCatalogueError: Error, LocalizedError, Equatable, Sendable {
    public enum Catalogue: String, Sendable {
        case gguf
        case coreML
    }

    public let catalogue: Catalogue
    /// Diagnostic only: which check failed. Never shown as the message.
    public let detail: String

    public var errorDescription: String? {
        switch catalogue {
        case .gguf:
            String(localized: "Airdraft's list of reviewed GGUF speech models is missing or damaged, so these models can't be downloaded or used. Reinstall Airdraft to restore it.", bundle: .module)
        case .coreML:
            String(localized: "Airdraft's list of reviewed Core ML speech models is missing or damaged, so these models can't be downloaded or used. Reinstall Airdraft to restore it.", bundle: .module)
        }
    }
}

/// A decoded, reviewed catalogue, or why it is unavailable. A damaged file
/// yields no models instead of crashing at first use, and one invalid entry
/// (an unsafe ID or path, a malformed digest, a duplicate) rejects the whole
/// file: the bundle is not what was reviewed, so none of it is trusted.
struct BundledModelCatalog<Entry: Decodable & Identifiable & Sendable>: Sendable where Entry.ID == String {
    let models: [Entry]
    let error: ModelCatalogueError?
    private let byID: [String: Entry]

    /// `validate` returns why an entry is unacceptable, or nil.
    init(url: URL?, catalogue: ModelCatalogueError.Catalogue, validate: (Entry) -> String?) {
        do {
            guard let url else { throw ModelCatalogueError(catalogue: catalogue, detail: "not bundled") }
            let models = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
            guard !models.isEmpty else { throw ModelCatalogueError(catalogue: catalogue, detail: "empty") }
            for model in models {
                if let problem = validate(model) {
                    throw ModelCatalogueError(catalogue: catalogue, detail: "\(model.id): \(problem)")
                }
            }
            let byID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard byID.count == models.count else { throw ModelCatalogueError(catalogue: catalogue, detail: "duplicate IDs") }
            self.init(models: models, byID: byID, error: nil)
        } catch {
            self.init(models: [], byID: [:], error: error as? ModelCatalogueError
                ?? ModelCatalogueError(catalogue: catalogue, detail: String(describing: error)))
        }
    }

    private init(models: [Entry], byID: [String: Entry], error: ModelCatalogueError?) {
        self.models = models
        self.byID = byID
        self.error = error
    }

    func model(_ id: String) -> Entry? { byID[id] }

    /// The entry, the catalogue's own failure, or `unpinned` for an ID it does not review.
    func require(_ id: String) throws -> Entry {
        if let model = byID[id] { return model }
        if let error { throw error }
        throw ModelDownloader.DownloadError.unpinned(id)
    }
}

extension LocalModels {
    /// Why `config`'s bundled catalogue cannot supply its model, or nil. Readiness
    /// and recording checks show this reinstall message instead of "not installed".
    public static func catalogueError(for config: ASRConfig) -> ModelCatalogueError? {
        switch config.kind {
        case .transcribeCpp: GGUFModelCatalog.catalogueError
        case .fluidAudio: CoreMLSpeechModelCatalog.catalogueError
        default: nil
        }
    }
}

/// Shared checks for reviewed artifacts: values that become local paths or
/// download URLs must stay inside their folder and on the pinned revision.
enum ModelCatalogueReview {
    /// One file or folder name: no separators, no `.`/`..`, no hidden names.
    static func isSafeComponent(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    /// A relative path made of safe components.
    static func isSafeRelativePath(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { isSafeComponent(String($0)) }
    }

    static func isRepository(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    static func isRevision(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil
    }

    static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }

    /// The Hugging Face URL for a reviewed file, or nil when it cannot be formed.
    static func downloadURL(repository: String, revision: String, path: String) -> URL? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(encoded)")
    }
}
