import AVFoundation
import Foundation
import Speech
import Synchronization

public protocol SpeechPreviewSession: Sendable {
    func append(_ samples: [Float])
    func cancel()
}

/// Optional on-device feedback. This session never supplies the final transcript.
public enum SpeechPreview {
    public static func start(
        locale: String,
        onText: @escaping @Sendable (String) -> Void,
        onIssue: @escaping @Sendable (String) -> Void
    ) -> any SpeechPreviewSession {
        PreviewSession(locale: locale, onText: onText, onIssue: onIssue)
    }

    public static func unavailableReason(locale: String) async -> String? {
        guard #available(macOS 26, *) else { return String(localized: "Live preview requires macOS 26 or later.", bundle: .module) }
        do {
            _ = try await installedTranscriber(locale: locale)
            return nil
        } catch { return error.localizedDescription }
    }

    @available(macOS 26, *)
    private static func installedTranscriber(locale: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw PreviewIssue(String(localized: "Apple Speech live preview is unavailable on this Mac. Turn off Live Preview in Settings.", bundle: .module))
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            throw PreviewIssue(String(localized: "Apple Speech does not support this preview language. Choose another language in Settings.", bundle: .module))
        }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw PreviewIssue(String(localized: "Install Apple Speech for \(supported.identifier) from Models, then start another recording.", bundle: .module))
        }
        try Task.checkCancellation()
        return transcriber
    }

    @available(macOS 26, *)
    fileprivate static func run(locale: String, control: SpeechPreviewControl) async {
        defer { control.cancel() }
        do {
            let transcriber = try await installedTranscriber(locale: locale)
            guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw PreviewIssue(String(localized: "Apple Speech has no available audio format. Reload its language in Models and retry.", bundle: .module))
            }
            try Task.checkCancellation()
            let converter = try SpeechPreviewConverter(targetFormat: targetFormat)
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .utility, modelRetention: .whileInUse))
            // Unfolding pulls one chunk at a time. There is no second, unbounded audio buffer.
            let input = AsyncThrowingStream<AnalyzerInput, Error>(unfolding: {
                try await converter.nextInput(from: control.audio)
            })
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    do {
                        for try await result in transcriber.results {
                            guard !Task.isCancelled else { break }
                            control.publish(String(result.text.characters), startTime: result.range.start.seconds)
                        }
                        if !Task.isCancelled, control.isActive {
                            control.fail(String(localized: "Live preview stopped. Start another recording to retry; final transcription is still available.", bundle: .module))
                        }
                    } catch {
                        if !Task.isCancelled { control.fail(String(localized: "Live preview stopped: \(error.localizedDescription) Start another recording to retry.", bundle: .module)) }
                    }
                }
                group.addTask {
                    do {
                        _ = try await analyzer.analyzeSequence(input)
                    } catch {
                        if !Task.isCancelled { control.fail(String(localized: "Live preview stopped: \(error.localizedDescription) Start another recording to retry.", bundle: .module)) }
                    }
                    // Finishing the input stream alone does not finish a SpeechAnalyzer.
                    // This cleanup stays off the caller's recording/final-transcription path.
                    await analyzer.cancelAndFinishNow()
                }
                await group.waitForAll()
            }
        } catch {
            if !Task.isCancelled { control.fail(error.localizedDescription) }
        }
    }
}

private struct PreviewIssue: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private final class PreviewSession: SpeechPreviewSession, Sendable {
    private let control: SpeechPreviewControl

    init(locale: String, onText: @escaping @Sendable (String) -> Void, onIssue: @escaping @Sendable (String) -> Void) {
        let control = SpeechPreviewControl(onText: onText, onIssue: onIssue)
        self.control = control
        // The worker retains control, not the session, so releasing a session cancels it.
        let worker = Task(priority: .utility) {
            if #available(macOS 26, *) {
                await SpeechPreview.run(locale: locale, control: control)
            } else {
                control.fail(String(localized: "Live preview requires macOS 26 or later.", bundle: .module))
            }
        }
        control.setWorker(worker)
    }

    func append(_ samples: [Float]) { control.append(samples) }
    func cancel() { control.cancel() }
    deinit { control.cancel() }
}

/// Synchronous lifetime gate shared by the audio callback and the asynchronous worker.
/// Callback delivery is locked too: once cancel returns, no later callback can begin.
final class SpeechPreviewControl: Sendable {
    let audio: SpeechPreviewAudioQueue
    /// onText/onIssue run while this is held, so nothing is delivered after cancel
    /// returns. Recursive so such a callback can call back into this control.
    private let lock = NSRecursiveLock()
    // Guarded by `lock`. Mutex cannot be re-entered, so these four fields are the
    // only unchecked state; every other stored property is checked Sendable.
    nonisolated(unsafe) private var active = true
    nonisolated(unsafe) private var worker: Task<Void, Never>?
    nonisolated(unsafe) private var latestStart = -Double.infinity
    nonisolated(unsafe) private var latestText = ""
    private let onText: @Sendable (String) -> Void
    private let onIssue: @Sendable (String) -> Void

    init(maximumSamples: Int = 32_000, onText: @escaping @Sendable (String) -> Void,
         onIssue: @escaping @Sendable (String) -> Void) {
        audio = SpeechPreviewAudioQueue(maximumSamples: maximumSamples)
        self.onText = onText
        self.onIssue = onIssue
    }

    var isActive: Bool { lock.withLock { active } }

    func setWorker(_ task: Task<Void, Never>) {
        let accepted = lock.withLock {
            guard active else { return false }
            worker = task
            return true
        }
        if !accepted { task.cancel() }
    }

    func append(_ samples: [Float]) {
        switch audio.append(samples) {
        case .accepted, .stopped: break
        case .overflow:
            fail(String(localized: "Live preview could not keep up. Start another recording to retry, or turn off Live Preview. Final transcription is unaffected.", bundle: .module))
        case .invalid:
            fail(String(localized: "Live preview received invalid audio. Check the selected microphone and start another recording.", bundle: .module))
        }
    }

    func publish(_ text: String, startTime: Double) {
        lock.withLock {
            guard active else { return }
            // Volatile revisions replace the current phrase; older finalized phrases
            // must not replace a newer phrase that is already visible.
            if startTime.isFinite {
                guard startTime >= latestStart else { return }
                latestStart = startTime
            }
            let tail = String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500))
            guard !tail.isEmpty, tail != latestText else { return }
            latestText = tail
            onText(tail)
        }
    }

    func fail(_ issue: String) { stop(issue: issue) }
    func cancel() { stop(issue: nil) }

    private func stop(issue: String?) {
        let task = lock.withLock { () -> Task<Void, Never>? in
            guard active else { return nil }
            active = false
            let task = worker
            worker = nil
            latestText = ""
            if let issue { onIssue(issue) }
            return task
        }
        audio.cancel()
        task?.cancel()
    }
}

/// A single-consumer queue bounded by audio duration, not by the number of chunks.
/// Overflow drops the entire preview session instead of creating gaps in its audio.
final class SpeechPreviewAudioQueue: Sendable {
    enum AppendResult: Equatable, Sendable { case accepted, stopped, overflow, invalid }
    private struct State {
        var chunks: [[Float]] = []
        var sampleCount = 0
        var stopped = false
        var waiter: CheckedContinuation<[Float]?, Never>?
    }
    private let state = Mutex(State())
    private let maximumSamples: Int

    init(maximumSamples: Int = 32_000) { self.maximumSamples = max(1, maximumSamples) }
    var pendingSampleCount: Int { state.withLock { $0.sampleCount } }

    func append(_ samples: [Float]) -> AppendResult {
        let maximumSamples = maximumSamples
        let (result, delivery) = state.withLock { state -> (AppendResult, CheckedContinuation<[Float]?, Never>?) in
            guard !state.stopped else { return (.stopped, nil) }
            guard !samples.isEmpty else { return (.accepted, nil) }
            let invalid = samples.count <= maximumSamples && !samples.allSatisfy(\.isFinite)
            if samples.count > maximumSamples - state.sampleCount || invalid {
                state.stopped = true
                state.chunks.removeAll()
                state.sampleCount = 0
                let delivery = state.waiter
                state.waiter = nil
                return (invalid ? .invalid : .overflow, delivery)
            }
            if let waiter = state.waiter {
                state.waiter = nil
                return (.accepted, waiter)
            }
            state.chunks.append(samples)
            state.sampleCount += samples.count
            return (.accepted, nil)
        }
        delivery?.resume(returning: result == .accepted ? samples : nil)
        return result
    }

    func next() async -> [Float]? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate = state.withLock { state -> (ready: Bool, samples: [Float]?) in
                    if state.stopped { return (true, nil) }
                    if !state.chunks.isEmpty {
                        let chunk = state.chunks.removeFirst()
                        state.sampleCount -= chunk.count
                        return (true, chunk)
                    }
                    precondition(state.waiter == nil, "Speech preview has one audio consumer")
                    state.waiter = continuation
                    return (false, nil)
                }
                if immediate.ready { continuation.resume(returning: immediate.samples) }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        let pending = state.withLock { state -> CheckedContinuation<[Float]?, Never>? in
            state.stopped = true
            state.chunks.removeAll()
            state.sampleCount = 0
            let pending = state.waiter
            state.waiter = nil
            return pending
        }
        pending?.resume(returning: nil)
    }
}

@available(macOS 26, *)
private actor SpeechPreviewConverter {
    private let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter?

    init(targetFormat: AVAudioFormat) throws {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false) else {
            throw PreviewIssue(String(localized: "Live preview could not prepare audio. Start another recording to retry.", bundle: .module))
        }
        sourceFormat = source
        self.targetFormat = targetFormat
        converter = source == targetFormat ? nil : AVAudioConverter(from: source, to: targetFormat)
        if source != targetFormat, converter == nil {
            throw PreviewIssue(String(localized: "Live preview could not convert audio. Reload Apple Speech in Models and retry.", bundle: .module))
        }
    }

    func nextInput(from queue: SpeechPreviewAudioQueue) async throws -> AnalyzerInput? {
        while let samples = await queue.next() {
            try Task.checkCancellation()
            guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = source.floatChannelData?[0] else {
                throw PreviewIssue(String(localized: "Live preview could not allocate an audio buffer. Start another recording to retry.", bundle: .module))
            }
            source.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { values in channel.update(from: values.baseAddress!, count: samples.count) }
            guard let converter else { return AnalyzerInput(buffer: source) }
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(samples.count) * ratio)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw PreviewIssue(String(localized: "Live preview could not allocate an audio buffer. Start another recording to retry.", bundle: .module))
            }
            var consumed = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if consumed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                inputStatus.pointee = .haveData
                return source
            }
            if let error { throw error }
            guard status != .error else { throw PreviewIssue(String(localized: "Live preview audio conversion failed. Start another recording to retry.", bundle: .module)) }
            if output.frameLength > 0 { return AnalyzerInput(buffer: output) }
        }
        return nil
    }
}
