import Foundation
import WhisperKit

public enum AudioFile {
    /// Any file AVFoundation can read, as 16 kHz mono Float32. For the CLI and self-tests.
    public static func load(path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }
}
