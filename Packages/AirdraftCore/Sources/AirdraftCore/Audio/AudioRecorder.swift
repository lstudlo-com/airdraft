import AVFoundation
import Foundation
import os

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case formatUnavailable
    case alreadyRecording
    case microphoneUnavailable(String)
    case deviceSetupFailed(String, Int)
    case inputChanged
    case inputChannelUnavailable(Int)

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access was denied."
        case .formatUnavailable: return "The microphone's audio format is unavailable. Reconnect it or choose another microphone."
        case .alreadyRecording: return "Already recording."
        case .inputChanged: return "The microphone input changed. Record again."
        case .inputChannelUnavailable(let channel):
            return "Input \(channel) is unavailable on this microphone. Choose an input channel in Configuration."
        case .microphoneUnavailable(let name): return "\(name) is unavailable. Reconnect it or choose another microphone."
        case .deviceSetupFailed(let name, let code):
            return "macOS could not open \(name) (audio error \(code)). Try System default or reconnect the microphone."
        }
    }
}

/// Captures the selected input device and resamples to 16 kHz mono Float32,
/// which is what every ASR engine here expects.
public protocol AudioRecording: AnyObject, Sendable {
    var isRecording: Bool { get }
    var levelHandler: (@Sendable (Float) -> Void)? { get set }
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)? { get set }
    func start(microphone: MicrophonePreference) throws
    func stop() -> [Float]
    func cancel()
}

public final class AudioRecorder: AudioRecording, @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "recorder")

    private var engine: AVAudioEngine?
    private let notifications: NotificationCenter
    private var configurationObserver: NSObjectProtocol?
    private var configurationCheck: DispatchWorkItem?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private var recording = false
    private var monitoringOnly = false
    private var inputChannelIndex = 0

    /// Called on the audio thread with the RMS level of each buffer (0...1).
    public var levelHandler: (@Sendable (Float) -> Void)?
    /// Delivered on the main queue if the active input is interrupted.
    public var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    public private(set) var activeMicrophone: Microphone?
    /// Actual HAL route, which may be AVAudioEngine's private aggregate device.
    public var inputRouteID: UInt32? { engine?.inputNode.auAudioUnit.deviceID }

    public convenience init() { self.init(notifications: .default) }

    public init(notifications: NotificationCenter) {
        self.notifications = notifications
    }

    public var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return recording
    }

    public static func requestMicrophoneAccess() async -> Bool {
        await MicrophonePermission.shared.request()
    }

    public func start(microphone preference: MicrophonePreference = .systemDefault) throws {
        try start(microphone: preference, monitoringOnly: false)
    }

    /// Opens the selected input for a live level preview without retaining audio.
    public func startLevelMonitoring(microphone preference: MicrophonePreference) throws {
        try start(microphone: preference, monitoringOnly: true)
    }

    private func start(microphone preference: MicrophonePreference, monitoringOnly: Bool) throws {
        lock.lock()
        if recording { lock.unlock(); throw AudioRecorderError.alreadyRecording }
        samples.removeAll(keepingCapacity: true)
        self.monitoringOnly = monitoringOnly
        lock.unlock()

        guard let device = preference.resolve(in: MicrophoneDevices.available(), systemDefaultID: MicrophoneDevices.systemDefaultID) else {
            throw AudioRecorderError.microphoneUnavailable(preference.name)
        }
        // Recreate the engine to discard the previous device's format and route.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // AVAudioEngine already follows the system input through a managed route.
        // Preserve that route when it already contains the selected input. Only
        // override it to select a different physical device.
        if preference.uid != nil {
            do {
                if !MicrophoneDevices.route(input.auAudioUnit.deviceID, contains: device.id) {
                    try input.auAudioUnit.setDeviceID(device.id)
                }
            } catch {
                let code = (error as NSError).code
                Self.log.error("recorder: selecting device=\(device.name, privacy: .public) id=\(device.id) failed code=\(code)")
                throw AudioRecorderError.deviceSetupFailed(device.name, code)
            }
        }
        inputChannelIndex = preference.channelIndex ?? 0
        try installCaptureTap(on: engine)
        self.engine = engine
        activeMicrophone = device
        // Core Audio also posts this for output changes and startup negotiation.
        // Leave its notification queue before touching or releasing the engine.
        configurationObserver = notifications.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            DispatchQueue.main.async { [weak self, weak engine] in
                guard let self, let engine, self.engine === engine, self.isRecording else { return }
                self.configurationCheck?.cancel()
                let check = DispatchWorkItem { [weak self, weak engine] in
                    guard let self, let engine, self.engine === engine, self.isRecording else { return }
                    self.recoverConfiguration(of: engine)
                }
                self.configurationCheck = check
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: check)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            let code = (error as NSError).code
            Self.log.error("recorder: starting device=\(device.name, privacy: .public) id=\(device.id) failed code=\(code)")
            throw AudioRecorderError.deviceSetupFailed(device.name, code)
        }
        lock.lock(); recording = true; lock.unlock()
        Self.log.notice("recorder: started device=\(device.name, privacy: .public) requested=\(device.id) route=\(input.auAudioUnit.deviceID) systemDefault=\(preference.uid == nil) input=\(self.inputChannelIndex + 1) channels=\(input.outputFormat(forBus: 0).channelCount)")
    }

    private func installCaptureTap(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter = try Self.captureConverter(from: inputFormat, channelIndex: inputChannelIndex)
        let targetFormat = converter.outputFormat
        lock.lock(); self.converter = converter; lock.unlock()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }
    }

    static func captureConverter(from inputFormat: AVAudioFormat, channelIndex: Int) throws -> AVAudioConverter {
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw AudioRecorderError.formatUnavailable }
        guard channelIndex >= 0, channelIndex < Int(inputFormat.channelCount) else {
            throw AudioRecorderError.inputChannelUnavailable(channelIndex + 1)
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatUnavailable
        }
        // Discrete hardware inputs have no speaker layout. Automatic conversion
        // can map mono to -1 (silence), even while buffers keep arriving. Select
        // the microphone explicitly; mixing all inputs would include loopback.
        converter.channelMap = [NSNumber(value: channelIndex)]
        return converter
    }

    private func recoverConfiguration(of engine: AVAudioEngine) {
        guard let device = activeMicrophone else { return }
        guard MicrophoneDevices.available().contains(where: { $0.uid == device.uid && $0.id == device.id }) else {
            reportInterruption(.microphoneUnavailable(device.name))
            return
        }
        let input = engine.inputNode
        let route = input.auAudioUnit.deviceID
        guard MicrophoneDevices.route(route, contains: device.id) else {
            reportInterruption(.inputChanged)
            return
        }
        let format = input.outputFormat(forBus: 0)
        if engine.isRunning, format == converter?.inputFormat {
            Self.log.notice("recorder: configuration notification ignored; input is healthy device=\(device.name, privacy: .public)")
            return
        }
        // Keep the captured samples and the selected device. Only rebuild the tap
        // and converter if Core Audio stopped the engine or changed its format.
        engine.stop()
        input.removeTap(onBus: 0)
        flushConverter()
        do {
            try installCaptureTap(on: engine)
            engine.prepare()
            try engine.start()
            Self.log.notice("recorder: resumed after configuration change device=\(device.name, privacy: .public) rate=\(format.sampleRate) channels=\(format.channelCount)")
        } catch {
            let reason = (error as? AudioRecorderError)
                ?? .deviceSetupFailed(device.name, (error as NSError).code)
            reportInterruption(reason)
        }
    }

    private func reportInterruption(_ reason: AudioRecorderError) {
        Self.log.error("recorder: input interrupted: \(reason.localizedDescription, privacy: .public)")
        interruptionHandler?(reason)
    }

    /// Trailing silence appended to every recording so the recogniser sees a
    /// clean end of speech instead of a hard cut in the middle of the last word.
    public static let tailPaddingSeconds: Double = 0.4

    /// Stops and returns everything captured since `start()`, plus tail padding.
    public func stop() -> [Float] {
        guard let engine else { return [] }
        configurationCheck?.cancel()
        configurationCheck = nil
        if let configurationObserver { notifications.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        flushConverter()
        self.engine = nil
        activeMicrophone = nil
        lock.lock(); defer { lock.unlock() }
        converter = nil
        recording = false
        monitoringOnly = false
        var out = samples
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        Self.log.notice("recorder: stopped frames=\(out.count) peak=\(peak)")
        samples.removeAll()
        if !out.isEmpty {
            out.append(contentsOf: [Float](repeating: 0, count: Int(Self.tailPaddingSeconds * Self.sampleRate)))
        }
        return out
    }

    /// The sample-rate converter keeps a few milliseconds internally; drain it.
    private func flushConverter() {
        lock.lock(); defer { lock.unlock() }
        guard let converter,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return }
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        guard status != .error, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        if !monitoringOnly { samples.append(contentsOf: chunk) }
    }

    public func cancel() {
        _ = stop()
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

        if !monitoringOnly { samples.append(contentsOf: chunk) }
        lock.unlock()

        if let levelHandler, count > 0 {
            var sum: Float = 0
            for v in chunk { sum += v * v }
            let rms = (sum / Float(count)).squareRoot()
            levelHandler(min(1, rms * 8))
        }
    }
}
