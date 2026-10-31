import ActivityKit
import Foundation

/// The Live Activity that shows, on the Lock Screen and in the Dynamic Island,
/// that Airdraft's microphone session is open.
struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            /// The input waits in standby for the keyboard.
            case ready
            case recording
            case processing
        }

        var phase: Phase
        var endsAt: Date?
        var recordingStartedAt: Date?
    }
}
