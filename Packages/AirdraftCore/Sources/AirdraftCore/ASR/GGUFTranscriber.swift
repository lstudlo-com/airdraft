import Foundation
import Synchronization
import TranscribeCppKit

/// Batch transcription through the official macOS transcribe.cpp runtime.
/// Weights are installed explicitly; model/session lifetimes never cross a
/// running native call, even when cancellation or unloading happens mid-decode.
public actor GGUFTranscriber: Transcriber {
    public nonisolated let id: String
    private let modelID: String
    private var model: NativeModel?
    private var loading: Task<NativeModel, Error>?
    private var generation = 0

    public init(modelID: String) {
        self.modelID = modelID
        id = "transcribe-cpp:\(modelID)"
    }
    public func isReady() async -> Bool { model != nil }
    public func prepare() async throws { _ = try await loadedModel() }
    public func unload() async {
        generation += 1
        loading?.cancel()
        loading = nil
        model = nil
    }

    public func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
        guard let entry = GGUFModelCatalog.model(modelID) else { throw TranscriberError.modelNotDownloaded }
        var config = entry.config
        config.language = hints.language ?? ""
        let language = entry.nativeLanguage(try SpeechLanguagePolicy.resolve(config).language)
        let native = try await loadedModel()
        let started = Date()
        var detected: String?
        let text = try await AudioChunker.transcribeAsync(samples, maxSeconds: native.windowSeconds) { chunk in
            // Exact digital silence has no speech. Do not invent text on it.
            guard chunk.contains(where: { $0 != 0 }) else { return "" }
            let cancellation = NativeCancellation()
            let result = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                let worker = Task.detached(priority: .userInitiated) {
                    try native.decode(chunk, language: language, cancellation: cancellation)
                }
                let result = try await worker.value
                try Task.checkCancellation()
                return result
            } onCancel: { cancellation.cancel() }
            // Copy session-owned strings before the native session is destroyed.
            if detected == nil { detected = result.language }
            return result.text
        }
        let fixedLanguage = entry.supportedLanguages.count == 1 ? entry.supportedLanguages[0] : nil
        return Transcript(text: text, language: detected ?? language ?? fixedLanguage, engine: id,
                          latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }

    private func loadedModel() async throws -> NativeModel {
        try Task.checkCancellation()
        guard let entry = GGUFModelCatalog.model(modelID), LocalModels.isInstalled(entry.config),
              let file = LocalModels.ggufFile(for: modelID) else { throw TranscriberError.modelNotDownloaded }
        if let model { return model }
        let current = generation
        let task: Task<NativeModel, Error>
        if let loading { task = loading }
        else {
            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let loaded = try NativeModel(file: file)
                try Task.checkCancellation()
                return loaded
            }
            loading = task
        }
        do {
            let loaded = try await withTaskCancellationHandler {
                let value = try await task.value
                try Task.checkCancellation()
                return value
            } onCancel: { task.cancel() }
            guard current == generation else { throw CancellationError() }
            model = loaded
            loading = nil
            return loaded
        } catch {
            if current == generation { loading = nil }
            throw error
        }
    }
}

private final class NativeCancellation: Sendable {
    private let cancelled = Mutex(false)
    func cancel() { cancelled.withLock { $0 = true } }
    var isCancelled: Bool { cancelled.withLock { $0 } }
}

private final class NativeModel: Sendable {
    // One backend initialization per process, before any model is constructed.
    private static let backendStatus = transcribe_init_backends_default()
    /// The native model handle is immutable after init and freed only in deinit.
    /// transcribe.cpp allows one compute call per model; `runLock` serializes them.
    nonisolated(unsafe) private let pointer: OpaquePointer
    private let runLock = NSLock()
    let windowSeconds: Double

    init(file: URL) throws {
        try Self.check(Self.backendStatus)
        var params = transcribe_model_load_params()
        transcribe_model_load_params_init(&params)
        var handle: OpaquePointer?
        try Self.check(transcribe_model_load_file(file.path, &params, &handle))
        guard let handle else { throw TranscriberError.invalidResponse }
        pointer = handle
        var caps = transcribe_capabilities()
        transcribe_capabilities_init(&caps)
        do {
            try Self.check(transcribe_model_get_capabilities(handle, &caps))
            guard caps.native_sample_rate == 16_000 else {
                throw TranscriberError.providerFailure(String(localized: "Local speech model", bundle: .module), String(localized: "Unsupported sample rate.", bundle: .module))
            }
            windowSeconds = caps.max_audio_ms > 0 ? min(25, Double(caps.max_audio_ms) / 1000) : 25
        } catch {
            transcribe_model_free(handle)
            throw error
        }
    }
    deinit { transcribe_model_free(pointer) }

    struct Result: Sendable { let text: String; let language: String? }
    func decode(_ samples: [Float], language: String?, cancellation: NativeCancellation) throws -> Result {
        // The C API permits only one in-flight compute operation per model.
        runLock.lock()
        defer { runLock.unlock() }
        if cancellation.isCancelled { throw CancellationError() }
        var session: OpaquePointer?
        try Self.check(transcribe_session_init(pointer, nil, &session))
        guard let session else { throw TranscriberError.invalidResponse }
        defer { transcribe_session_free(session) }
        let context = Unmanaged.passUnretained(cancellation).toOpaque()
        transcribe_set_abort_callback(session, { context in
            guard let context else { return false }
            return Unmanaged<NativeCancellation>.fromOpaque(context).takeUnretainedValue().isCancelled
        }, context)
        defer { transcribe_set_abort_callback(session, nil, nil) }
        var params = transcribe_run_params()
        transcribe_run_params_init(&params)
        params.task = TRANSCRIBE_TASK_TRANSCRIBE
        params.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
        params.diarize = TRANSCRIBE_DIARIZE_MODE_OFF
        params.keep_special_tags = false
        func run(_ languagePointer: UnsafePointer<CChar>?) -> transcribe_status {
            params.language = languagePointer
            return samples.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32($0.count), &params) }
        }
        let status = language.map { $0.withCString { run($0) } } ?? run(nil)
        if cancellation.isCancelled || transcribe_was_aborted(session) { throw CancellationError() }
        try Self.check(status)
        guard !transcribe_was_truncated(session) else {
            throw TranscriberError.providerFailure(String(localized: "Local speech model", bundle: .module), String(localized: "The decoder truncated the result. Try a shorter recording.", bundle: .module))
        }
        let text = transcribe_full_text(session).map { String(cString: $0) } ?? ""
        let detected = transcribe_detected_language(session).map { String(cString: $0) }
        return Result(text: text, language: detected?.isEmpty == false ? detected : nil)
    }

    private static func check(_ status: transcribe_status) throws {
        guard status == TRANSCRIBE_OK else {
            let message = transcribe_status_string(Int32(status.rawValue)).map { String(cString: $0) } ?? "Native decoding failed."
            throw TranscriberError.providerFailure(String(localized: "Local speech model", bundle: .module), message)
        }
    }
}
