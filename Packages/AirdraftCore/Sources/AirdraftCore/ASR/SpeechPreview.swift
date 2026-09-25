import AVFoundation
import Foundation
import Speech

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
        guard #available(macOS 26, *) else { return "Live preview requires macOS 26 or later." }
        do {
            _ = try await installedTranscriber(locale: locale)
            return nil
        } catch { return error.localizedDescription }
    }

    @available(macOS 26, *)
    private static func installedTranscriber(locale: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw PreviewIssue("Apple Speech live preview is unavailable on this Mac. Turn off Live Preview in Settings.")
        }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) else {
            throw PreviewIssue("Apple Speech does not support this preview language. Choose another language in Settings.")
        }
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw PreviewIssue("Install Apple Speech for \(supported.identifier) from Models, then start another recording.")
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
                throw PreviewIssue("Apple Speech has no available audio format. Reload its language in Models and retry.")
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
                            control.fail("Live preview stopped. Start another recording to retry; final transcription is still available.")
                        }
                    } catch {
                        if !Task.isCancelled { control.fail("Live preview stopped: \(error.localizedDescription) Start another recording to retry.") }
                    }
                }
                group.addTask {
                    do {
                        _ = try await analyzer.analyzeSequence(input)
                    } catch {
                        if !Task.isCancelled { control.fail("Live preview stopped: \(error.localizedDescription) Start another recording to retry.") }
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
                control.fail("Live preview requires macOS 26 or later.")
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
final class SpeechPreviewControl: @unchecked Sendable {
    let audio: SpeechPreviewAudioQueue
    private let lock = NSRecursiveLock()
    private var active = true
    private var worker: Task<Void, Never>?
    private var latestStart = -Double.infinity
    private var latestText = ""
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
            fail("Live preview could not keep up. Start another recording to retry, or turn off Live Preview. Final transcription is unaffected.")
        case .invalid:
            fail("Live preview received invalid audio. Check the selected microphone and start another recording.")
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
final class SpeechPreviewAudioQueue: @unchecked Sendable {
    enum AppendResult: Equatable { case accepted, stopped, overflow, invalid }
    private let lock = NSLock()
    private let maximumSamples: Int
    private var chunks: [[Float]] = []
    private var sampleCount = 0
    private var stopped = false
    private var waiter: CheckedContinuation<[Float]?, Never>?

    init(maximumSamples: Int = 32_000) { self.maximumSamples = max(1, maximumSamples) }
    var pendingSampleCount: Int { lock.withLock { sampleCount } }

    func append(_ samples: [Float]) -> AppendResult {
        var delivery: CheckedContinuation<[Float]?, Never>?
        let result = lock.withLock { () -> AppendResult in
            guard !stopped else { return .stopped }
            guard !samples.isEmpty else { return .accepted }
            let invalid = samples.count <= maximumSamples && !samples.allSatisfy(\.isFinite)
            if samples.count > maximumSamples - sampleCount || invalid {
                stopped = true
                chunks.removeAll()
                sampleCount = 0
                delivery = waiter
                waiter = nil
                return invalid ? .invalid : .overflow
            }
            if let waiter {
                delivery = waiter
                self.waiter = nil
            } else {
                chunks.append(samples)
                sampleCount += samples.count
            }
            return .accepted
        }
        delivery?.resume(returning: result == .accepted ? samples : nil)
        return result
    }

    func next() async -> [Float]? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate = lock.withLock { () -> (ready: Bool, samples: [Float]?) in
                    if stopped { return (true, nil) }
                    if !chunks.isEmpty {
                        let chunk = chunks.removeFirst()
                        sampleCount -= chunk.count
                        return (true, chunk)
                    }
                    precondition(waiter == nil, "Speech preview has one audio consumer")
                    waiter = continuation
                    return (false, nil)
                }
                if immediate.ready { continuation.resume(returning: immediate.samples) }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        let pending = lock.withLock { () -> CheckedContinuation<[Float]?, Never>? in
            stopped = true
            chunks.removeAll()
            sampleCount = 0
            let pending = waiter
            waiter = nil
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
            throw PreviewIssue("Live preview could not prepare audio. Start another recording to retry.")
        }
        sourceFormat = source
        self.targetFormat = targetFormat
        converter = source == targetFormat ? nil : AVAudioConverter(from: source, to: targetFormat)
        if source != targetFormat, converter == nil {
            throw PreviewIssue("Live preview could not convert audio. Reload Apple Speech in Models and retry.")
        }
    }

    func nextInput(from queue: SpeechPreviewAudioQueue) async throws -> AnalyzerInput? {
        while let samples = await queue.next() {
            try Task.checkCancellation()
            guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = source.floatChannelData?[0] else {
                throw PreviewIssue("Live preview could not allocate an audio buffer. Start another recording to retry.")
            }
            source.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { values in channel.update(from: values.baseAddress!, count: samples.count) }
            guard let converter else { return AnalyzerInput(buffer: source) }
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(ceil(Double(samples.count) * ratio)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw PreviewIssue("Live preview could not allocate an audio buffer. Start another recording to retry.")
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
            guard status != .error else { throw PreviewIssue("Live preview audio conversion failed. Start another recording to retry.") }
            if output.frameLength > 0 { return AnalyzerInput(buffer: output) }
        }
        return nil
    }
}
