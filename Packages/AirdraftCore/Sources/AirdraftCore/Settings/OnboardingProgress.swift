import Foundation
import Observation

/// First-use progress belongs to this installation, not the model or license.
/// Skipping is remembered separately from completing a real dictation.
@MainActor @Observable
public final class OnboardingProgress {
    public enum Step: String, CaseIterable, Codable, Sendable {
        case welcome, speech, permissions, shortcut, practice, done

        public var index: Int { Self.allCases.firstIndex(of: self)! }
        public var previous: Step? { index > 0 ? Self.allCases[index - 1] : nil }
        public var next: Step? { index + 1 < Self.allCases.count ? Self.allCases[index + 1] : nil }

        /// Shortcut practice never records, and Try It waits until the chosen engine
        /// is usable, so a press can never start dictation with the wrong model.
        public func pausesDictation(speechReady: Bool) -> Bool {
            self == .shortcut || (self == .practice && !speechReady)
        }
    }

    private struct Saved: Codable {
        var step: Step = .welcome
        var dismissed = false
        var completed = false
        /// The speech setup chosen in onboarding while its model still downloads.
        var chosenSpeech: ASRConfig?

        init(dismissed: Bool = false) { self.dismissed = dismissed }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let step = try? values.decode(Step.self, forKey: .step) {
                self.step = step
            } else if let legacy = try? values.decode(Int.self, forKey: .step) {
                // The original three-step flow stored permissions, speech, practice as 0...2.
                self.step = [.permissions, .speech, .practice][min(max(legacy, 0), 2)]
            }
            dismissed = try values.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
            completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
            chosenSpeech = try? values.decodeIfPresent(ASRConfig.self, forKey: .chosenSpeech)
        }
    }

    private let defaults: UserDefaults
    private var saved: Saved
    public private(set) var isPresented = false
    /// Real pipeline deliveries during this practice visit. Typed text never counts.
    public private(set) var practiceDeliveries = 0
    public var deliveredDuringPractice: Bool { practiceDeliveries > 0 }
    public var step: Step { saved.step }
    public var isComplete: Bool { saved.completed }
    public var hasBeenDismissed: Bool { saved.dismissed }
    public var shouldPresentOnLaunch: Bool { !saved.dismissed && !saved.completed }
    public var chosenSpeech: ASRConfig? { saved.chosenSpeech }

    public init(defaults: UserDefaults, existingSetup: Bool) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "onboarding.progress"),
           let value = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = value
        } else {
            // Do not interrupt existing users or overwrite their engine choices.
            saved = Saved(dismissed: existingSetup)
        }
    }

    /// Replaying finished setup starts again from the welcome step.
    public func present() {
        guard !isPresented else { return }
        practiceDeliveries = 0
        if saved.step == .done {
            saved.step = .welcome
            persist()
        }
        isPresented = true
    }

    public func move(to step: Step) {
        if step != .practice { practiceDeliveries = 0 }
        saved.step = step
        persist()
    }

    public func noteDelivery() {
        guard isPresented, step == .practice else { return }
        practiceDeliveries += 1
    }

    /// Remember the speech choice until its model is ready to become the app default.
    public func chooseSpeech(_ config: ASRConfig?) {
        saved.chosenSpeech = config
        persist()
    }

    /// Records success after a real practice dictation and shows the final step.
    @discardableResult public func complete() -> Bool {
        guard deliveredDuringPractice else { return false }
        saved.completed = true
        saved.dismissed = true
        saved.step = .done
        persist()
        return true
    }

    /// Closes the final step. Setup was already recorded by `complete()`.
    public func finish() {
        guard saved.completed else { return dismiss() }
        saved.chosenSpeech = nil
        isPresented = false
        persist()
    }

    public func dismiss() {
        saved.dismissed = true
        saved.chosenSpeech = nil
        isPresented = false
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "onboarding.progress")
        }
    }
}
