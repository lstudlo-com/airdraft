import AVFoundation
import Foundation

public enum AudioRecorderError: Error, LocalizedError {
    case microphoneDenied
    case formatUnavailable
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access was denied."
        case .formatUnavailable: return "Could not create the 16 kHz mono audio format."
        case .alreadyRecording: return "Already recording."
        }
    }
}

/// Captures the default input device and resamples to 16 kHz mono Float32,
/// which is what every ASR engine here expects.
public final class AudioRecorder: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private var recording = false

    /// Called on the audio thread with the RMS level of each buffer (0...1).
    public var levelHandler: (@Sendable (Float) -> Void)?

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

    public func start() throws {
        lock.lock()
        if recording { lock.unlock(); throw AudioRecorderError.alreadyRecording }
        samples.removeAll(keepingCapacity: true)
        recording = true
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw AudioRecorderError.formatUnavailable }

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
    }

    /// Trailing silence appended to every recording so the recogniser sees a
    /// clean end of speech instead of a hard cut in the middle of the last word.
    public static let tailPaddingSeconds: Double = 0.4

    /// Stops and returns everything captured since `start()`, plus tail padding.
    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        flushConverter()
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
