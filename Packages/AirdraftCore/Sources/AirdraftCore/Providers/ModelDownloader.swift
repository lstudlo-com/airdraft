import CohereTranscribeASR
import CryptoKit
import Foundation
import Qwen3ASR

/// Anonymous downloads into `LocalModels.root`. Never sends a Hugging Face
/// token, so a stale `~/.cache/huggingface/token` cannot break it.
public actor ModelDownloader {
    public static let shared = ModelDownloader()

    public struct Progress: Sendable, Equatable {
        /// Nil means the current stage has no measurable total, never an invented zero percent.
        public var fraction: Double?
        public var currentFile: String
        public var receivedBytes: Int64?
        public var totalBytes: Int64?
        public init(fraction: Double?, currentFile: String, receivedBytes: Int64? = nil, totalBytes: Int64? = nil) {
            self.fraction = fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
            self.currentFile = currentFile
            self.receivedBytes = receivedBytes
            self.totalBytes = totalBytes
        }

        public var detail: String {
            var parts: [String] = []
            if let fraction, fraction > 0 {
                // Tiny files can arrive well before the first weights chunk. Keep that
                // progress visible, and never round an unfinished transfer up to 100%.
                parts.append(fraction < 0.001 ? "<0.1%" : String(format: "%.1f%%", floor(fraction * 1_000) / 10))
            }
            if let receivedBytes, receivedBytes > 0 {
                let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
                if let totalBytes {
                    parts.append("\(received) of \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                } else { parts.append("\(received) received") }
            }
            return parts.joined(separator: " · ")
        }
    }

    public enum DownloadError: Error, LocalizedError {
        case listing(status: Int)
        case download(file: String, status: Int)
        case emptyListing
        case alreadyInProgress
        case incomplete
        case checksumMismatch
        case unsafePath(String)
        public var errorDescription: String? {
            switch self {
            case .listing(let s): return "Could not list model files (HTTP \(s))."
            case .download(let f, let s): return "Download of \(f) failed (HTTP \(s))."
            case .alreadyInProgress: return "This model is already downloading."
            case .incomplete: return "The model download is incomplete. Retry to finish the missing files."
            case .checksumMismatch: return "The model archive failed its integrity check. Download it again."
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
        case .parakeet: try await downloadSherpa(model: .parakeet, progress: progress)
        case .apple:
            progress(Progress(fraction: nil, currentFile: "Installing language…"))
            try await AppleSpeechTranscriber(locale: config.effectiveAppleLocale).prepare()
            progress(Progress(fraction: 1, currentFile: "Language installed"))
        case .openAICompatible, .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini: return
        }
    }

    /// Qwen3-ASR weights through speech-swift's own anonymous downloader.
    public func downloadQwen3(modelId: String, progress: @escaping ProgressHandler) async throws {
        try await exclusive("qwen3:\(modelId)") {
            progress(Progress(fraction: nil, currentFile: "Preparing download…"))
            _ = try await Qwen3ASRModel.fromPretrained(
                modelId: modelId,
                cacheDir: LocalModels.qwen3Folder(for: modelId),
                offlineMode: false,
                progressHandler: { fraction, stage in
                    progress(Progress(fraction: fraction > 0 && fraction < 0.8 ? fraction / 0.8 : nil,
                                      currentFile: stage))
                }
            )
        }
    }

    /// Cohere Transcribe weights through speech-swift's own anonymous downloader.
    public func downloadCohere(modelId: String, progress: @escaping ProgressHandler) async throws {
        try await exclusive("cohere:\(modelId)") {
            progress(Progress(fraction: nil, currentFile: "Preparing download…"))
            _ = try await CohereTranscribeModel.fromPretrained(
                modelId,
                cacheDir: LocalModels.cohereFolder(for: modelId),
                offlineMode: false,
                progressHandler: { fraction in
                    progress(Progress(fraction: fraction > 0 && fraction < 1 ? fraction : nil,
                                      currentFile: fraction >= 1 ? "Preparing model…" : "Downloading weights…"))
                }
            )
        }
    }

    /// Fetches a sherpa-onnx release archive (.tar.bz2) and unpacks it with /usr/bin/tar.
    public func downloadSherpa(model: SherpaTranscriber.Model, progress: @escaping ProgressHandler) async throws {
        try await exclusive("sherpa:\(model.rawValue)") {
            progress(Progress(fraction: nil, currentFile: "Connecting…"))
            let (tmp, response) = try await ModelDownloadTransfer.download(from: model.archiveURL) { received, total in
                progress(Progress(fraction: total.map { Double(received) / Double($0) },
                                  currentFile: model.folderName + ".tar.bz2", receivedBytes: received, totalBytes: total))
            }
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw DownloadError.download(file: model.folderName, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            try Task.checkCancellation()
            try await Self.installSherpaArchive(tmp, model: model, root: LocalModels.sherpaRoot, progress: progress)
        }
    }

    /// Verify before touching the installation root, including an existing model.
    static func installSherpaArchive(_ downloaded: URL, model: SherpaTranscriber.Model,
                                    root: URL, progress: ProgressHandler) async throws {
        if let checksum = model.archiveSHA256 {
            progress(Progress(fraction: nil, currentFile: "Verifying archive…"))
            try verifySHA256(of: downloaded, expected: checksum)
        }
        progress(Progress(fraction: nil, currentFile: "Unpacking…"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent(model.folderName + ".tar.bz2")
        try? FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: downloaded, to: archive)
        defer { try? FileManager.default.removeItem(at: archive) }
        let status = try await unpack(archive, into: root)
        guard status == 0, LocalModels.hasSherpa(model, at: root.appendingPathComponent(model.folderName)) else {
            throw DownloadError.download(file: model.folderName, status: Int(status))
        }
    }

    /// Stream the archive so verification does not retain hundreds of MB in memory.
    static func verifySHA256(of file: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: bytes)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw DownloadError.checksumMismatch }
    }

    /// A WhisperKit variant plus the shared tokenizer files, from the Hub's public file API.
    public func downloadWhisper(variant: String, progress: @escaping ProgressHandler) async throws {
        try await exclusive("whisper:\(variant)") {
            progress(Progress(fraction: nil, currentFile: "Preparing download…"))
            let repo = "argmaxinc/whisperkit-coreml"
            let modelFiles = try await listFiles(repo: repo, path: "openai_whisper-\(variant)")
            guard !modelFiles.isEmpty else { throw DownloadError.emptyListing }
            var files = try modelFiles.map { try transferFile($0, repo: repo, root: LocalModels.whisperKitRoot) }
            if !LocalModels.hasWhisperTokenizer {
                let tokenizerRepo = "openai/whisper-large-v3"
                let tokenizerFiles = try await listFiles(repo: tokenizerRepo, path: "")
                    .filter { LocalModels.whisperTokenizerFiles.contains($0.path) }
                guard tokenizerFiles.count == LocalModels.whisperTokenizerFiles.count else { throw DownloadError.emptyListing }
                files += try tokenizerFiles.map { try transferFile($0, repo: tokenizerRepo, root: LocalModels.whisperTokenizerFolder) }
            }
            try await ModelDownloadTransfer.install(files, progress: progress)
        }
    }

    /// bsdtar refuses absolute and `..` member paths by default.
    static func unpack(_ archive: URL, into root: URL) async throws -> Int32 {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xjf", archive.path, "-C", root.path]
        return try await CLIProcess.run(tar, input: "", timeout: 300).status
    }

    /// Explicit user-triggered installation. SpeakerKit inference always uses download: false.
    public func downloadSpeakerModel(progress: @escaping ProgressHandler) async throws {
        try await exclusive("speakerkit") {
            let folder = LocalSpeakerDiarizer.folder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let marker = folder.appendingPathComponent(LocalModels.incompleteMarker)
            try Data().write(to: marker, options: .atomic)
            var files: [ModelDownloadTransfer.File] = []
            for path in LocalSpeakerDiarizer.modelPaths {
                let entries = try await listFiles(repo: "argmaxinc/speakerkit-coreml", path: path)
                guard !entries.isEmpty else { throw DownloadError.emptyListing }
                files += try entries.map { try transferFile($0, repo: "argmaxinc/speakerkit-coreml", root: folder) }
            }
            try await ModelDownloadTransfer.install(files, progress: progress)
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: marker)
            guard LocalSpeakerDiarizer.isInstalled else { throw DownloadError.incomplete }
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

    private func transferFile(_ entry: TreeEntry, repo: String, root: URL) throws -> ModelDownloadTransfer.File {
        guard !entry.path.isEmpty, !entry.path.hasPrefix("/"), !entry.path.split(separator: "/").contains("..") else {
            throw DownloadError.unsafePath(entry.path)
        }
        let destination = root.appendingPathComponent(entry.path)
        guard destination.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(
            root.standardizedFileURL.resolvingSymlinksInPath().path + "/") else { throw DownloadError.unsafePath(entry.path) }
        let encoded = entry.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.path
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(encoded)")!
        return .init(url: url, destination: destination, size: entry.size)
    }
}
