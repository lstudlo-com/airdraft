import AirdraftCore
import XCTest

/// Models never deletes the files of a speech model dictation may use: the app
/// default, the chosen profile's binding and, with Choose profile by app on,
/// the binding of a profile an app rule chooses (AD-080). In memory only.
@MainActor
final class ModelDeletionProtectionTests: XCTestCase {
    func testAppRuleSpeechModelIsInUseOnlyWhileRulesApply() {
        let isolated = IsolatedContainer()
        defer { isolated.tearDown() }
        let container = isolated.container
        container.settings.asr = ASRConfig(kind: .senseVoice, language: "en")
        var parakeet = container.settings.asr
        parakeet.select(.parakeet)
        var whisper = container.settings.asr
        whisper.select(.whisperKit)
        func use(_ config: ASRConfig) -> SpeechModelUse? {
            container.speechModelUse { $0.engineID == config.engineID }
        }

        XCTAssertEqual(use(container.settings.asr), .appDefault)
        XCTAssertNil(use(parakeet))

        var summary = container.profiles.profiles.first { $0.id == RefinementProfile.summaryID }!
        summary.speechModel = ProfileSpeechModel(config: parakeet)
        container.profiles.update(summary)
        container.profiles.addAppRule(.family(.terminal), profileID: RefinementProfile.summaryID)
        XCTAssertNil(use(parakeet), "Rules kept while Choose profile by app is off choose nothing")

        container.profiles.setChoosesProfileByApp(true)
        XCTAssertEqual(use(parakeet), .appRule(profile: summary.displayName))
        XCTAssertNil(use(whisper))

        // The chosen profile's own binding is reported as such.
        var clean = container.profiles.profiles.first { $0.id == RefinementProfile.cleanID }!
        clean.speechModel = ProfileSpeechModel(config: whisper)
        container.profiles.update(clean)
        XCTAssertEqual(use(whisper), .chosenProfile)

        container.profiles.setChoosesProfileByApp(false)
        XCTAssertNil(use(parakeet))
    }
}
