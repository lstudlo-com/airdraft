import Foundation
import Synchronization

/// Where live preview text comes from. Neither source supplies the final transcript.
public enum LivePreviewSource: String, Codable, CaseIterable, Sendable, Identifiable {
    /// A separate Apple Speech analyzer (macOS 26+).
    case appleSpeech
    /// Bounded incremental decodes with the recording's own loaded local model.
    case speechModel
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .speechModel: return String(localized: "Selected speech model", bundle: .module)
        }
    }
}

/// Cadence and memory bounds for model-driven live text (AD-084).
public struct ModelPreviewPolicy: Sendable, Equatable {
    /// Minimum time from the end of one decode to the start of the next.
    public var minimumInterval: Double
    /// New audio required before another provisional decode.
    public var minimumNewAudioSeconds: Double
    /// The provisional window: once the uncommitted audio reaches this length,
    /// its head is decoded once more, committed, and removed from the window.
    public var windowSeconds: Double
    /// A commit cuts at the quietest 100 ms frame within this span before the window end.
    public var commitSearchSeconds: Double
    /// A decode slower than this stops the preview for the session.
    public var slowDecodeSeconds: Double
    /// Audio kept while decodes are skipped (engine busy); older audio is dropped.
    public var bufferSeconds: Double
    /// Displayed text is the tail of committed plus provisional text.
    public var maximumCharacters: Int
    /// Wait between checks while too little new audio has arrived.
    public var pollSeconds: Double

    public init(minimumInterval: Double = 1.0, minimumNewAudioSeconds: Double = 0.5, windowSeconds: Double = 10,
                commitSearchSeconds: Double = 3, slowDecodeSeconds: Double = 3, bufferSeconds: Double = 20,
                maximumCharacters: Int = 500, pollSeconds: Double = 0.1) {
        self.minimumInterval = minimumInterval
        self.minimumNewAudioSeconds = minimumNewAudioSeconds
        self.windowSeconds = windowSeconds
        self.commitSearchSeconds = min(commitSearchSeconds, windowSeconds)
        self.slowDecodeSeconds = slowDecodeSeconds
        self.bufferSeconds = max(bufferSeconds, windowSeconds)
        self.maximumCharacters = maximumCharacters
        self.pollSeconds = pollSeconds
    }

    public static let standard = ModelPreviewPolicy()
    /// Meetings show a longer display-only tail in their recording card.
    public static let meeting = ModelPreviewPolicy(maximumCharacters: 1_500)
}

/// Display-only decode of one window. Returns nil when the engine is busy or not
/// loaded, so this tick is dropped; it never loads, downloads or waits for a lease.
public typealias ModelPreviewDecoder = @Sendable ([Float]) async throws -> String?

/// What a recording captured for model preview: the same speech config and hints
/// its final transcription uses, so preview never rebuilds the native decoder.
public struct ModelPreviewRequest: Sendable {
    public let asr: ASRConfig
    public let hints: TranscriptionHints
    public init(asr: ASRConfig, hints: TranscriptionHints) {
        self.asr = asr
        self.hints = hints
    }
}

public enum ModelSpeechPreview {
    /// Engines whose single-window decode is fast and stateless across calls:
    /// non-autoregressive sherpa-onnx offline decoders. Autoregressive or GPU
    /// models (Whisper, Qwen3-ASR, Cohere, FireRedASR2, GGUF, Core ML) and every
    /// cloud provider stay unavailable.
    /// Whether choosing this model shows live text with the Selected speech
    /// model source: its own fast decoder, or Apple Speech's analyzer (AD-108).
    public static func showsLiveText(_ asr: ASRConfig) -> Bool {
        supports(asr) || appleSpeechLocale(for: asr) != nil
    }

    public static func supports(_ asr: ASRConfig) -> Bool {
        switch asr.kind {
        case .parakeet, .senseVoice, .senseVoiceMultilingual, .orukeet: return true
        default: return false
        }
    }

    /// When the selected model is Apple Speech itself, the model source runs the
    /// Apple Speech preview analyzer in that model's own locale: the same engine
    /// and language, so no other model is substituted. Nil for every other model.
    public static func appleSpeechLocale(for asr: ASRConfig) -> String? {
        asr.kind == .apple ? asr.effectiveAppleLocale : nil
    }

    /// Why the selected model cannot show live text, or nil when it can.
    /// Stats the model folder: never call it from a view body (use the
    /// `installed:` form with a fact measured off the main actor).
    public static func unavailableReason(for asr: ASRConfig) -> String? {
        unavailableReason(for: asr, installed: supports(asr) && LocalModels.isInstalled(asr))
    }

    /// The same reason from an installed state already measured elsewhere;
    /// reads no files.
    public static func unavailableReason(for asr: ASRConfig, installed: Bool) -> String? {
        if appleSpeechLocale(for: asr) != nil { return nil }
        guard supports(asr) else {
            return String(localized: "Live text is unavailable for \(asr.displayName). Use Apple Speech for preview, or a model marked Live text in Models.", bundle: .module)
        }
        guard installed else {
            return String(localized: "Install \(asr.displayName) in Models to see live text.", bundle: .module)
        }
        return nil
    }

    /// The recording window's one-line notice for a model without live text.
    /// The HUD shows it briefly instead of opening the live-text window. It
    /// names the model without its runtime so it stays short. Stats the model
    /// folder, like `unavailableReason(for:)`.
    public static func recordingNotice(for asr: ASRConfig) -> String? {
        guard unavailableReason(for: asr) != nil else { return nil }
        guard supports(asr) else {
            return String(localized: "\(asr.modelDisplayName) doesn’t support live text", bundle: .module)
        }
        return String(localized: "Install \(asr.modelDisplayName) in Models to see live text.", bundle: .module)
    }

    public static func start(policy: ModelPreviewPolicy = .standard,
                             decode: @escaping ModelPreviewDecoder,
                             onText: @escaping @Sendable (String) -> Void,
                             onIssue: @escaping @Sendable (String) -> Void,
                             now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                             sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) })
        -> ModelPreviewSession {
        ModelPreviewSession(policy: policy, decode: decode, onText: onText, onIssue: onIssue, now: now, sleep: sleep)
    }

    /// The production decoder: the factory's display-only lease path.
    public static func decoder(factory: EngineFactory, request: ModelPreviewRequest) -> ModelPreviewDecoder {
        { samples in try await factory.transcribePreview(samples, hints: request.hints, config: request.asr) }
    }

    /// Meetings: loads the installed model through the factory lease (never a
    /// download) and starts a display-only session. Meeting capture excludes
    /// dictation and media work, so this load cannot displace a recording's model.
    public static func startForMeeting(asr: ASRConfig, hints: TranscriptionHints, factory: EngineFactory,
                                       onText: @escaping @Sendable (String) -> Void,
                                       onIssue: @escaping @Sendable (String) -> Void) async -> ModelPreviewSession? {
        if let reason = unavailableReason(for: asr) {
            onIssue(reason)
            return nil
        }
        SherpaTranscriber.anticipate(hints)
        do {
            try await factory.prepare(asr)
        } catch {
            if !(error is CancellationError) {
                onIssue(String(localized: "Live transcript unavailable: \(error.localizedDescription)", bundle: .module))
            }
            return nil
        }
        guard !Task.isCancelled else { return nil }
        return start(policy: .meeting, decode: decoder(factory: factory, request: ModelPreviewRequest(asr: asr, hints: hints)),
                     onText: onText, onIssue: onIssue)
    }

    /// The last `maximum` characters, starting at a word boundary when one is
    /// close, so the bounded display does not open with a partial word.
    static func tail(_ text: String, maximum: Int) -> String {
        guard text.count > maximum else { return text }
        let suffix = text.suffix(maximum)
        if let space = suffix.prefix(24).firstIndex(where: \.isWhitespace) {
            return String(suffix[suffix.index(after: space)...])
        }
        return String(suffix)
    }

    /// Joins committed and provisional text without a space next to CJK text.
    static func join(_ head: String, _ tail: String) -> String {
        let head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = head.unicodeScalars.last else { return tail }
        guard let first = tail.unicodeScalars.first else { return head }
        if isUnspaced(last) || isUnspaced(first) || CharacterSet.punctuationCharacters.contains(first) { return head + tail }
        return head + " " + tail
    }

    private static func isUnspaced(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF: return true
        default: return false
        }
    }

    /// The sample index of the quietest 100 ms frame's centre inside `range`.
    static func quietestCut(_ samples: [Float], in range: Range<Int>) -> Int {
        let frame = 1_600
        let lower = max(0, range.lowerBound)
        let upper = min(samples.count, range.upperBound)
        guard upper - lower >= frame else { return upper }
        var best = upper
        var bestEnergy = Float.infinity
        var start = lower
        while start + frame <= upper {
            var energy: Float = 0
            for index in start..<(start + frame) { energy += samples[index] * samples[index] }
            // Later frames win ties so committed text covers as much speech as possible.
            if energy <= bestEnergy {
                bestEnergy = energy
                best = start + frame / 2
            }
            start += frame / 2
        }
        return best
    }
}

/// Model-driven live preview: one decode in flight, a cadence floor, a bounded
/// window plus committed prefix, and no callback after `cancel()` returns.
public final class ModelPreviewSession: SpeechPreviewSession, Sendable {
    public struct Metrics: Sendable, Equatable {
        public var decodes = 0
        public var commits = 0
        public var skippedBusy = 0
        /// Decodes cancelled because final inference or a load needed the lease.
        public var preempted = 0
        public var droppedSamples = 0
        public var decodeSeconds: [Double] = []
        /// Start-to-start gaps between successive decodes.
        public var intervals: [Double] = []
        public var longestWindowSamples = 0
    }

    private struct State {
        var active = true
        /// Uncommitted audio. `segmentStart` is the absolute index of its first sample.
        var segment: [Float] = []
        var segmentStart = 0
        /// Absolute end index of the audio the last provisional decode covered.
        var decodedEnd = 0
        var committed = ""
        var provisional = ""
        var published = ""
        var metrics = Metrics()
    }

    private let policy: ModelPreviewPolicy
    private let decode: ModelPreviewDecoder
    private let onText: @Sendable (String) -> Void
    private let onIssue: @Sendable (String) -> Void
    private let now: @Sendable () -> TimeInterval
    private let sleep: @Sendable (Double) async throws -> Void
    private let state = Mutex(State())
    /// Held while delivering callbacks and while stopping, so nothing is
    /// delivered after cancel returns. Recursive so a callback can cancel.
    private let callbackLock = NSRecursiveLock()
    /// Guarded by `callbackLock`.
    nonisolated(unsafe) private var worker: Task<Void, Never>?
    nonisolated(unsafe) private var stopped = false

    init(policy: ModelPreviewPolicy, decode: @escaping ModelPreviewDecoder,
         onText: @escaping @Sendable (String) -> Void, onIssue: @escaping @Sendable (String) -> Void,
         now: @escaping @Sendable () -> TimeInterval, sleep: @escaping @Sendable (Double) async throws -> Void) {
        self.policy = policy
        self.decode = decode
        self.onText = onText
        self.onIssue = onIssue
        self.now = now
        self.sleep = sleep
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.run()
        }
        callbackLock.withLock {
            if stopped { task.cancel() } else { worker = task }
        }
    }

    public var metrics: Metrics { state.withLock { $0.metrics } }
    public var isActive: Bool { state.withLock { $0.active } }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        guard samples.allSatisfy(\.isFinite) else {
            fail(String(localized: "Live preview received invalid audio. Check the selected microphone and start another recording.", bundle: .module))
            return
        }
        let limit = Int(policy.bufferSeconds * 16_000)
        let keep = Int(policy.windowSeconds * 16_000)
        state.withLock { state in
            guard state.active else { return }
            state.segment.append(contentsOf: samples)
            if state.segment.count > limit {
                // Decodes were skipped for a long time. Drop the oldest audio in
                // one block instead of growing without bound.
                let drop = state.segment.count - keep
                state.segment.removeFirst(drop)
                state.segmentStart += drop
                state.decodedEnd = max(state.decodedEnd, state.segmentStart)
                state.metrics.droppedSamples += drop
            }
        }
    }

    public func cancel() { stop(issue: nil) }

    func fail(_ issue: String) { stop(issue: issue) }

    private func stop(issue: String?) {
        let task = callbackLock.withLock { () -> Task<Void, Never>? in
            guard !stopped else { return nil }
            stopped = true
            state.withLock { state in
                state.active = false
                state.segment = []
                state.committed = ""
                state.provisional = ""
            }
            if let issue { onIssue(issue) }
            let task = worker
            worker = nil
            return task
        }
        task?.cancel()
    }

    private enum Job {
        case provisional(samples: [Float], end: Int)
        case commit(samples: [Float], end: Int)
        var samples: [Float] {
            switch self { case .provisional(let samples, _), .commit(let samples, _): return samples }
        }
    }

    private func nextJob() -> Job? {
        let window = Int(policy.windowSeconds * 16_000)
        let search = Int(policy.commitSearchSeconds * 16_000)
        let minimumNew = Int(policy.minimumNewAudioSeconds * 16_000)
        return state.withLock { state -> Job? in
            guard state.active else { return nil }
            let end = state.segmentStart + state.segment.count
            if state.segment.count >= window {
                let cut = ModelSpeechPreview.quietestCut(state.segment, in: (window - search)..<window)
                return .commit(samples: Array(state.segment.prefix(cut)), end: state.segmentStart + cut)
            }
            guard end - state.decodedEnd >= minimumNew else { return nil }
            return .provisional(samples: state.segment, end: end)
        }
    }

    private func run() async {
        var lastEnd = -Double.infinity
        var lastStart: Double?
        var interval = policy.minimumInterval
        while !Task.isCancelled, isActive {
            let wait = lastEnd + interval - now()
            do { try await sleep(wait > 0 ? wait : policy.pollSeconds) } catch { return }
            guard !Task.isCancelled, isActive else { return }
            guard let job = nextJob() else { continue }
            let started = now()
            let text: String?
            do {
                text = try await decode(job.samples)
            } catch is CancellationError {
                // Final inference preempted this display-only decode; try again later.
                lastEnd = now()
                state.withLock { $0.metrics.preempted += 1 }
                continue
            } catch {
                guard !Task.isCancelled, isActive else { return }
                fail(String(localized: "Live preview stopped: \(error.localizedDescription) Final transcription is unaffected.", bundle: .module))
                return
            }
            let finished = now()
            lastEnd = finished
            guard !Task.isCancelled, isActive else { return }
            let elapsed = finished - started
            let gap = lastStart.map { started - $0 }
            lastStart = started
            guard let text else {
                state.withLock { $0.metrics.skippedBusy += 1 }
                continue
            }
            if elapsed > policy.slowDecodeSeconds {
                fail(String(localized: "Live preview stopped because the speech model was too slow. Final transcription is unaffected.", bundle: .module))
                return
            }
            // The cadence adapts to the decode cost so preview never takes more
            // than about a third of the engine's time.
            interval = max(policy.minimumInterval, elapsed * 2)
            apply(job, text: text, elapsed: elapsed, gap: gap)
        }
    }

    private func apply(_ job: Job, text: String, elapsed: Double, gap: Double?) {
        let maximum = policy.maximumCharacters
        callbackLock.withLock {
            guard !stopped else { return }
            let display = state.withLock { state -> String? in
                guard state.active else { return nil }
                state.metrics.decodes += 1
                state.metrics.decodeSeconds.append(elapsed)
                if let gap { state.metrics.intervals.append(gap) }
                state.metrics.longestWindowSamples = max(state.metrics.longestWindowSamples, job.samples.count)
                switch job {
                case .commit(_, let end):
                    state.metrics.commits += 1
                    state.committed = String(ModelSpeechPreview.join(state.committed, text).suffix(maximum * 4))
                    let drop = min(state.segment.count, max(0, end - state.segmentStart))
                    state.segment.removeFirst(drop)
                    state.segmentStart += drop
                    state.decodedEnd = state.segmentStart
                    state.provisional = ""
                case .provisional(_, let end):
                    state.provisional = text
                    state.decodedEnd = end
                }
                let display = ModelSpeechPreview.tail(ModelSpeechPreview.join(state.committed, state.provisional), maximum: maximum)
                guard !display.isEmpty, display != state.published else { return nil }
                state.published = display
                return display
            }
            if let display { onText(display) }
        }
    }
}

/// Mixes meeting tracks onto one 16 kHz timeline for display-only live text.
/// Audio that arrives more than `lagSeconds` behind the newest track is dropped
/// from the preview only; saved meeting audio is written separately and unchanged.
public final class MeetingPreviewMixer: Sendable {
    private struct State {
        var emitted = 0
        var buffer: [Float] = []
        var latestEnd: [MeetingTrack: Int] = [:]
        var finished = false
    }
    private let state = Mutex(State())
    private let lag: Int
    private let sink: @Sendable ([Float]) -> Void

    public init(lagSeconds: Double = 0.5, sink: @escaping @Sendable ([Float]) -> Void) {
        lag = Int(lagSeconds * 16_000)
        self.sink = sink
    }

    public func append(_ samples: [Float], track: MeetingTrack, at offset: Double) {
        guard !samples.isEmpty, offset.isFinite, offset >= 0 else { return }
        let output = state.withLock { state -> [Float]? in
            guard !state.finished else { return nil }
            var start = Int((offset * 16_000).rounded())
            var values = samples[...]
            if start < state.emitted {
                let late = state.emitted - start
                guard late < values.count else { return nil }
                values = values.dropFirst(late)
                start = state.emitted
            }
            let end = start + values.count
            state.latestEnd[track] = max(state.latestEnd[track] ?? 0, end)
            let needed = end - state.emitted
            if state.buffer.count < needed { state.buffer.append(contentsOf: repeatElement(0, count: needed - state.buffer.count)) }
            var index = start - state.emitted
            for value in values { state.buffer[index] += value; index += 1 }
            let horizon = (state.latestEnd.values.max() ?? 0) - lag
            guard horizon > state.emitted else { return nil }
            let count = min(state.buffer.count, horizon - state.emitted)
            // The same rule as the saved mix: average the sources that contain samples.
            let divisor = Float(max(1, state.latestEnd.count))
            let chunk = state.buffer.prefix(count).map { $0 / divisor }
            state.buffer.removeFirst(count)
            state.emitted += count
            return chunk
        }
        if let output, !output.isEmpty { sink(output) }
    }

    public func finish() { state.withLock { $0.finished = true; $0.buffer = [] } }
}
