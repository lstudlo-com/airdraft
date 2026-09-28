import Foundation
import Observation

/// First-use progress belongs to this installation, not the model or license.
/// Skipping is remembered separately from completing a real dictation.
@MainActor @Observable
public final class OnboardingProgress {
    public enum Step: Int, CaseIterable, Codable, Sendable {
        case permissions, speech, practice
    }
    private struct Saved: Codable {
        var step: Step = .permissions
        var dismissed = false
        var completed = false
    }
    private let defaults: UserDefaults
    private var saved: Saved
    public private(set) var isPresented = false
    public private(set) var deliveredDuringPractice = false
    public var step: Step { saved.step }
    public var isComplete: Bool { saved.completed }
    public var shouldPresentOnLaunch: Bool { !saved.dismissed && !saved.completed }

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

    public func present() {
        guard !isPresented else { return }
        deliveredDuringPractice = false
        isPresented = true
    }

    public func move(to step: Step) {
        saved.step = step
        persist()
    }

    public func noteDelivery() {
        guard isPresented, step == .practice else { return }
        deliveredDuringPractice = true
    }

    @discardableResult public func complete() -> Bool {
        guard deliveredDuringPractice else { return false }
        saved.completed = true
        saved.dismissed = true
        isPresented = false
        persist()
        return true
    }

    public func dismiss() {
        saved.dismissed = true
        isPresented = false
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "onboarding.progress")
        }
    }
}
