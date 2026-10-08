import Foundation

/// Shared relative meter response. Linear in signal amplitude; no decibel/log curve.
public enum AudioLevel {
    public static func meter(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var power: Double = 0
        for sample in samples {
            guard sample.isFinite else { return 0 }
            power += Double(sample) * Double(sample)
        }
        return Float(min(1, sqrt(power / Double(samples.count)) * 8))
    }
}
