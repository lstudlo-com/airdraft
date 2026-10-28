import Foundation
import Synchronization

/// One WebSocket frame.
public enum StreamingFrame: Sendable, Equatable {
    case text(String)
    case data(Data)

    /// A JSON object as a text frame. Keys are sorted so requests are deterministic.
    static func json(_ object: [String: Any]) -> StreamingFrame {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return .text(String(decoding: data, as: UTF8.self))
    }

    /// The frame's JSON object, or nil when it is not one.
    var jsonObject: [String: Any]? {
        let data: Data
        switch self {
        case .text(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// An open real-time connection. Production wraps `URLSessionWebSocketTask`;
/// tests inject a scripted fake, so no test reaches a provider.
public protocol StreamingConnection: Sendable {
    func send(_ frame: StreamingFrame) async throws
    func receive() async throws -> StreamingFrame
    func close()
}

public typealias StreamingConnector = @Sendable (URLRequest) async throws -> any StreamingConnection

/// Reads one provider's messages into finalized and provisional text.
/// Each session owns one parser and uses it from a single task.
public protocol StreamingParser: AnyObject {
    /// Every finalized word so far, joined the way the provider's batch API joins them.
    var finalText: String { get }
    /// The current non-final words, replaced by each update.
    var provisional: String { get }
    var language: String? { get }
    /// The provider has delivered everything for the ended input.
    var finished: Bool { get }
    /// False until the provider accepts the start frames.
    var readyForStart: Bool { get }
    /// False until the provider accepts audio; the session buffers audio until then.
    var readyForAudio: Bool { get }
    /// Throws `StreamingError.provider` for an error message.
    func consume(_ frame: StreamingFrame) throws
}

extension StreamingParser {
    public var readyForStart: Bool { true }
    public var readyForAudio: Bool { true }
}

/// AD-123: a cloud provider's real-time speech API for one recording.
public protocol StreamingSpeechProvider: Sendable {
    /// Whether the streamed final text is the batch model's own output with the
    /// same options; then it becomes the transcript instead of a second request.
    var matchesBatchModel: Bool { get }
    /// The batch transcriber's engine ID, recorded on a streamed transcript.
    var engineID: String { get }
    /// Audio sample rate the provider expects; samples are resampled from 16 kHz.
    var sampleRate: Int { get }
    /// The handshake request. Keys go in headers or subprotocols, never the URL;
    /// a provider that takes only a URL token mints a short-lived one first.
    func request(apiKey: String) async throws -> URLRequest
    func startFrames() -> [StreamingFrame]
    func audioFrame(_ pcm16: Data) -> StreamingFrame
    /// Frames that end the input; the provider then finalizes and finishes.
    func endFrames() -> [StreamingFrame]
    func makeParser() -> any StreamingParser
}

extension StreamingSpeechProvider {
    public var sampleRate: Int { 16_000 }
}

public enum StreamingError: Error, LocalizedError, Equatable {
    case provider(String)
    case closed
    case invalidMessage

    public var errorDescription: String? {
        switch self {
        case .provider(let message): return message
        case .closed: return String(localized: "The live text connection closed early.", bundle: .module)
        case .invalidMessage: return String(localized: "The live text service sent an unexpected reply.", bundle: .module)
        }
    }
}

public enum CloudLiveTranscript {
    /// How long release waits for the provider's final words before transcribing again.
    public static let finishSeconds: Double = 10

    /// 16 kHz mono Float32 as little-endian PCM16 at `rate`.
    static func pcm16(_ samples: [Float], rate: Int = 16_000) -> Data {
        let source = rate == 16_000 ? samples : resample(samples, to: rate)
        var data = Data(count: source.count * 2)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for (index, value) in source.enumerated() {
                let clamped = max(-1, min(1, value.isFinite ? value : 0))
                out[index] = Int16(clamped * Float(Int16.max)).littleEndian
            }
        }
        return data
    }

    /// Linear interpolation; enough for speech going to 24 kHz.
    static func resample(_ samples: [Float], to rate: Int) -> [Float] {
        guard rate != 16_000, !samples.isEmpty else { return samples }
        let ratio = Double(16_000) / Double(rate)
        let count = Int(Double(samples.count) / ratio)
        return (0..<count).map { index in
            let position = Double(index) * ratio
            let lower = Int(position)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            return samples[lower] * (1 - fraction) + samples[upper] * fraction
        }
    }

    /// The production connector: an ephemeral session with Airdraft's provider rules.
    public static let urlSessionConnector: StreamingConnector = { request in
        let task = webSocketSession.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
        return URLSessionStreamingConnection(task: task)
    }

    /// No cookies, cache or stored credentials; quiet sockets stay open through a long recording.
    private static let webSocketSession = ProviderTransport.makeSession(timeout: 900)
}

/// `URLSessionWebSocketTask` is thread-safe; this only adapts its messages.
private final class URLSessionStreamingConnection: StreamingConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    init(task: URLSessionWebSocketTask) { self.task = task }

    func send(_ frame: StreamingFrame) async throws {
        switch frame {
        case .text(let text): try await task.send(.string(text))
        case .data(let data): try await task.send(.data(data))
        }
    }

    func receive() async throws -> StreamingFrame {
        switch try await task.receive() {
        case .string(let text): return .text(text)
        case .data(let data): return .data(data)
        @unknown default: throw StreamingError.invalidMessage
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil) }
}

/// AD-123: live text streamed from a cloud provider. Audio is buffered until the
/// connection opens, so none is lost; at release the rest of the capture is sent,
/// the input ends and the provider's finalized text is the transcript when the
/// streaming model is the batch model. No callback after `cancel()` or finishing.
public final class CloudLiveTranscriptSession: LiveTranscriptSession, Sendable {
    private struct State {
        var appended = 0
        var published = ""
    }
    private let provider: any StreamingSpeechProvider
    private let audio: AsyncStream<[Float]>.Continuation
    private let state = Mutex(State())
    private let onText: @Sendable (String) -> Void
    private let onIssue: @Sendable (String) -> Void
    private let finishSeconds: Double
    /// Held while delivering callbacks and while stopping. Recursive so a callback can cancel.
    private let callbackLock = NSRecursiveLock()
    // Guarded by `callbackLock`.
    nonisolated(unsafe) private var stopped = false
    nonisolated(unsafe) private var worker: Task<Transcript?, Never>?
    private let connection = Mutex<(any StreamingConnection)?>(nil)

    public var reusesForTranscript: Bool { provider.matchesBatchModel }

    public init(provider: any StreamingSpeechProvider, apiKey: String, connector: @escaping StreamingConnector,
                finishSeconds: Double = CloudLiveTranscript.finishSeconds,
                onText: @escaping @Sendable (String) -> Void, onIssue: @escaping @Sendable (String) -> Void) {
        self.provider = provider
        self.onText = onText
        self.onIssue = onIssue
        self.finishSeconds = finishSeconds
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        audio = continuation
        let task = Task<Transcript?, Never>(priority: .userInitiated) { [weak self] in
            guard let self else { return nil }
            return await self.run(stream: stream, apiKey: apiKey, connector: connector)
        }
        callbackLock.withLock {
            if stopped { task.cancel() } else { worker = task }
        }
    }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let accepted = callbackLock.withLock { () -> Bool in
            guard !stopped else { return false }
            state.withLock { $0.appended += samples.count }
            return true
        }
        if accepted { audio.yield(samples) }
    }

    public func cancel() {
        let task = callbackLock.withLock { () -> Task<Transcript?, Never>? in
            stopped = true
            defer { worker = nil }
            return worker
        }
        shutDown(task)
    }

    private func shutDown(_ task: Task<Transcript?, Never>?) {
        audio.finish()
        task?.cancel()
        connection.withLock { $0 }?.close()
    }

    private func fail(_ error: Error) {
        let task = callbackLock.withLock { () -> Task<Transcript?, Never>? in
            guard !stopped else { return nil }
            stopped = true
            onIssue(String(localized: "Live text stopped: \(error.localizedDescription) Your recording continues.", bundle: .module))
            defer { worker = nil }
            return worker
        }
        shutDown(task)
    }

    public func finishTranscript(capture: [Float]) async -> Transcript? {
        let task = callbackLock.withLock { () -> Task<Transcript?, Never>?? in
            guard !stopped else { return nil }
            stopped = true
            defer { worker = nil }
            return .some(worker)
        }
        guard let task, let task else { return nil }
        // A streaming model that differs from the batch model never stands in for it.
        guard provider.matchesBatchModel else {
            shutDown(task)
            return nil
        }
        let appended = state.withLock { $0.appended }
        guard appended <= capture.count else {
            shutDown(task)
            return nil
        }
        // Audio still in flight when the recorder stopped is taken from the capture.
        if capture.count > appended { audio.yield(Array(capture[appended...])) }
        audio.finish()
        let started = ProcessInfo.processInfo.systemUptime
        let seconds = finishSeconds
        let transcript = try? await OperationDeadline.run(seconds: seconds) {
            await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        }
        guard var transcript, !Task.isCancelled else {
            shutDown(task)
            return nil
        }
        connection.withLock { $0 }?.close()
        transcript.latencyMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        return transcript
    }

    private func publish(final: String, provisional: String) {
        callbackLock.withLock {
            guard !stopped else { return }
            let display = state.withLock { state -> String? in
                let shown = ModelSpeechPreview.tail(ModelSpeechPreview.join(final, provisional), maximum: 500)
                guard !shown.isEmpty, shown != state.published else { return nil }
                state.published = shown
                return shown
            }
            if let display { onText(display) }
        }
    }

    private func receive(from socket: any StreamingConnection) async throws -> StreamingFrame {
        do {
            return try await socket.receive()
        } catch {
            throw Task.isCancelled ? CancellationError() : StreamingError.closed
        }
    }

    /// Connects, streams audio until the input ends, and returns the finalized
    /// transcript once the provider finishes; nil on failure or cancellation.
    private func run(stream: AsyncStream<[Float]>, apiKey: String, connector: StreamingConnector) async -> Transcript? {
        let provider = self.provider
        do {
            let socket = try await connector(try await provider.request(apiKey: apiKey))
            connection.withLock { $0 = socket }
            if Task.isCancelled { socket.close(); return nil }
            let parser = provider.makeParser()
            // Start frames and then audio wait, buffered, until the provider is ready for each.
            while !parser.readyForStart {
                try parser.consume(try await receive(from: socket))
            }
            for frame in provider.startFrames() { try await socket.send(frame) }
            while !parser.readyForAudio {
                try parser.consume(try await receive(from: socket))
            }
            let sender = Task {
                for await samples in stream {
                    try Task.checkCancellation()
                    try await socket.send(provider.audioFrame(CloudLiveTranscript.pcm16(samples, rate: provider.sampleRate)))
                }
                try Task.checkCancellation()
                for frame in provider.endFrames() { try await socket.send(frame) }
            }
            defer { sender.cancel() }
            while !parser.finished {
                try parser.consume(try await receive(from: socket))
                publish(final: parser.finalText, provisional: parser.provisional)
            }
            try await sender.value
            return Transcript(text: parser.finalText.trimmingCharacters(in: .whitespacesAndNewlines),
                              language: parser.language, engine: provider.engineID, latencyMs: 0)
        } catch {
            if !Task.isCancelled, !(error is CancellationError) { fail(error) }
            return nil
        }
    }
}

/// AD-123: the cloud speech configs Airdraft streams for live text.
public enum CloudStreaming {
    /// The provider's real-time API for this exact speech config, or nil when it
    /// has none Airdraft supports (Groq, OpenRouter, custom endpoints, unknown models).
    public static func provider(for config: ASRConfig, hints: TranscriptionHints) -> (any StreamingSpeechProvider)? {
        switch config.kind {
        case .soniox:
            guard config.speechModelID == "stt-async-v5" else { return nil }
            return SonioxStreaming(hints: hints, engineID: config.engineID)
        case .deepgram:
            // Whisper Large has no Deepgram streaming API.
            guard ["nova-3", "nova-3-multilingual"].contains(config.speechModelID) else { return nil }
            return DeepgramStreaming(model: config.speechModelID, hints: hints, engineID: config.engineID)
        case .xAI:
            guard config.speechModelID == "grok-voice-transcribe-2.0" else { return nil }
            return XAIStreaming(hints: hints, engineID: config.engineID)
        case .cartesia:
            guard config.speechModelID == "ink-whisper" else { return nil }
            return CartesiaStreaming(hints: hints, engineID: config.engineID)
        case .assemblyAI:
            guard ["universal-3-5-pro", "universal-3-6-pro-preview"].contains(config.speechModelID) else { return nil }
            return AssemblyAIStreaming(batchModel: config.speechModelID, hints: hints, engineID: config.engineID)
        case .speechmatics:
            guard config.speechModelID == "enhanced" else { return nil }
            return SpeechmaticsStreaming(config: config, hints: hints)
        case .elevenLabs:
            // The medical model has no real-time counterpart.
            guard config.speechModelID == "scribe_v2" else { return nil }
            return ElevenLabsStreaming(hints: hints, engineID: config.engineID)
        case .openAI:
            guard ["gpt-transcribe", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"].contains(config.speechModelID) else { return nil }
            return OpenAIStreaming(hints: hints, engineID: config.engineID)
        case .mistral:
            guard config.speechModelID == "voxtral-mini-latest" else { return nil }
            return MistralStreaming(hints: hints, engineID: config.engineID)
        case .gemini:
            guard config.speechModelID == "gemini-3.5-transcribe" else { return nil }
            return GeminiStreaming(hints: hints, engineID: config.engineID)
        default:
            return nil
        }
    }

    /// Whether this cloud model shows live text.
    public static func supports(_ config: ASRConfig) -> Bool {
        provider(for: config, hints: hints(for: config)) != nil
    }

    /// Whether its live text is the batch model's own output, so it becomes the
    /// transcript; otherwise the recording is transcribed again after release.
    /// Judged with the language the recording would resolve, since some
    /// providers match only with an explicit language.
    public static func becomesTranscript(_ config: ASRConfig) -> Bool {
        provider(for: config, hints: hints(for: config))?.matchesBatchModel == true
    }

    private static func hints(for config: ASRConfig) -> TranscriptionHints {
        TranscriptionHints(language: (try? SpeechLanguagePolicy.resolve(config))?.language)
    }
}

/// A live-text session that could not start; it reports why once and shows nothing.
final class UnavailableLiveSession: SpeechPreviewSession, Sendable {
    init(issue: String, onIssue: @escaping @Sendable (String) -> Void) { onIssue(issue) }
    func append(_ samples: [Float]) {}
    func cancel() {}
}
