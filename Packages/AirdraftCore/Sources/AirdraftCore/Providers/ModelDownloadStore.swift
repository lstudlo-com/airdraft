import Foundation
import Observation

/// Download ownership outlives any Models page or filtered row.
@MainActor @Observable
public final class ModelDownloadStore {
    public struct Job: Equatable {
        public var progress: ModelDownloader.Progress?
        public var error: String?
        public var cancelling = false
        fileprivate let token: UUID
    }
    public private(set) var jobs: [String: Job] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let download: @Sendable (ASRConfig, @escaping ModelDownloader.ProgressHandler) async throws -> Void
    @ObservationIgnored private let installed: @Sendable (ASRConfig) -> Bool

    public init(
        download: @escaping @Sendable (ASRConfig, @escaping ModelDownloader.ProgressHandler) async throws -> Void = { config, progress in
            try await ModelDownloader.shared.download(config, progress: progress)
        },
        installed: @escaping @Sendable (ASRConfig) -> Bool = { LocalModels.isInstalled($0) }
    ) {
        self.download = download
        self.installed = installed
    }

    public var isBusy: Bool { !tasks.isEmpty }

    #if DEBUG
    /// Isolated UI render data; does not start a transfer or change installed files.
    public func setPreviewProgress(_ progress: ModelDownloader.Progress, for config: ASRConfig) {
        guard tasks[config.engineID] == nil else { return }
        jobs[config.engineID] = Job(progress: progress, token: UUID())
    }
    #endif

    public func start(_ config: ASRConfig, onComplete: @escaping @MainActor () -> Void = {}) {
        let id = config.engineID
        guard tasks[id] == nil else { return }
        let token = UUID()
        jobs[id] = Job(progress: .init(fraction: nil, currentFile: "Preparing download…"), token: token)
        tasks[id] = Task { [self] in
            // Keep callback order and bound pending UI work when the network is fast.
            let (updates, continuation) = AsyncStream<ModelDownloader.Progress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let receiver = Task { @MainActor [weak self] in
                for await progress in updates {
                    guard let self, self.jobs[id]?.token == token,
                          self.tasks[id] != nil, self.jobs[id]?.cancelling == false else { continue }
                    self.jobs[id]?.progress = progress
                }
            }
            defer { continuation.finish(); receiver.cancel(); tasks[id] = nil }
            do {
                try await download(config) { continuation.yield($0) }
                continuation.finish()
                await receiver.value
                try Task.checkCancellation()
                guard installed(config) else { throw ModelDownloader.DownloadError.incomplete }
                jobs[id] = Job(progress: nil, token: token)
                onComplete()
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                jobs[id] = Job(progress: nil, error: cancelled ? "Download cancelled. Retry to resume." : error.localizedDescription, token: token)
            }
        }
    }

    public func cancel(_ config: ASRConfig) {
        guard let task = tasks[config.engineID] else { return }
        jobs[config.engineID]?.cancelling = true
        task.cancel()
    }

    public func cancelAll() { for task in tasks.values { task.cancel() } }
}
