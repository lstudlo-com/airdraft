#if os(iOS)
import AVFoundation
import Foundation
import os

/// Captures the current audio session input and resamples to 16 kHz mono
/// Float32, which is what every ASR engine here expects.
///
/// iOS lets an app in the background record only from an input that is already
/// running. A standby session keeps the input open without retaining audio, so
/// a dictation the keyboard requests from another app starts at once; `stop()`
/// then returns to standby instead of closing the input.
///
/// Unchecked: the engine, session and observers are configured on the main
/// thread by the owner, while the realtime tap touches only `samples`,
/// `converter`, `recording` and the callbacks under `lock`.
public final class AudioRecorder: AudioRecording, @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    /// Trailing silence appended to every recording so the recogniser sees a
    /// clean end of speech instead of a hard cut in the middle of the last word.
    public static let tailPaddingSeconds: Double = 0.4
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "recorder")

    private var engine: AVAudioEngine?
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var sampleCallback: (@Sendable ([Float]) -> Void)?
    private var levelCallback: (@Sendable (Float) -> Void)?
    private let lock = NSLock()
    private var recording = false
    private var standby = false
    private var retains = true

    public var samplesHandler: (@Sendable ([Float]) -> Void)? {
        get { lock.withLock { sampleCallback } }
        set { lock.withLock { sampleCallback = newValue } }
    }

    /// Called on the audio thread with the meter level of each buffer (0...1),
    /// in standby too, so the app can show that the input is live.
    public var levelHandler: (@Sendable (Float) -> Void)? {
        get { lock.withLock { levelCallback } }
        set { lock.withLock { levelCallback = newValue } }
    }

    /// Delivered on the main queue when a call, Siri or a route change takes the input.
    public var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?

    public convenience init() { self.init(notifications: .default) }

    public init(notifications: NotificationCenter) {
        self.notifications = notifications
    }

    /// Off for long recordings that stream through `samplesHandler` to disk:
    /// `stop()` then returns nothing and memory stays flat however long it runs.
    public var retainsSamples: Bool {
        get { lock.withLock { retains } }
        set { lock.withLock { retains = newValue } }
    }

    public var isRecording: Bool { lock.withLock { recording } }
    /// The input is open, recording or in standby.
    public var isInputRunning: Bool { engine != nil }
    public var isInStandby: Bool { standby }

    public static func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start(microphone preference: MicrophonePreference = .systemDefault) throws {
        try lock.withLock {
            if recording { throw AudioRecorderError.alreadyRecording }
            samples.removeAll(keepingCapacity: true)
        }
        if engine == nil { try openInput() }
        lock.withLock { recording = true }
        Self.log.notice("recorder: started standby=\(self.standby)")
    }

    /// Opens the input without retaining audio. Call while the app is in the
    /// foreground; recordings that start later reuse this input.
    public func startStandby() throws {
        if engine == nil { try openInput() }
        standby = true
        Self.log.notice("recorder: standby started")
    }

    /// Closes a standby input. A recording in progress keeps the input until it stops.
    public func endStandby() {
        standby = false
        if !isRecording { closeInput() }
        Self.log.notice("recorder: standby ended")
    }

    /// Returns everything captured since `start()`, plus tail padding. A standby
    /// input stays open for the next recording.
    public func stop() -> [Float] {
        flushConverter()
        var out: [Float] = lock.withLock {
            recording = false
            let captured = samples
            samples.removeAll()
            return captured
        }
        if !standby { closeInput() }
        let peak = out.reduce(Float(0)) { max($0, abs($1)) }
        Self.log.notice("recorder: stopped frames=\(out.count) peak=\(peak)")
        if !out.isEmpty {
            out.append(contentsOf: [Float](repeating: 0, count: Int(Self.tailPaddingSeconds * Self.sampleRate)))
        }
        return out
    }

    public func cancel() {
        _ = stop()
    }

    // MARK: - Input

    private func openInput() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // Mixing keeps the user's music playing while the input waits in standby.
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            let code = (error as NSError).code
            Self.log.error("recorder: audio session failed code=\(code)")
            throw AudioRecorderError.sessionUnavailable(code)
        }
        let engine = AVAudioEngine()
        try installCaptureTap(on: engine)
        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            let code = (error as NSError).code
            Self.log.error("recorder: engine start failed code=\(code)")
            throw AudioRecorderError.sessionUnavailable(code)
        }
        self.engine = engine
        observeSession()
    }

    private func closeInput() {
        for observer in observers { notifications.removeObserver(observer) }
        observers.removeAll()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        lock.withLock { converter = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeSession() {
        observers.append(notifications.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated { self?.interrupt(.inputChanged) }
        })
        observers.append(notifications.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt(.inputChanged) }
        })
    }

    /// A call or reset stops the engine; keep what was captured for the owner.
    private func interrupt(_ reason: AudioRecorderError) {
        let wasRecording = isRecording
        standby = false
        if !wasRecording { closeInput() }
        Self.log.error("recorder: input interrupted recording=\(wasRecording)")
        if wasRecording { interruptionHandler?(reason) }
    }

    private func installCaptureTap(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
                                               channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatUnavailable
        }
        // The built-in and Bluetooth routes deliver the microphone on the first channel.
        converter.channelMap = [0]
        lock.withLock { self.converter = converter }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }
    }

    /// The sample-rate converter keeps a few milliseconds internally; drain it.
    private func flushConverter() {
        lock.withLock {
            guard recording, retains, let converter,
                  let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 4096) else { return }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            guard status != .error, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
            converter.reset()
        }
    }

    private func handle(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        lock.lock()
        guard self.converter === converter, buffer.format == converter.inputFormat else {
            lock.unlock()
            return
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            lock.unlock()
            return
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.floatChannelData?[0] else {
            lock.unlock()
            return
        }
        let count = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
        if recording && retains { samples.append(contentsOf: chunk) }
        let preview = recording ? sampleCallback : nil
        let levelHandler = levelCallback
        lock.unlock()
        if !chunk.isEmpty { preview?(chunk) }
        if let levelHandler, count > 0 { levelHandler(AudioLevel.meter(chunk)) }
    }
}
#endif
