import AVFoundation
import Foundation
import os

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case formatUnavailable
    case alreadyRecording
    case microphoneUnavailable(String)
    case deviceSetupFailed(String, Int)

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access was denied."
        case .formatUnavailable: return "The microphone's audio format is unavailable. Reconnect it or choose another microphone."
        case .alreadyRecording: return "Already recording."
        case .microphoneUnavailable(let name): return "\(name) is unavailable. Reconnect it or choose another microphone."
        case .deviceSetupFailed(let name, let code):
            return "macOS could not open \(name) (audio error \(code)). Try System default or reconnect the microphone."
        }
    }
}

/// Captures the selected input device and resamples to 16 kHz mono Float32,
/// which is what every ASR engine here expects.
public final class AudioRecorder: @unchecked Sendable {
    public static let sampleRate: Double = 16_000
    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "recorder")

    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private var recording = false

    /// Called on the audio thread with the RMS level of each buffer (0...1).
    public var levelHandler: (@Sendable (Float) -> Void)?
    /// Delivered on the main queue if the active input is interrupted.
    public var interruptionHandler: (@Sendable () -> Void)?
    public private(set) var activeMicrophone: Microphone?
    /// Actual HAL route, which may be AVAudioEngine's private aggregate device.
    public var inputRouteID: UInt32? { engine?.inputNode.auAudioUnit.deviceID }

    public init() {}

    public var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return recording
    }

    public static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public func start(microphone preference: MicrophonePreference = .systemDefault) throws {
        lock.lock()
        if recording { lock.unlock(); throw AudioRecorderError.alreadyRecording }
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        guard let device = preference.resolve(in: MicrophoneDevices.available(), systemDefaultID: MicrophoneDevices.systemDefaultID) else {
            throw AudioRecorderError.microphoneUnavailable(preference.name)
        }
        // Recreate the engine to discard the previous device's format and route.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // AVAudioEngine already follows the system input through a managed route.
        // Preserve that route for System default; only override it when the user
        // explicitly selects a device.
        if preference.uid != nil {
            do {
                if input.auAudioUnit.deviceID != device.id {
                    try input.auAudioUnit.setDeviceID(device.id)
                }
            } catch {
                let code = (error as NSError).code
                Self.log.error("recorder: selecting device=\(device.name, privacy: .public) id=\(device.id) failed code=\(code)")
                throw AudioRecorderError.deviceSetupFailed(device.name, code)
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw AudioRecorderError.formatUnavailable }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.formatUnavailable
        }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            self.converter = nil
            let code = (error as NSError).code
            Self.log.error("recorder: starting device=\(device.name, privacy: .public) id=\(device.id) failed code=\(code)")
            throw AudioRecorderError.deviceSetupFailed(device.name, code)
        }
        self.engine = engine
        activeMicrophone = device
        lock.lock(); recording = true; lock.unlock()
        Self.log.notice("recorder: started device=\(device.name, privacy: .public) requested=\(device.id) route=\(input.auAudioUnit.deviceID) systemDefault=\(preference.uid == nil)")
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self, weak engine] _ in
            guard let self, let engine, self.engine === engine, self.isRecording else { return }
            self.interruptionHandler?()
        }
    }

    /// Trailing silence appended to every recording so the recogniser sees a
    /// clean end of speech instead of a hard cut in the middle of the last word.
    public static let tailPaddingSeconds: Double = 0.4

    /// Stops and returns everything captured since `start()`, plus tail padding.
    public func stop() -> [Float] {
        guard let engine else { return [] }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        flushConverter()
        self.engine = nil
        converter = nil
        activeMicrophone = nil
        lock.lock(); defer { lock.unlock() }
        recording = false
        var out = samples
        samples.removeAll()
        if !out.isEmpty {
            out.append(contentsOf: [Float](repeating: 0, count: Int(Self.tailPaddingSeconds * Self.sampleRate)))
        }
        return out
    }

    /// The sample-rate converter keeps a few milliseconds internally; drain it.
    private func flushConverter() {
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
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    public func cancel() {
        _ = stop()
    }

    private func handle(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

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
        guard status != .error, let channel = out.floatChannelData?[0] else { return }

        let count = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        if let levelHandler, count > 0 {
            var sum: Float = 0
            for v in chunk { sum += v * v }
            let rms = (sum / Float(count)).squareRoot()
            levelHandler(min(1, rms * 8))
        }
    }
}
