import Foundation
import Observation

/// Settings only the iPhone app has. Shared settings (speech, refinement,
/// profiles, vocabulary) stay in AirdraftCore's `AppSettings`.
@MainActor
@Observable
final class MobileSettings {
    /// How long a keyboard session keeps the microphone in standby. Short by
    /// default: the input stays open, and iOS shows its indicator, until it ends.
    var sessionMinutes: Int { didSet { defaults.set(sessionMinutes, forKey: Key.sessionMinutes) } }
    /// Copy each dictation made in Airdraft itself to the clipboard.
    var copiesResult: Bool { didSet { defaults.set(copiesResult, forKey: Key.copiesResult) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) } }

    static let sessionChoices = [2, 5, 15, 30, 60]
    static let defaultSessionMinutes = 5

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let sessionMinutes = "ios.sessionMinutes"
        static let copiesResult = "ios.copiesResult"
        static let onboarding = "ios.onboardingCompleted"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let minutes = defaults.integer(forKey: Key.sessionMinutes)
        sessionMinutes = Self.sessionChoices.contains(minutes) ? minutes : Self.defaultSessionMinutes
        copiesResult = defaults.object(forKey: Key.copiesResult) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
    }
}
