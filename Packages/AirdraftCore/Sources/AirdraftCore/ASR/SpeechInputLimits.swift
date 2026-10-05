import Foundation

public enum SpeechInputLimits {
    /// Microphone dictation only; imported audio keeps its provider's input limits.
    public static let recordingSecondsRange = 10...600

    public static func clampedRecordingSeconds(_ requested: Int) -> Int {
        min(max(recordingSecondsRange.lowerBound, requested), recordingSecondsRange.upperBound)
    }

    // Leave room for WAV, multipart fields and the recorder's tail padding below 25 MB.
    public static func maximumRecordingSeconds(for kind: ASRProviderKind) -> Int {
        min(recordingSecondsRange.upperBound, kind == .groq ? 740 : Int.max)
    }

    public static func recordingSeconds(_ requested: Int, for kind: ASRProviderKind) -> Int {
        min(clampedRecordingSeconds(requested), maximumRecordingSeconds(for: kind))
    }

    static func validate(sampleCount: Int, for kind: ASRProviderKind) throws {
        if kind == .groq && sampleCount > 12_000_000 {
            throw TranscriberError.providerFailure("Groq", "This recording exceeds the upload limit. Choose another speech provider and retry.")
        }
    }
}
