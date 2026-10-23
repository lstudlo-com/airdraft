import CoreAudio
import Foundation
import XCTest
@testable import AirdraftCore

/// AD-080: Home readiness covers profiles that app rules choose, so it never
/// says Ready while the recording check would refuse dictation into that app.
/// Facts are injected; no file, key or model is touched.
@MainActor
final class AppRuleReadinessTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func fixture() -> (ProfileStore, AppSettings) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-rule-readiness-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "airdraft.rule-readiness.\(UUID().uuidString)"
        suites.append(suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr.select(.senseVoice)
        settings.asr.language = "en"
        settings.llm.select(.none)
        return (ProfileStore(directory: dir), settings)
    }

    private func bind(_ store: ProfileStore, _ id: UUID, to config: ASRConfig) {
        var profile = store.profiles.first { $0.id == id }!
        profile.speechModel = ProfileSpeechModel(config: config)
        store.update(profile)
    }

    private func facts(installed: [ASRProviderKind: Bool?] = [:], keys: [String: Bool?] = [:],
                       refinementKey: Bool = false) -> AppRuleSetupFacts {
        AppRuleSetupFacts(installed: { config in installed[config.kind] ?? true },
                          keyPresent: { ref in keys[ref] ?? false },
                          refinementKeyPresent: refinementKey)
    }

    private func status(_ store: ProfileStore, _ settings: AppSettings, _ facts: AppRuleSetupFacts) -> [AppRuleSetupStatus] {
        AppRuleReadiness.setups(profiles: store, settings: settings)
            .map { AppRuleReadiness.status(of: $0, llm: settings.llm, facts: facts) }
    }

    func testARuleWhoseProfileBindsAMissingLocalModelIsASetupIssue() {
        let (store, settings) = fixture()
        var parakeet = settings.asr
        parakeet.select(.parakeet)
        bind(store, RefinementProfile.summaryID, to: parakeet)
        let rule = store.addAppRule(.app(bundleID: "com.tinyspeck.slackmacgap"), profileID: RefinementProfile.summaryID, appName: "Slack")!
        // Off: rules are kept but never chosen, so nothing extra is checked.
        XCTAssertTrue(AppRuleReadiness.setups(profiles: store, settings: settings).isEmpty)

        store.setChoosesProfileByApp(true)
        let setups = AppRuleReadiness.setups(profiles: store, settings: settings)
        XCTAssertEqual(setups.map(\.rule.id), [rule.id])
        XCTAssertEqual(setups.first?.speech.kind, .parakeet)
        XCTAssertEqual(setups.first?.checksSpeech, true)
        XCTAssertEqual(setups.first?.checksRefinement, false, "Clean and Summary both refine")
        XCTAssertEqual(AppRuleReadiness.localSpeechConfigs(setups).map(\.kind), [.parakeet])
        XCTAssertEqual(status(store, settings, facts(installed: [.parakeet: false])), [.issue(.speechModelMissing)])
        XCTAssertEqual(status(store, settings, facts(installed: [.parakeet: Bool?.none])), [.checking],
                       "Unmeasured files are checked, not reported")
        XCTAssertEqual(status(store, settings, facts(installed: [.parakeet: true])), [.ready])

        // The pipeline's own snapshot for that app uses the same speech config.
        XCTAssertEqual(store.selection(forApp: "com.tinyspeck.slackmacgap").profile.speechConfig(default: settings.asr), setups[0].speech)
        // Onboarding practice always uses the chosen profile.
        settings.beginOnboardingPractice()
        XCTAssertTrue(AppRuleReadiness.setups(profiles: store, settings: settings).isEmpty)
        settings.endOnboardingPractice()
    }

    func testRulesThatMatchTheChosenProfilesSetupAddNothing() {
        let (store, settings) = fixture()
        store.setChoosesProfileByApp(true)
        store.addAppRule(.family(.code), profileID: RefinementProfile.conciseID)
        store.addAppRule(.family(.terminal), profileID: RefinementProfile.verbatimID)
        XCTAssertTrue(AppRuleReadiness.setups(profiles: store, settings: settings).isEmpty,
                      "Same speech model; Verbatim refines less than the chosen profile")
        // A binding equal to the app default resolves to the same speech config.
        bind(store, RefinementProfile.conciseID, to: settings.asr)
        XCTAssertTrue(AppRuleReadiness.setups(profiles: store, settings: settings).isEmpty)
    }

    func testRefinementIsCheckedWhenOnlyTheRulesProfileRefines() {
        let (store, settings) = fixture()
        store.setActive(RefinementProfile.verbatimID)
        settings.llm.select(.groq)
        store.setChoosesProfileByApp(true)
        store.addAppRule(.family(.email), profileID: RefinementProfile.conciseID)
        let setups = AppRuleReadiness.setups(profiles: store, settings: settings)
        XCTAssertEqual(setups.map(\.checksRefinement), [true])
        XCTAssertEqual(setups.map(\.checksSpeech), [false])
        guard case .issue(.refinement)? = status(store, settings, facts(refinementKey: false)).first else {
            return XCTFail("A missing refinement key refuses dictation into Mail")
        }
        XCTAssertEqual(status(store, settings, facts(refinementKey: true)), [.ready])
        settings.llm.select(.none)
        XCTAssertEqual(status(store, settings, facts()), [.ready], "Refinement Off needs nothing")
    }

    func testCloudBindingsRetiredBindingsAndLanguagesMapToTheirSetupActions() {
        let (store, settings) = fixture()
        store.setChoosesProfileByApp(true)
        var groq = settings.asr
        groq.select(.groq)
        bind(store, RefinementProfile.summaryID, to: groq)
        store.addAppRule(.family(.workChat), profileID: RefinementProfile.summaryID)
        XCTAssertEqual(AppRuleReadiness.speechKeyRefs(AppRuleReadiness.setups(profiles: store, settings: settings)), [groq.keyRef])
        XCTAssertEqual(status(store, settings, facts(keys: [groq.keyRef: false])), [.issue(.speechKeyMissing)])
        XCTAssertEqual(status(store, settings, facts(keys: [groq.keyRef: Bool?.none])), [.checking])
        XCTAssertEqual(status(store, settings, facts(keys: [groq.keyRef: true])), [.ready])

        bind(store, RefinementProfile.summaryID, to: ASRConfig(kind: .transcribeCpp, model: "retired-model"))
        XCTAssertEqual(status(store, settings, facts()), [.issue(.speechModelUnavailable)])

        var distil = settings.asr
        distil.select(.whisperKit)
        distil.whisperModel = WhisperModelVariant.allCases.first(where: \.isEnglishOnly)!.rawValue
        bind(store, RefinementProfile.summaryID, to: distil)
        settings.asr.language = "zh"
        guard case .issue(.speechLanguage)? = status(store, settings, facts()).first else {
            return XCTFail("An English-only binding cannot take the shared Chinese language")
        }
    }

    /// The readiness result agrees with the recording check for the same facts.
    func testStatusAgreesWithTheRecordingPrerequisites() throws {
        let (store, settings) = fixture()
        store.setChoosesProfileByApp(true)
        var parakeet = settings.asr
        parakeet.select(.parakeet)
        var groq = settings.asr
        groq.select(.groq)
        let microphone = Microphone(id: AudioDeviceID(7), uid: "fixture", name: "Fixture")
        for (binding, installed, key) in [(parakeet, false, false), (parakeet, true, false), (groq, true, false), (groq, true, true)] {
            bind(store, RefinementProfile.summaryID, to: binding)
            store.addAppRule(.family(.workChat), profileID: RefinementProfile.summaryID)
            let setup = try XCTUnwrap(AppRuleReadiness.setups(profiles: store, settings: settings).first)
            let readiness = AppRuleReadiness.status(of: setup, llm: settings.llm, facts: facts(installed: [setup.speech.kind: installed],
                                                                                              keys: [setup.speech.keyRef: key]))
            let environment = RecordingPrerequisites.Environment(
                microphoneAuthorized: true, accessibilityAuthorized: true, devices: [microphone], defaultDeviceID: 7,
                readCredential: { key && $0 == setup.speech.keyRef ? "fixture-key" : nil },
                installed: { _ in installed })
            let refused = (try? RecordingPrerequisites.check(asr: setup.speech, llm: settings.llm, refinementEnabled: setup.profile.usesLLM,
                                                             microphone: .systemDefault, insertionEnabled: true,
                                                             environment: environment)) == nil
            XCTAssertEqual(readiness != .ready, refused, "\(binding.kind) installed \(installed) key \(key): \(readiness)")
        }
    }
}
