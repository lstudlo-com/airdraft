import Foundation

/// Minimal 16-bit PCM WAV writer for shipping audio to HTTP transcription APIs.
public enum WAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(samples.count * 2)

        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(le: 36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(le: UInt32(16))
        data.append(le: UInt16(1)) // PCM
        data.append(le: channels)
        data.append(le: UInt32(sampleRate))
        data.append(le: byteRate)
        data.append(le: blockAlign)
        data.append(le: bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        data.append(le: dataSize)

        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() {
            let clamped = max(-1, min(1, s))
            pcm[i] = Int16(clamped * Float(Int16.max))
        }
        pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(le value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
