import AVFoundation
import XCTest
@testable import AirdraftCore

final class AudioRecorderTests: XCTestCase {
    func testDiscreteHardwareInputsProduceAudibleMono() throws {
        // Scarlett exposes four discrete inputs, not a surround speaker layout.
        // The implicit AVAudioConverter map is [-1], which produces only zeros.
        for rate in [44_100.0, 48_000.0] {
            let format = try discreteFormat(channels: 4, sampleRate: rate)
            for channel in 0..<4 {
                let samples = try convert(format: format, selected: channel, signalOn: channel)
                XCTAssertGreaterThan(samples.count, 1_000)
                XCTAssertEqual(peak(samples), 0.25, accuracy: 0.01,
                               "Input \(channel + 1) at \(rate) Hz must survive conversion")
                let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
                XCTAssertGreaterThan(rms, 0.15)
            }
        }
    }

    func testOtherInputsAndLoopbackAreExcluded() throws {
        let format = try discreteFormat(channels: 4, sampleRate: 48_000)
        for selected in 0..<2 {
            for other in 0..<4 where other != selected {
                let samples = try convert(format: format, selected: selected, signalOn: other)
                XCTAssertFalse(samples.isEmpty)
                XCTAssertEqual(peak(samples), 0)
            }
        }
    }

    func testMonoAndStereoMicrophonesKeepTheirSignal() throws {
        for channels: AVAudioChannelCount in [1, 2] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000, channels: channels, interleaved: false))
            for channel in 0..<Int(channels) {
                XCTAssertEqual(peak(try convert(format: format, selected: channel, signalOn: channel)),
                               0.25, accuracy: 0.01)
            }
        }
    }

    func testUnavailableInputFailsInsteadOfRecordingSilence() throws {
        let format = try discreteFormat(channels: 4, sampleRate: 48_000)
        for channel in [-1, 4] {
            XCTAssertThrowsError(try AudioRecorder.captureConverter(from: format, channelIndex: channel)) { error in
                guard case AudioRecorderError.inputChannelUnavailable = error else {
                    return XCTFail("Expected unavailable input, received \(error)")
                }
            }
        }
    }

    private func discreteFormat(channels: AVAudioChannelCount, sampleRate: Double) throws -> AVAudioFormat {
        let layout = try XCTUnwrap(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels))
        return try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                          interleaved: false, channelLayout: layout))
    }

    private func convert(format: AVAudioFormat, selected: Int, signalOn: Int) throws -> [Float] {
        let converter = try AudioRecorder.captureConverter(from: format, channelIndex: selected)
        XCTAssertEqual(converter.outputFormat.sampleRate, AudioRecorder.sampleRate)
        XCTAssertEqual(converter.outputFormat.channelCount, 1)
        let frameCount = Int(format.sampleRate / 10)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)))
        input.frameLength = input.frameCapacity
        let channels = try XCTUnwrap(input.floatChannelData)
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<frameCount {
                channels[channel][frame] = channel == signalOn
                    ? 0.25 * sin(Float(frame) * 2 * .pi * 440 / Float(format.sampleRate)) : 0
            }
        }
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 1_616))
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        XCTAssertNotEqual(status, .error)
        XCTAssertNil(error)
        return Array(UnsafeBufferPointer(start: try XCTUnwrap(output.floatChannelData)[0],
                                         count: Int(output.frameLength)))
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }
}
