import AVFoundation
import Foundation

public enum MediaAudioDecoder {
    /// Decode one selected audio track through AVFoundation. Bounded PCM buffers; no audio output device.
    public static func normalize(_ source: URL, to destination: URL) async throws -> Double {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MediaError.invalidAudio }
        guard duration <= MediaConfiguration.maximumDuration else { throw MediaError.tooLong }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw MediaError.invalidAudio }
        // A multi-track video needs an explicit track choice, not a silent arbitrary mix.
        guard tracks.count == 1 else { throw MediaDecodeError.multipleTracks }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.invalidAudio }
        reader.add(output)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let file = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard reader.startReading() else { throw reader.error ?? MediaError.invalidAudio }
        var frames: Int64 = 0
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let block = CMSampleBufferGetDataBuffer(sample) else { throw MediaError.invalidAudio }
                let count = CMSampleBufferGetNumSamples(sample)
                guard count > 0, count <= 1_048_576,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let pointer = buffer.floatChannelData?[0] else { throw MediaError.invalidAudio }
                guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: pointer) == noErr else { throw MediaError.invalidAudio }
                buffer.frameLength = AVAudioFrameCount(count)
                guard (0..<count).allSatisfy({ pointer[$0].isFinite }) else { throw MediaError.invalidAudio }
                frames += Int64(count)
                guard Double(frames) / 16_000 <= MediaConfiguration.maximumDuration else { throw MediaError.tooLong }
                try file.write(from: buffer)
            }
            try Task.checkCancellation()
            guard reader.status == .completed, frames > 0 else { throw reader.error ?? MediaError.invalidAudio }
            return Double(frames) / 16_000
        } catch {
            reader.cancelReading()
            throw error
        }
    }
}

public enum MediaDecodeError: LocalizedError {
    case multipleTracks
    public var errorDescription: String? { "This file contains multiple audio tracks. Export the track you want as a separate audio file, then import it." }
}

/// A bounded read that preserves absolute positions across app restarts.
public enum MediaAudioWindow {
    public static func read(_ url: URL, from seconds: Double, maximumSeconds: Double = 25) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16_000, (1...2).contains(file.processingFormat.channelCount),
              seconds.isFinite, seconds >= 0, maximumSeconds > 0 else { throw MediaError.invalidAudio }
        file.framePosition = min(file.length, AVAudioFramePosition(seconds * 16_000))
        let count = min(Int64(maximumSeconds * 16_000), file.length - file.framePosition)
        guard count > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else { throw MediaError.invalidAudio }
        try file.read(into: buffer)
        guard let pointer = buffer.floatChannelData?[0] else { throw MediaError.invalidAudio }
        let frameCount = Int(buffer.frameLength)
        if file.processingFormat.channelCount == 2, let other = buffer.floatChannelData?[1] {
            return (0..<frameCount).map { (pointer[$0] + other[$0]) * 0.5 }
        }
        return Array(UnsafeBufferPointer(start: pointer, count: frameCount))
    }
}
