import AirdraftCore
import Foundation
import Observation
import os

/// Transcribe on iPhone: import an audio or video file, or record a long
/// conversation with the microphone, then transcribe it with the same
/// resumable media jobs as the Mac (speaker turns, checkpoints, exports).
/// iOS cannot capture other apps' audio, so recordings are microphone only.
@MainActor
@Observable
final class TranscribeController {
    private(set) var documents: [TranscriptDocument] = []
    private(set) var recordingStartedAt: Date?
    private(set) var issue: String?
    private(set) var speakerModelInstalled = LocalSpeakerDiarizer.isInstalled
    private(set) var speakerDownload: Double?
    var configuration: MediaConfiguration {
        didSet { save() }
    }

    let runner: MediaJobRunner?
    var isRecording: Bool { recordingStartedAt != nil }
    /// Set by the container: dictation and its keyboard session hold the microphone.
    @ObservationIgnored var dictationHoldsMicrophone: () -> Bool = { false }

    @ObservationIgnored private let history: HistoryStore?
    @ObservationIgnored private let draftsDirectory: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private var sink: RecordingSink?
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "transcribe")
    private static let configurationKey = "ios.transcribe.configuration"

    init(history: HistoryStore?, factory: EngineFactory, directory: URL, speech: ASRConfig,
         defaults: UserDefaults = .standard) {
        self.history = history
        self.defaults = defaults
        draftsDirectory = directory.appendingPathComponent("MeetingDrafts", isDirectory: true)
        runner = history.map { MediaJobRunner(history: $0, directory: directory, factory: factory) }
        if let data = defaults.data(forKey: Self.configurationKey),
           let saved = try? JSONDecoder().decode(MediaConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = Self.configuration(matching: speech)
        }
        runner?.onChange = { [weak self] in Task { await self?.reload() } }
        recorder.interruptionHandler = { [weak self] _ in
            Task { @MainActor in self?.stopRecording() }
        }
    }

    /// The media model that matches the dictation model, when media supports it.
    static func configuration(matching speech: ASRConfig) -> MediaConfiguration {
        var configuration = MediaConfiguration(language: speech.language, identifySpeakers: false, localModel: .apple)
        switch speech.kind {
        case .fluidAudio: configuration.selectModelChoice("coreml:\(speech.model)")
        case .transcribeCpp: configuration.selectModelChoice("gguf:\(speech.model)")
        case .whisperKit where speech.whisperModel == WhisperModelVariant.turboCompressed.rawValue:
            configuration.selectLocalModel(.whisperTurboCompressed)
        case .soniox: configuration.engine = .soniox
        default: configuration.selectLocalModel(.apple)
        }
        return configuration
    }

    private func save() {
        if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: Self.configurationKey) }
    }

    func reload() async {
        guard let history else { return }
        do {
            documents = try await Task.detached(priority: .userInitiated) { try history.documents(limit: 200) }.value
        } catch {
            issue = error.localizedDescription
        }
    }

    func clearIssue() {
        issue = nil
        runner?.clearIssue()
    }

    // MARK: - Import

    /// Files from the document picker are security scoped: read them while
    /// access lasts, then the job owns a normalized copy.
    func importFile(_ url: URL) {
        guard let runner, !isRecording else { return }
        issue = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
        // Earlier copies were normalized into History by their jobs; only the new one is needed.
        if !runner.isBusy { try? FileManager.default.removeItem(at: root) }
        let staging = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let copy = staging.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: copy)
            runner.importFile(copy, configuration: configuration)
        } catch {
            issue = error.localizedDescription
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard history != nil, !isRecording, runner?.isBusy != true else { return }
        guard !dictationHoldsMicrophone() else {
            issue = String(localized: "End the keyboard session or dictation before recording.")
            return
        }
        issue = nil
        do {
            try FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true)
            let sink = try RecordingSink(directory: draftsDirectory)
            recorder.retainsSamples = false
            recorder.samplesHandler = { samples in sink.append(samples) }
            try recorder.start(microphone: .systemDefault)
            self.sink = sink
            recordingStartedAt = Date()
            Self.log.notice("recording started")
        } catch {
            recorder.samplesHandler = nil
            issue = error.localizedDescription
        }
    }

    func stopRecording() {
        guard isRecording, let sink else { return }
        _ = recorder.stop()
        recorder.samplesHandler = nil
        recordingStartedAt = nil
        self.sink = nil
        let directory = draftsDirectory
        let configuration = configuration
        Task {
            do {
                let draft = try await sink.finish()
                guard let history, let runner else { return }
                let asset = try await Task.detached {
                    try MeetingAudioStore.recover(draft, directory: directory, history: history, interrupted: false)
                }.value
                runner.transcribeRecording(asset, configuration: configuration)
                await reload()
            } catch {
                issue = error.localizedDescription
                Self.log.error("recording could not be saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Documents

    func delete(_ document: TranscriptDocument) {
        guard let history else { return }
        try? history.deleteDocument(id: document.id)
        documents.removeAll { $0.id == document.id }
    }

    func downloadSpeakerModel() {
        guard speakerDownload == nil else { return }
        speakerDownload = 0
        Task { [weak self] in
            do {
                try await ModelDownloader.shared.downloadSpeakerModel { progress in
                    Task { @MainActor in self?.speakerDownload = progress.fraction ?? 0 }
                }
                self?.speakerModelInstalled = LocalSpeakerDiarizer.isInstalled
            } catch {
                self?.issue = error.localizedDescription
            }
            self?.speakerDownload = nil
        }
    }
}

/// Writes microphone audio to a recoverable draft off the realtime thread.
/// Unchecked: `writer` and `written` are touched only on `queue`.
private final class RecordingSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "airdraft.transcribe.sink")
    private let writer: MeetingAudioWriter
    private var written = 0
    private var failure: Error?

    init(directory: URL) throws {
        writer = try MeetingAudioWriter(directory: directory, microphone: true)
    }

    func append(_ samples: [Float]) {
        queue.async { [self] in
            guard failure == nil else { return }
            do {
                try writer.append(samples, track: .microphone, at: Double(written) / Double(MeetingAudioWriter.sampleRate))
                written += samples.count
            } catch {
                failure = error
            }
        }
    }

    func finish() async throws -> MeetingDraft {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if let failure { throw failure }
                    continuation.resume(returning: try writer.finish())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
