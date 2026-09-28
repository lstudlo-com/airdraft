import XCTest
@testable import AirdraftCore

@MainActor final class OnboardingProgressTests: XCTestCase {
    func testReplayInSameLaunchPreservesNewlyConfiguredSettings() {
        for completed in [false, true] {
            let name = "OnboardingTests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let settings = AppSettings(defaults: defaults)
            settings.onboarding.present()
            if completed {
                settings.onboarding.move(to: .practice)
                settings.onboarding.noteDelivery()
                XCTAssertTrue(settings.onboarding.complete())
            } else { settings.onboarding.dismiss() }
            settings.llm.select(.anthropic)
            settings.outputDestination = .script
            settings.onboarding.present()
            settings.beginOnboardingPractice()
            settings.endOnboardingPractice()
            XCTAssertEqual(settings.llm.kind, .anthropic)
            XCTAssertEqual(settings.outputDestination, .script)
            settings.beginOnboardingPractice()
            let restarted = AppSettings(defaults: defaults)
            XCTAssertEqual(restarted.llm.kind, .anthropic)
            XCTAssertEqual(restarted.outputDestination, .script)
        }
    }

    func testReturningUsersPracticeRestoresSettingsAfterRestart() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let original = AppSettings(defaults: defaults)
        original.llm.select(.anthropic)
        original.outputDestination = .script
        let settings = AppSettings(defaults: defaults)
        settings.beginOnboardingPractice()
        settings.beginOnboardingPractice()
        XCTAssertEqual(settings.llm.kind, .none)
        XCTAssertEqual(settings.outputDestination, .cursor)
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.llm.kind, .anthropic)
        XCTAssertEqual(restored.outputDestination, .script)
        restored.beginOnboardingPractice()
        restored.endOnboardingPractice()
        XCTAssertEqual(restored.outputDestination, .script)
    }

    func testNewInstallResumesProgressButDoesNotClaimSuccess() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = OnboardingProgress(defaults: defaults, existingSetup: false)
        XCTAssertTrue(first.shouldPresentOnLaunch)
        first.present()
        first.move(to: .practice)
        XCTAssertFalse(first.complete())
        let resumed = OnboardingProgress(defaults: defaults, existingSetup: true)
        XCTAssertEqual(resumed.step, .practice)
        XCTAssertTrue(resumed.shouldPresentOnLaunch)
        XCTAssertFalse(resumed.isComplete)
        resumed.present()
        resumed.noteDelivery()
        XCTAssertTrue(resumed.complete())
        XCTAssertFalse(OnboardingProgress(defaults: defaults, existingSetup: false).shouldPresentOnLaunch)
    }

    func testExistingUsersAndSkipStayDismissedWithoutLosingReplay() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let old = OnboardingProgress(defaults: defaults, existingSetup: true)
        XCTAssertFalse(old.shouldPresentOnLaunch)
        old.present()
        old.noteDelivery()
        XCTAssertFalse(old.complete(), "Only a dictation during the practice step can complete setup")
        old.dismiss()
        let restored = OnboardingProgress(defaults: defaults, existingSetup: false)
        XCTAssertFalse(restored.shouldPresentOnLaunch)
        XCTAssertFalse(restored.isComplete)
        restored.present()
        XCTAssertTrue(restored.isPresented)
    }
}
