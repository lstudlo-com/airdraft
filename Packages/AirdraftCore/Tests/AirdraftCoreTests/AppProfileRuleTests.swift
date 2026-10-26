import AppKit
import ApplicationServices
import Foundation
import XCTest
@testable import AirdraftCore

/// Choose profile by app (AD-080): resolution, persistence and the recording
/// snapshot. Engines, capture and delivery are injected; no microphone,
/// general clipboard, credential or real app is used.
@MainActor
final class AppProfileRuleTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-app-rules-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Resolution

    /// App rule beats family rule beats chosen profile; families come from bundle IDs alone; a rule for the same target is updated.
    func testRuleResolutionClassificationAndUpdates() {
        // AppRuleBeatsFamilyRuleWhichBeatsChosenProfile
        do {
            let store = ProfileStore(directory: tempDir())
            store.setActive(RefinementProfile.conciseID)
            store.addAppRule(.family(.terminal), profileID: RefinementProfile.summaryID)
            store.addAppRule(.app(bundleID: "dev.warp.Warp"), profileID: RefinementProfile.verbatimID, appName: "Warp")

            // Off by default: rules are kept but the chosen profile applies everywhere.
            XCTAssertFalse(store.choosesProfileByApp)
            XCTAssertEqual(store.selection(forApp: "dev.warp.Warp").profile.id, RefinementProfile.conciseID)
            XCTAssertNil(store.selection(forApp: "dev.warp.Warp").rule)

            store.setChoosesProfileByApp(true)
            XCTAssertEqual(store.selection(forApp: "dev.warp.Warp").profile.id, RefinementProfile.verbatimID)
            XCTAssertEqual(store.selection(forApp: "DEV.WARP.warp").profile.id, RefinementProfile.verbatimID, "Bundle IDs match case-insensitively")
            XCTAssertEqual(store.selection(forApp: "com.googlecode.iterm2").profile.id, RefinementProfile.summaryID)
            XCTAssertEqual(store.selection(forApp: "com.googlecode.iterm2").rule?.match, .family(.terminal))
            for terminal in ["org.alacritty", "com.github.wez.wezterm"] {
                XCTAssertEqual(store.selection(forApp: terminal).rule?.match, .family(.terminal), terminal)
            }
            XCTAssertEqual(store.selection(forApp: "com.apple.mail").profile.id, RefinementProfile.conciseID)
            XCTAssertFalse(store.selection(forApp: "com.apple.mail").isAutomatic)
            XCTAssertEqual(store.selection(forApp: nil).profile.id, RefinementProfile.conciseID)
            XCTAssertEqual(store.selection(forApp: "com.example.unknown").profile.id, RefinementProfile.conciseID)
        }
        // FamilyComesFromBundleIDAloneAndGeneralIsNotARule
        do {
            XCTAssertEqual(AppFamily.classify(bundleID: "com.microsoft.VSCode"), .code)
            XCTAssertEqual(AppFamily.classify(bundleID: "com.jetbrains.intellij"), .code)
            XCTAssertEqual(AppFamily.classify(bundleID: "com.tinyspeck.slackmacgap"), .workChat)
            XCTAssertEqual(AppFamily.classify(bundleID: "com.google.Chrome"), .general, "A browser's family needs its URL, which rules never read")
            let store = ProfileStore(directory: tempDir())
            XCTAssertNil(store.addAppRule(.family(.general), profileID: RefinementProfile.summaryID))
            XCTAssertNil(store.addAppRule(.family(.code), profileID: UUID()), "A rule must name an existing profile")
            XCTAssertTrue(store.appRules.isEmpty)
            XCTAssertFalse(AppProfileRule.selectableFamilies.contains(.general))
        }
        // AddingARuleForTheSameTargetUpdatesIt
        do {
            let store = ProfileStore(directory: tempDir())
            let first = store.addAppRule(.family(.code), profileID: RefinementProfile.summaryID)
            let second = store.addAppRule(.family(.code), profileID: RefinementProfile.verbatimID)
            XCTAssertEqual(store.appRules.count, 1)
            XCTAssertEqual(first?.id, second?.id)
            XCTAssertEqual(store.appRules.first?.profileID, RefinementProfile.verbatimID)
            store.setProfile(RefinementProfile.conciseID, forRule: first!.id)
            XCTAssertEqual(store.appRules.first?.profileID, RefinementProfile.conciseID)
            store.setProfile(UUID(), forRule: first!.id)
            XCTAssertEqual(store.appRules.first?.profileID, RefinementProfile.conciseID, "An unknown profile is refused")
            store.removeAppRule(id: first!.id)
            XCTAssertTrue(store.appRules.isEmpty)
        }
    }

    // MARK: Profile deletion, reset, persistence and migration

    /// Deletion and reset, persistence and 0.11 migration, unreadable rules skipped in place and written back unchanged.
    func testRulesPersistMigrateKeepUnreadableEntriesAndFollowProfileDeletion() throws {
        // DeletingAProfileRemovesItsRulesAndResetClearsAll
        do {
            let dir = tempDir()
            let store = ProfileStore(directory: dir)
            let coding = store.add(RefinementProfile(name: "Coding", instructions: "Keep identifiers."))
            store.setChoosesProfileByApp(true)
            store.addAppRule(.family(.terminal), profileID: coding.id)
            store.addAppRule(.app(bundleID: "dev.zed.Zed"), profileID: coding.id, appName: "Zed")
            store.addAppRule(.family(.email), profileID: RefinementProfile.conciseID)
            XCTAssertEqual(store.selection(forApp: "dev.zed.Zed").profile.id, coding.id)

            store.remove(id: coding.id)
            XCTAssertEqual(store.appRules.map(\.match), [.family(.email)])
            XCTAssertEqual(store.selection(forApp: "dev.zed.Zed").profile.id, store.activeProfileID, "Never another profile silently")
            XCTAssertEqual(ProfileStore(directory: dir).appRules.map(\.match), [.family(.email)])

            // Resetting a built-in keeps its rules: the profile still exists.
            store.resetProfile(id: RefinementProfile.conciseID)
            XCTAssertEqual(store.appRules.count, 1)

            store.resetAll()
            XCTAssertTrue(store.appRules.isEmpty)
            XCTAssertFalse(store.choosesProfileByApp)
            let reloaded = ProfileStore(directory: dir)
            XCTAssertTrue(reloaded.appRules.isEmpty)
            XCTAssertFalse(reloaded.choosesProfileByApp)
        }
        // RulesPersistAndOlderFilesLoadWithTheFeatureOff
        do {
            let dir = tempDir()
            let store = ProfileStore(directory: dir)
            store.setChoosesProfileByApp(true)
            store.addAppRule(.app(bundleID: "dev.warp.Warp"), profileID: RefinementProfile.summaryID, appName: "Warp")
            store.addAppRule(.family(.code), profileID: RefinementProfile.verbatimID)
            let reloaded = ProfileStore(directory: dir)
            XCTAssertTrue(reloaded.choosesProfileByApp)
            XCTAssertEqual(reloaded.appRules, store.appRules)
            XCTAssertEqual(reloaded.appRules.first?.appName, "Warp")

            // A 0.11 file has neither key.
            let legacyDir = tempDir()
            let legacy = """
            {"version":1,"baseRules":"base","activeProfileID":"\(RefinementProfile.summaryID.uuidString)",
             "profiles":\(String(decoding: try JSONEncoder().encode(RefinementProfile.defaults), as: UTF8.self))}
            """
            try Data(legacy.utf8).write(to: legacyDir.appendingPathComponent("profiles.json"))
            let migrated = ProfileStore(directory: legacyDir)
            XCTAssertNil(migrated.persistenceError)
            XCTAssertFalse(migrated.choosesProfileByApp)
            XCTAssertTrue(migrated.appRules.isEmpty)
            XCTAssertEqual(migrated.activeProfileID, RefinementProfile.summaryID)
            XCTAssertEqual(migrated.baseRules, "base")
        }
        // UnreadableRulesAreSkippedWithoutSettingTheFileAside
        do {
            let dir = tempDir()
            let valid = AppProfileRule(match: .family(.email), profileID: RefinementProfile.conciseID)
            let missingProfile = AppProfileRule(match: .family(.code), profileID: UUID())
            let duplicate = AppProfileRule(match: .family(.email), profileID: RefinementProfile.summaryID)
            let encoded = try JSONEncoder().encode([valid, missingProfile, duplicate])
            var rules = try JSONSerialization.jsonObject(with: encoded) as! [Any]
            // A newer version's family and an unrelated value must not break loading.
            rules.insert(["id": UUID().uuidString, "profileID": RefinementProfile.cleanID.uuidString,
                          "match": ["family": ["_0": "spreadsheet"]]], at: 0)
            rules.insert("not a rule", at: 1)
            let file: [String: Any] = [
                "version": 1, "baseRules": "base", "activeProfileID": RefinementProfile.cleanID.uuidString,
                "profiles": try JSONSerialization.jsonObject(with: JSONEncoder().encode(RefinementProfile.defaults)),
                "choosesProfileByApp": true, "appRules": rules,
            ]
            let url = dir.appendingPathComponent("profiles.json")
            try JSONSerialization.data(withJSONObject: file).write(to: url)
            let store = ProfileStore(directory: dir)
            XCTAssertNil(store.persistenceError)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(store.choosesProfileByApp)
            XCTAssertEqual(store.appRules, [valid])
            XCTAssertEqual(store.selection(forApp: "com.apple.mail").profile.id, RefinementProfile.conciseID)
        }
        // UnreadableRulesAreWrittenBackUnchangedOnSave
        // A rule written by a newer version survives saving in this one, unchanged;
        // deleting its profile or Reset All removes it like any other rule.
        do {
            let dir = tempDir()
            let url = dir.appendingPathComponent("profiles.json")
            let custom = ProfileStore(directory: dir).addNew()
            let newer: [String: Any] = ["id": UUID().uuidString, "profileID": RefinementProfile.cleanID.uuidString,
                                        "match": ["family": ["_0": "spreadsheet"]], "appName": "Numbers",
                                        "priority": 2, "weight": 0.5, "enabled": true, "tags": ["a", NSNull()]]
            let newerForCustom: [String: Any] = ["id": UUID().uuidString, "profileID": custom.id.uuidString,
                                                 "match": ["window": ["_0": "Inbox"]]]
            let orphan: [String: Any] = ["id": UUID().uuidString, "profileID": UUID().uuidString,
                                         "match": ["family": ["_0": "spreadsheet"]]]
            var file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            file["choosesProfileByApp"] = true
            file["appRules"] = [newer, "not a rule", newerForCustom, orphan]
            try JSONSerialization.data(withJSONObject: file).write(to: url)

            func storedRules() throws -> [Any] {
                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
                return try XCTUnwrap(object?["appRules"] as? [Any])
            }
            let store = ProfileStore(directory: dir)
            XCTAssertNil(store.persistenceError)
            XCTAssertTrue(store.appRules.isEmpty)
            // Any save writes the readable rules first, then the unreadable ones as read.
            let added = try XCTUnwrap(store.addAppRule(.family(.email), profileID: RefinementProfile.conciseID))
            var saved = try storedRules()
            XCTAssertEqual(saved.count, 4, "The orphaned rule is dropped like a readable one")
            XCTAssertEqual((saved[0] as? [String: Any])?["id"] as? String, added.id.uuidString)
            XCTAssertEqual(saved[1] as? NSDictionary, newer as NSDictionary, "The newer rule is written back unchanged")
            XCTAssertEqual(saved[2] as? String, "not a rule")
            XCTAssertEqual(saved[3] as? NSDictionary, newerForCustom as NSDictionary)
            let reloaded = ProfileStore(directory: dir)
            XCTAssertEqual(reloaded.appRules, [added])
            reloaded.setChoosesProfileByApp(false)
            XCTAssertEqual(try storedRules().count, 4, "Rules stay saved while the switch is off")

            reloaded.remove(id: custom.id)
            saved = try storedRules()
            XCTAssertEqual(saved.count, 3, "Deleting a profile removes the unreadable rule that names it")
            XCTAssertFalse(saved.contains { ($0 as? NSDictionary) == newerForCustom as NSDictionary })
            reloaded.resetAll()
            XCTAssertTrue(try storedRules().isEmpty, "Reset All clears every rule")
        }
    }

    // MARK: Recording snapshot

    func testRecordingSnapshotUsesFrontmostRuleItsSpeechModelAndLimitButNotInPractice() async throws {
        // RecordingUsesTheFrontmostAppsRuleIncludingItsSpeechModelAndKeepsIt
        do {
            let fixture = try RuleFixture()
            defer { fixture.close() }
            var summary = fixture.profiles.profiles.first { $0.id == RefinementProfile.summaryID }!
            var bound = fixture.settings.asr
            bound.select(.parakeet)
            summary.speechModel = ProfileSpeechModel(config: bound)
            fixture.profiles.update(summary)
            fixture.profiles.setChoosesProfileByApp(true)
            let rule = fixture.profiles.addAppRule(.family(.terminal), profileID: RefinementProfile.summaryID)!
            fixture.frontmost = "dev.warp.Warp"

            try await fixture.pipeline.startFromAutomation()
            XCTAssertEqual(fixture.preflightASR?.kind, .parakeet, "An automatic profile's speech binding applies")
            XCTAssertEqual(fixture.preflightUsesLLM, true)
            // Rule, profile and frontmost changes during recording apply to the next one.
            fixture.profiles.setProfile(RefinementProfile.verbatimID, forRule: rule.id)
            fixture.frontmost = "com.apple.mail"
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Summary")
            XCTAssertEqual(try fixture.history.recent().first?.asrEngine, bound.engineID)
            XCTAssertEqual(fixture.pipeline.speechConfig.kind, .senseVoice, "The app default and chosen profile are unchanged")
            XCTAssertEqual(fixture.profiles.activeProfileID, RefinementProfile.cleanID)

            try await fixture.pipeline.startFromAutomation()
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Clean", "Mail has no rule")
            fixture.frontmost = "dev.warp.Warp"
            try await fixture.pipeline.startFromAutomation()
            XCTAssertEqual(fixture.preflightUsesLLM, false)
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Verbatim")
        }
        // RecordingLimitFollowsTheSnapshotsSpeechModel
        // The recording limit and the kept-audio bound come from the speech model
        // the recording's snapshot uses (here an app rule's), never from the chosen
        // profile's model, so provider limits match the engine that transcribes.
        do {
            let fixture = try RuleFixture()
            defer { fixture.close() }
            var summary = fixture.profiles.profiles.first { $0.id == RefinementProfile.summaryID }!
            var bound = fixture.settings.asr
            bound.select(.parakeet)
            summary.speechModel = ProfileSpeechModel(config: bound)
            fixture.profiles.update(summary)
            fixture.profiles.setChoosesProfileByApp(true)
            fixture.profiles.addAppRule(.family(.terminal), profileID: RefinementProfile.summaryID)
            fixture.settings.maxRecordingSeconds = 600
            fixture.pipeline.recordingLimitSeconds = { requested, kind in kind == .parakeet ? 1 : requested }
            fixture.frontmost = "dev.warp.Warp"
            XCTAssertEqual(fixture.pipeline.availableRecordingSeconds, 1, "The rule's model sets the limit")
            fixture.frontmost = "com.apple.mail"
            XCTAssertEqual(fixture.pipeline.availableRecordingSeconds, 600)
            XCTAssertFalse(fixture.pipeline.keptAudioShortensNextRecording)

            // A recording into the rule's app stops at its model's limit, with no kept-audio notice.
            fixture.frontmost = "dev.warp.Warp"
            try await fixture.pipeline.startFromAutomation()
            XCTAssertEqual(fixture.preflightASR?.kind, .parakeet)
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            while fixture.pipeline.isRecording, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(fixture.pipeline.isRecording, "The rule's model limit stops the recording")
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.asrEngine, bound.engineID)
            XCTAssertEqual(fixture.pipeline.state, .idle, "A provider limit is not a kept-audio stop")

            // The chosen profile's shorter limit does not shorten the rule's recording.
            fixture.pipeline.recordingLimitSeconds = { requested, kind in kind == .senseVoice ? 1 : requested }
            try await fixture.pipeline.startFromAutomation()
            try await Task.sleep(for: .milliseconds(1_600))
            XCTAssertTrue(fixture.pipeline.isRecording, "Only the transcribing engine's limit applies")
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(fixture.pipeline.state, .idle)
            XCTAssertEqual(try fixture.history.recent().count, 2)
        }
        // OnboardingPracticeIgnoresAppRules
        do {
            let fixture = try RuleFixture()
            defer { fixture.close() }
            fixture.profiles.setChoosesProfileByApp(true)
            fixture.profiles.addAppRule(.family(.terminal), profileID: RefinementProfile.summaryID)
            fixture.frontmost = "dev.warp.Warp"
            fixture.settings.beginOnboardingPractice()
            defer { fixture.settings.endOnboardingPractice() }
            try await fixture.pipeline.startFromAutomation()
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Clean")
        }
    }

    func testStartupRuleChangeIsRejectedAndCapturedDestinationIsFollowedOnlyWithoutUncheckedSetup() async throws {
        // RuleChangeDuringStartupIsRejectedLikeAnyOtherSetupChange
        do {
            let fixture = try RuleFixture()
            defer { fixture.close() }
            fixture.profiles.setChoosesProfileByApp(true)
            let rule = fixture.profiles.addAppRule(.app(bundleID: "dev.warp.Warp"), profileID: RefinementProfile.summaryID)!
            fixture.frontmost = "dev.warp.Warp"
            fixture.onPreflight = { fixture.profiles.setProfile(RefinementProfile.conciseID, forRule: rule.id) }
            do {
                try await fixture.pipeline.startFromAutomation()
                XCTFail("A rule change before capture must not record with stale settings")
            } catch {}
            XCTAssertFalse(fixture.pipeline.isRecording)
        }
        // CapturedDestinationIsFollowedOnlyWhenItNeedsNoUncheckedSetup
        do {
            let target = RuleTarget(bundleID: "fixture.editor")
            defer { target.close() }
            let fixture = try RuleFixture(target: target)
            defer { fixture.close() }
            fixture.pipeline.insertionEnabled = true
            fixture.profiles.setChoosesProfileByApp(true)
            fixture.profiles.addAppRule(.app(bundleID: "fixture.editor"), profileID: RefinementProfile.conciseID)
            // The press reached Airdraft while an app switch to the editor was in flight.
            fixture.frontmost = "fixture.previous"
            try await fixture.pipeline.startFromAutomation()
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Concise")
            XCTAssertEqual(target.deliveries, 1)

            // A destination whose profile needs another speech model keeps the checked one.
            var concise = fixture.profiles.profiles.first { $0.id == RefinementProfile.conciseID }!
            var bound = fixture.settings.asr
            bound.select(.parakeet)
            concise.speechModel = ProfileSpeechModel(config: bound)
            fixture.profiles.update(concise)
            try await fixture.pipeline.startFromAutomation()
            XCTAssertEqual(fixture.preflightASR?.kind, .senseVoice)
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Clean")
            XCTAssertEqual(try fixture.history.recent().first?.asrEngine, fixture.settings.asr.engineID)
        }
    }

    func testRetriesResolveCurrentRulesForTheOriginalAppEvenAfterAFailedRetry() async throws {
        // RetryResolvesCurrentRulesForTheOriginalApp
        do {
            let fixture = try RuleFixture(failSpeechOnce: true)
            defer { fixture.close() }
            fixture.profiles.setChoosesProfileByApp(true)
            let rule = fixture.profiles.addAppRule(.app(bundleID: "dev.warp.Warp"), profileID: RefinementProfile.summaryID)!
            fixture.frontmost = "dev.warp.Warp"
            try await fixture.pipeline.startFromAutomation()
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)

            // Retry runs while another app is frontmost: the recording's own app chooses.
            fixture.frontmost = "com.apple.mail"
            fixture.profiles.setProfile(RefinementProfile.conciseID, forRule: rule.id)
            fixture.pipeline.retryRecording()
            try await fixture.waitIdle()
            XCTAssertFalse(fixture.pipeline.hasRecoverableRecording)
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Concise")
        }
        // FailedRetryKeepsTheOriginalAppForTheNextRetry
        do {
            let fixture = try RuleFixture(failSpeechOnce: true)
            defer { fixture.close() }
            fixture.profiles.setChoosesProfileByApp(true)
            fixture.profiles.addAppRule(.app(bundleID: "dev.warp.Warp"), profileID: RefinementProfile.summaryID)
            fixture.frontmost = "dev.warp.Warp"
            try await fixture.pipeline.startFromAutomation()
            fixture.pipeline.stopAndProcess()
            try await fixture.waitIdle()
            await fixture.failSpeechAgain()
            fixture.frontmost = nil
            fixture.pipeline.retryRecording()
            try await fixture.waitIdle()
            XCTAssertTrue(fixture.pipeline.hasRecoverableRecording)
            fixture.pipeline.retryRecording()
            try await fixture.waitIdle()
            XCTAssertEqual(try fixture.history.recent().first?.mode, "Summary")
        }
    }

}

@MainActor
private final class RuleFixture {
    let suite = "airdraft.app-rules.\(UUID())"
    let directory: URL
    let settings: AppSettings
    let profiles: ProfileStore
    let history: HistoryStore
    let failure: RuleSpeechFailure
    var pipeline: DictationPipeline!
    var frontmost: String?
    var preflightASR: ASRConfig?
    var preflightUsesLLM: Bool?
    var onPreflight: (() -> Void)?

    init(failSpeechOnce: Bool = false, target: RuleTarget? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.asr = ASRConfig(kind: .senseVoice, language: "en")
        settings.llm = LLMConfig(kind: .claudeCode, model: "rule-refiner", minWordsForLLM: 0)
        settings.livePreviewEnabled = false
        settings.useAppContext = false
        profiles = ProfileStore(directory: directory)
        history = try HistoryStore(directory: directory)
        let failure = RuleSpeechFailure(remaining: failSpeechOnce ? 1 : 0)
        self.failure = failure
        let factory = EngineFactory(status: EngineStatus(), credentialReader: { _ in
            XCTFail("App rule tests must not read credentials"); return nil
        }, transcriberBuilder: { RuleSpeech(id: $0.engineID, failure: failure) },
           refinerBuilder: { RuleRefiner(id: $0.model) })
        pipeline = DictationPipeline(settings: settings, dictionary: DictionaryStore(directory: directory), profiles: profiles,
            history: history, factory: factory, recorder: RuleRecorder(), inserter: target?.inserter(),
            insertText: { _, _, _ in
                target?.deliveries += 1
                return InsertionResult(method: .paste, notice: nil)
            },
            recordingPreflight: { [weak self] asr, _, usesLLM, _, _ in
                self?.preflightASR = asr
                self?.preflightUsesLLM = usesLLM
                self?.onPreflight?()
            }, requestMicrophoneAccess: { true })
        pipeline.insertionEnabled = false
        pipeline.frontmostBundleID = { [weak self] in self?.frontmost }
    }

    func failSpeechAgain() async { await failure.set(1) }

    func waitIdle() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while pipeline.isBusy || pipeline.isFinishingDelivery, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(pipeline.isBusy || pipeline.isFinishingDelivery, "Injected pipeline operation did not complete")
    }

    func close() {
        pipeline.cancel()
        try? history.close()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A focused text field with a caret in one fixture app, read through an
/// injected OS boundary and a disposable pasteboard.
@MainActor
private final class RuleTarget {
    let bundleID: String
    let clipboard = NSPasteboard.withUniqueName()
    let field = AXUIElementCreateApplication(303)
    var deliveries = 0
    init(bundleID: String) { self.bundleID = bundleID }
    func close() { clipboard.releaseGlobally() }
    func inserter() -> TextInserter {
        TextInserter(environment: .init(frontmostApplication: { .init(processID: 303, bundleID: self.bundleID) },
            application: { .init(processID: $0, bundleID: self.bundleID) }, activate: { _ in false }, isTrusted: { true },
            applicationFocus: { _ in self.field }, systemFocus: { self.field }, focusedWindow: { _ in nil },
            processID: { _ in 303 }, readAttribute: { _, attribute in
                switch attribute as String {
                case kAXRoleAttribute as String: return (.success, kAXTextAreaRole as CFString)
                case kAXSelectedTextRangeAttribute as String:
                    var range = CFRange(location: 0, length: 0)
                    return (.success, AXValueCreate(.cfRange, &range))
                default: return (.attributeUnsupported, nil)
                }
            }, enableWebAccessibility: { _ in false }, postPaste: { XCTFail("Injected delivery must not post keys"); return false },
            pasteboard: clipboard))
    }
}

private actor RuleSpeechFailure {
    var remaining: Int
    init(remaining: Int) { self.remaining = remaining }
    func set(_ count: Int) { remaining = count }
    func check() throws { if remaining > 0 { remaining -= 1; throw TranscriberError.timedOut } }
}
private struct RuleSpeech: Transcriber {
    let id: String
    let failure: RuleSpeechFailure
    func prepare() async throws {}
    func transcribe(samples: [Float], hints: TranscriptionHints) async throws -> Transcript {
        try await failure.check()
        return Transcript(text: "Recorded words", engine: id, latencyMs: 0)
    }
}
private struct RuleRefiner: Refiner {
    let id: String
    func refine(_ request: RefineRequest) async throws -> RefineResult {
        RefineResult(text: request.transcript, engine: id, latencyMs: 0, promptVersion: "fixture")
    }
}
/// Unchecked: test double driven only by the MainActor pipeline under test;
/// it never touches its fields or handlers from another thread.
private final class RuleRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var levelHandler: (@Sendable (Float) -> Void)?
    var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
    func start(microphone: MicrophonePreference) throws { isRecording = true }
    func stop() -> [Float] { isRecording = false; return [Float](repeating: 0.1, count: 16_000) }
    func cancel() { isRecording = false }
}
