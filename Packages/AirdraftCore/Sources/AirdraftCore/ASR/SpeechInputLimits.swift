import Foundation

public enum SpeechInputLimits {
    // Leave room for WAV, multipart fields and the recorder's tail padding below 25 MB.
    public static func maximumRecordingSeconds(for kind: ASRProviderKind) -> Int {
        kind == .groq ? 740 : 1800
    }

    public static func recordingSeconds(_ requested: Int, for kind: ASRProviderKind) -> Int {
        min(max(10, requested), maximumRecordingSeconds(for: kind))
    }

    static func validate(sampleCount: Int, for kind: ASRProviderKind) throws {
        if kind == .groq && sampleCount > 12_000_000 {
            throw TranscriberError.providerFailure("Groq", "This recording exceeds the upload limit. Choose another speech provider and retry.")
        }
    }
}
