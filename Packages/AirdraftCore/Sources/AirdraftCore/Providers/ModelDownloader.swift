import CohereTranscribeASR
import Foundation
import Qwen3ASR

/// Anonymous downloads into `LocalModels.root`. Never sends a Hugging Face
/// token, so a stale `~/.cache/huggingface/token` cannot break it.
public actor ModelDownloader {
    public static let shared = ModelDownloader()

    public struct Progress: Sendable, Equatable {
        public var fraction: Double
        public var currentFile: String
        public init(fraction: Double, currentFile: String) {
            self.fraction = min(1, max(0, fraction))
            self.currentFile = currentFile
        }
    }

    public enum DownloadError: Error, LocalizedError {
        case listing(status: Int)
        case download(file: String, status: Int)
        case emptyListing
        case alreadyInProgress
        case incomplete
        case unsafePath(String)
        public var errorDescription: String? {
            switch self {
            case .listing(let s): return "Could not list model files (HTTP \(s))."
            case .download(let f, let s): return "Download of \(f) failed (HTTP \(s))."
            case .alreadyInProgress: return "This model is already downloading."
            case .incomplete: return "The model download is incomplete. Retry to finish the missing files."
            case .emptyListing: return "The model folder is empty on Hugging Face."
            case .unsafePath(let path): return "Refused to download \(path): it points outside the models folder."
            }
        }
    }

    public typealias ProgressHandler = @Sendable (Progress) -> Void

    /// Keys of downloads in flight; a second request fails instead of claiming completion.
    private var active: Set<String> = []

    private func exclusive(_ key: String, _ work: () async throws -> Void) async throws {
        guard !active.contains(key) else { throw DownloadError.alreadyInProgress }
        active.insert(key)
        defer { active.remove(key) }
        try await work()
    }

    /// Downloads whatever the engine `config` selects needs; no-op for engines without files.
    public func download(_ config: ASRConfig, progress: @escaping ProgressHandler) async throws {
        try await exclusive("install:\(config.engineID)") {
            let marker: URL?
            if let folder = LocalModels.folder(for: config) {
                let root = LocalModels.root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
                guard folder.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root) else {
                    throw DownloadError.unsafePath(folder.path)
                }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                marker = folder.appendingPathComponent(LocalModels.incompleteMarker)
                try Data().write(to: marker!, options: .atomic)
            } else { marker = nil }
            try await downloadFiles(config, progress: progress)
            try Task.checkCancellation()
            guard LocalModels.hasFiles(config) else { throw DownloadError.incomplete }
            if let marker { try FileManager.default.removeItem(at: marker) }
        }
    }

    private func downloadFiles(_ config: ASRConfig, progress: @escaping ProgressHandler) async throws {
        switch config.kind {
        case .whisperKit: try await downloadWhisper(variant: config.whisperModel, progress: progress)
        case .qwen3: try await downloadQwen3(modelId: config.qwen3Model, progress: progress)
        case .cohere: try await downloadCohere(modelId: config.cohereModel, progress: progress)
        case .fireRed: try await downloadSherpa(model: .fireRed, progress: progress)
        case .senseVoice: try await downloadSherpa(model: .senseVoice, progress: progress)
        case .apple, .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox: return
        }
    }

    /// Qwen3-ASR weights through speech-swift's own anonymous downloader.
    public func downloadQwen3(modelId: String, progress: @escaping ProgressHandler) async throws {
        try await exclusive("qwen3:\(modelId)") {
            progress(Progress(fraction: 0, currentFile: "weights"))
            _ = try await Qwen3ASRModel.fromPretrained(
                modelId: modelId,
                cacheDir: LocalModels.qwen3Folder(for: modelId),
                offlineMode: false,
                progressHandler: { fraction, stage in progress(Progress(fraction: fraction, currentFile: stage)) }
            )
        }
    }

    /// Cohere Transcribe weights through speech-swift's own anonymous downloader.
    public func downloadCohere(modelId: String, progress: @escaping ProgressHandler) async throws {
        try await exclusive("cohere:\(modelId)") {
            progress(Progress(fraction: 0, currentFile: "weights"))
            _ = try await CohereTranscribeModel.fromPretrained(
                modelId,
                cacheDir: LocalModels.cohereFolder(for: modelId),
                offlineMode: false,
                progressHandler: { fraction in progress(Progress(fraction: fraction, currentFile: "weights")) }
            )
        }
    }

    /// Fetches a sherpa-onnx release archive (.tar.bz2) and unpacks it with /usr/bin/tar.
    public func downloadSherpa(model: SherpaTranscriber.Model, progress: @escaping ProgressHandler) async throws {
        try await exclusive("sherpa:\(model.rawValue)") {
            progress(Progress(fraction: 0, currentFile: model.folderName + ".tar.bz2"))
            let (tmp, response) = try await URLSession.shared.download(from: model.archiveURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                try? FileManager.default.removeItem(at: tmp)
                throw DownloadError.download(file: model.folderName, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            progress(Progress(fraction: 0.8, currentFile: "unpacking"))
            let root = LocalModels.sherpaRoot
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let archive = root.appendingPathComponent(model.folderName + ".tar.bz2")
            try? FileManager.default.removeItem(at: archive)
            try FileManager.default.moveItem(at: tmp, to: archive)
            defer { try? FileManager.default.removeItem(at: archive) }
            let status = try await Self.unpack(archive, into: root)
            guard status == 0, LocalModels.hasSherpa(model) else {
                throw DownloadError.download(file: model.folderName, status: Int(status))
            }
        }
    }

    /// A WhisperKit variant plus the shared tokenizer files, from the Hub's public file API.
    public func downloadWhisper(variant: String, progress: @escaping ProgressHandler) async throws {
        try await exclusive("whisper:\(variant)") {
            let repo = "argmaxinc/whisperkit-coreml"
            let modelFiles = try await listFiles(repo: repo, path: "openai_whisper-\(variant)")
            guard !modelFiles.isEmpty else { throw DownloadError.emptyListing }

            let total = max(1, modelFiles.reduce(Int64(0)) { $0 + ($1.size ?? 0) })
            var completed: Int64 = 0
            for entry in modelFiles {
                // The listing comes from the network: never let a path leave the models folder.
                guard !entry.path.hasPrefix("/"), !entry.path.split(separator: "/").contains("..") else {
                    throw DownloadError.unsafePath(entry.path)
                }
                let dest = LocalModels.whisperKitRoot.appendingPathComponent(entry.path)
                let name = (entry.path as NSString).lastPathComponent
                progress(Progress(fraction: Double(completed) / Double(total), currentFile: name))
                let existing = (try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? Int64
                if existing == nil || existing != entry.size {
                    try await download(repo: repo, path: entry.path, to: dest)
                }
                completed += entry.size ?? 0
            }

            guard !LocalModels.hasWhisperTokenizer else { return }
            for name in LocalModels.whisperTokenizerFiles {
                try Task.checkCancellation()
                let file = LocalModels.whisperTokenizerFolder.appendingPathComponent(name)
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int64 ?? 0
                if size > 0 { continue }
                progress(Progress(fraction: 1, currentFile: name))
                try await download(repo: "openai/whisper-large-v3", path: name, to: LocalModels.whisperTokenizerFolder.appendingPathComponent(name))
            }
        }
    }

    /// bsdtar refuses absolute and `..` member paths by default.
    private static func unpack(_ archive: URL, into root: URL) async throws -> Int32 {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xjf", archive.path, "-C", root.path]
        return try await withCheckedThrowingContinuation { continuation in
            tar.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try tar.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - Hub helpers

    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64?
    }

    private func listFiles(repo: String, path: String) async throws -> [TreeEntry] {
        var url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main/\(path)")!
        url.append(queryItems: [URLQueryItem(name: "recursive", value: "true")])
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DownloadError.listing(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode([TreeEntry].self, from: data).filter { $0.type == "file" }
    }

    private func download(repo: String, path: String, to dest: URL) async throws {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encoded)")!
        let (tmp, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tmp)
            throw DownloadError.download(file: path, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: dest.path) {
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
    }
}
