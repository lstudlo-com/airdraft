import AVFoundation
import Foundation
import Speech
import Synchronization

extension SpeechPreview {
    /// AD-123: Apple Speech live text for a recording whose model is Apple Speech
    /// in the same locale. It analyzes with final transcription's options plus
    /// volatile reporting, so its finalized results are the model's own output and
    /// become the transcript at release.
    public static func startTranscript(
        locale: String,
        onText: @escaping @Sendable (String) -> Void,
        onIssue: @escaping @Sendable (String) -> Void
    ) -> any SpeechPreviewSession {
        AppleLiveTranscriptSession(locale: locale, onText: onText, onIssue: onIssue)
    }
}

/// Keeps every sample until release (a recording is bounded by its 600-second
/// limit), shows finalized plus volatile text, and finalizes through the whole
/// capture in `finishTranscript`. No callback after `cancel()` or finishing begins.
final class AppleLiveTranscriptSession: LiveTranscriptSession, Sendable {
    private struct State {
        var appended = 0
        var finalized = ""
        var volatile = ""
        var published = ""
    }
    private let locale: String
    private let audio = SpeechPreviewAudioQueue(maximumSamples: Int(SpeechInputLimits.recordingSecondsRange.upperBound + 5) * 16_000)
    private let state = Mutex(State())
    private let onText: @Sendable (String) -> Void
    private let onIssue: @Sendable (String) -> Void
    /// Held while delivering callbacks and while stopping. Recursive so a callback can cancel.
    private let callbackLock = NSRecursiveLock()
    // Guarded by `callbackLock`.
    nonisolated(unsafe) private var stopped = false
    nonisolated(unsafe) private var worker: Task<Transcript?, Never>?

    var reusesForTranscript: Bool { true }

    init(locale: String, onText: @escaping @Sendable (String) -> Void, onIssue: @escaping @Sendable (String) -> Void) {
        self.locale = locale
        self.onText = onText
        self.onIssue = onIssue
        let task = Task<Transcript?, Never>(priority: .userInitiated) { [weak self] in
            guard let self else { return nil }
            return await self.run()
        }
        callbackLock.withLock {
            if stopped { task.cancel() } else { worker = task }
        }
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        switch audio.append(samples) {
        case .accepted: state.withLock { $0.appended += samples.count }
        case .stopped: break
        case .overflow, .invalid:
            fail(String(localized: "Live preview received invalid audio. Check the selected microphone and start another recording.", bundle: .module))
        }
    }

    func cancel() {
        let task = callbackLock.withLock { () -> Task<Transcript?, Never>? in
            stopped = true
            defer { worker = nil }
            return worker
        }
        audio.cancel()
        task?.cancel()
    }

    private func fail(_ issue: String) {
        let task = callbackLock.withLock { () -> Task<Transcript?, Never>? in
            guard !stopped else { return nil }
            stopped = true
            onIssue(issue)
            defer { worker = nil }
            return worker
        }
        audio.cancel()
        task?.cancel()
    }

    func finishTranscript(capture: [Float]) async -> Transcript? {
        let task = callbackLock.withLock { () -> Task<Transcript?, Never>?? in
            guard !stopped else { return nil }
            stopped = true
            defer { worker = nil }
            return .some(worker)
        }
        guard let task, let task else { return nil }
        let appended = state.withLock { $0.appended }
        // Audio still in flight when the recorder stopped is taken from the capture itself.
        guard appended <= capture.count else {
            audio.cancel()
            task.cancel()
            return nil
        }
        if capture.count > appended, audio.append(Array(capture[appended...])) != .accepted {
            audio.cancel()
            task.cancel()
            return nil
        }
        audio.finish()
        let started = ProcessInfo.processInfo.systemUptime
        var transcript = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        transcript?.latencyMs = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        return transcript
    }

    private func publish(_ result: String, isFinal: Bool) {
        callbackLock.withLock {
            guard !stopped else {
                // Finishing still collects finalized results; nothing is shown.
                if isFinal { state.withLock { $0.finalized += result } }
                return
            }
            let display = state.withLock { state -> String? in
                if isFinal {
                    state.finalized += result
                    state.volatile = ""
                } else {
                    state.volatile = result
                }
                let shown = ModelSpeechPreview.tail((state.finalized + state.volatile).trimmingCharacters(in: .whitespacesAndNewlines),
                                                    maximum: 500)
                guard !shown.isEmpty, shown != state.published else { return nil }
                state.published = shown
                return shown
            }
            if let display { onText(display) }
        }
    }

    /// Returns the finalized transcript once input ends, or nil on failure or cancellation.
    private func run() async -> Transcript? {
        guard #available(macOS 26, *) else {
            fail(String(localized: "Live preview requires macOS 26 or later.", bundle: .module))
            return nil
        }
        do {
            guard SpeechTranscriber.isAvailable,
                  let supported = await AppleSpeechTranscriber.resolvedLocale(for: locale) else {
                throw PreviewIssue(String(localized: "Apple Speech does not support this preview language. Choose another language in Settings.", bundle: .module))
            }
            // Final transcription's options (AppleSpeechTranscriber uses `.transcription`),
            // reporting volatile results as well; never `fastResults`.
            let preset = SpeechTranscriber.Preset.transcription
            let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: preset.transcriptionOptions,
                                                reportingOptions: preset.reportingOptions.union([.volatileResults]),
                                                attributeOptions: preset.attributeOptions)
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw PreviewIssue(String(localized: "Install Apple Speech for \(supported.identifier) from Models, then start another recording.", bundle: .module))
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw PreviewIssue(String(localized: "Apple Speech has no available audio format. Reload its language in Models and retry.", bundle: .module))
            }
            try Task.checkCancellation()
            let converter = try SpeechPreviewConverter(targetFormat: format)
            let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            let audio = self.audio
            let input = AsyncThrowingStream<AnalyzerInput, Error>(unfolding: { try await converter.nextInput(from: audio) })
            let collector = Task<Void, Error> {
                for try await result in transcriber.results {
                    self.publish(String(result.text.characters), isFinal: result.isFinal)
                }
            }
            defer { collector.cancel() }
            do {
                _ = try await analyzer.analyzeSequence(input)
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                try await collector.value
                try Task.checkCancellation()
            } catch {
                collector.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
            let text = state.withLock { $0.finalized }.trimmingCharacters(in: .whitespacesAndNewlines)
            return Transcript(text: text, language: supported.identifier, engine: "apple-speech:\(locale)", latencyMs: 0)
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                fail(String(localized: "Live preview stopped: \(error.localizedDescription) Start another recording to retry.", bundle: .module))
            }
            return nil
        }
    }
}
