import XCTest
@testable import AirdraftCore

@MainActor final class OnboardingProgressTests: XCTestCase {
    func testPracticeProfileOverrideEndsOnExitAndDoesNotSurviveRestart() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let original = AppSettings(defaults: defaults)
        original.asr = ASRConfig(kind: .senseVoice)
        original.llm = LLMConfig(kind: .appleIntelligence)
        original.outputDestination = .script
        let settings = AppSettings(defaults: defaults)
        let profile = RefinementProfile(name: "Bound", instructions: "",
            speechModel: ProfileSpeechModel(config: ASRConfig(kind: .openAI)))
        for _ in 0..<3 {
            settings.beginOnboardingPractice()
            XCTAssertTrue(settings.isOnboardingPractice)
            XCTAssertEqual(settings.speechConfig(for: profile).kind, .senseVoice)
            XCTAssertNil(settings.effectiveProfile(profile).speechModel)
            XCTAssertFalse(settings.effectiveProfile(profile).usesLLM)
            settings.endOnboardingPractice()
            XCTAssertFalse(settings.isOnboardingPractice)
            XCTAssertEqual(settings.effectiveProfile(profile), profile)
            XCTAssertEqual(settings.speechConfig(for: profile).kind, .openAI)
            XCTAssertEqual(settings.llm.kind, .appleIntelligence)
            XCTAssertEqual(settings.outputDestination, .script)
        }
        settings.beginOnboardingPractice()
        let restarted = AppSettings(defaults: defaults)
        XCTAssertFalse(restarted.isOnboardingPractice)
        XCTAssertEqual(restarted.effectiveProfile(profile), profile)
        XCTAssertEqual(restarted.speechConfig(for: profile).kind, .openAI)
        XCTAssertEqual(restarted.llm.kind, .appleIntelligence)
        XCTAssertEqual(restarted.outputDestination, .script)
    }

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
                XCTAssertEqual(settings.onboarding.step, .done)
                XCTAssertTrue(settings.onboarding.isPresented, "The final step stays visible after success")
                settings.onboarding.finish()
                XCTAssertFalse(settings.onboarding.isPresented)
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

    func testLegacyThreeStepProgressKeepsItsStepAndChoices() throws {
        for (legacy, step) in [(0, OnboardingProgress.Step.permissions), (1, .speech), (2, .practice)] {
            let name = "OnboardingTests.\(UUID())"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let json = #"{"step":\#(legacy),"dismissed":true,"completed":false}"#
            defaults.set(Data(json.utf8), forKey: "onboarding.progress")
            let progress = OnboardingProgress(defaults: defaults, existingSetup: false)
            XCTAssertEqual(progress.step, step)
            XCTAssertTrue(progress.hasBeenDismissed, "Migration must not reopen a skipped setup")
            XCTAssertFalse(progress.shouldPresentOnLaunch)
            XCTAssertNil(progress.chosenSpeech)
        }
    }

    func testNewInstallStartsAtWelcomeAndReplayRestartsAfterSuccess() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = OnboardingProgress(defaults: defaults, existingSetup: false)
        XCTAssertEqual(progress.step, .welcome)
        XCTAssertEqual(OnboardingProgress.Step.allCases.map(\.rawValue),
                       ["welcome", "speech", "permissions", "shortcut", "practice", "done"])
        XCTAssertEqual(OnboardingProgress.Step.welcome.next, .speech)
        XCTAssertNil(OnboardingProgress.Step.welcome.previous)
        XCTAssertEqual(OnboardingProgress.Step.practice.previous, .shortcut)
        progress.present()
        progress.chooseSpeech(ASRConfig(kind: .whisperKit))
        progress.move(to: .practice)
        progress.noteDelivery()
        progress.noteDelivery()
        XCTAssertEqual(progress.practiceDeliveries, 2)
        XCTAssertTrue(progress.complete())
        progress.finish()
        XCTAssertNil(progress.chosenSpeech, "A finished setup leaves the speech default to Models")
        let restarted = OnboardingProgress(defaults: defaults, existingSetup: true)
        XCTAssertTrue(restarted.isComplete)
        XCTAssertEqual(restarted.step, .done)
        restarted.present()
        XCTAssertEqual(restarted.step, .welcome)
        XCTAssertFalse(restarted.deliveredDuringPractice)
        XCTAssertTrue(restarted.isComplete, "Replaying does not forget earlier success")
    }

    func testDeliveriesCountOnlyInPracticeAndResetWhenLeaving() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = OnboardingProgress(defaults: defaults, existingSetup: false)
        progress.present()
        progress.move(to: .shortcut)
        progress.noteDelivery()
        XCTAssertFalse(progress.deliveredDuringPractice)
        progress.move(to: .practice)
        progress.noteDelivery()
        XCTAssertTrue(progress.deliveredDuringPractice)
        progress.move(to: .shortcut)
        XCTAssertFalse(progress.deliveredDuringPractice, "Returning to practice needs a new dictation")
        progress.move(to: .practice)
        XCTAssertFalse(progress.complete())
        progress.finish()
        XCTAssertTrue(progress.hasBeenDismissed, "Finishing without success is a skip")
        XCTAssertFalse(progress.isComplete)
    }

    func testChosenSpeechSurvivesRestartUntilSkipped() {
        let name = "OnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let progress = OnboardingProgress(defaults: defaults, existingSetup: false)
        var config = ASRConfig(kind: .senseVoice)
        config.language = "zh"
        progress.chooseSpeech(config)
        progress.move(to: .permissions)
        let resumed = OnboardingProgress(defaults: defaults, existingSetup: true)
        XCTAssertEqual(resumed.chosenSpeech, config)
        XCTAssertEqual(resumed.step, .permissions)
        resumed.dismiss()
        XCTAssertNil(OnboardingProgress(defaults: defaults, existingSetup: false).chosenSpeech)
    }

    func testOnlyShortcutPracticeAndUnreadyTryItPauseDictation() {
        for step in OnboardingProgress.Step.allCases {
            XCTAssertEqual(step.pausesDictation(speechReady: true), step == .shortcut, "\(step)")
            XCTAssertEqual(step.pausesDictation(speechReady: false), step == .shortcut || step == .practice, "\(step)")
        }
    }
}
