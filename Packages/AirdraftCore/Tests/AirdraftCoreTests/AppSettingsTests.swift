import XCTest
@testable import AirdraftCore

@MainActor
final class AppSettingsTests: XCTestCase {
    func testAppIconsDefaultByThemeForNewAndExistingSettings() throws {
        try withDefaults { defaults in
            XCTAssertEqual(AppSettings(defaults: defaults).appIcons.light, .carvedWave)
            XCTAssertEqual(AppSettings(defaults: defaults).appIcons.dark, .nightWave)
            let existing = AppSettings(defaults: defaults)
            existing.appearance = .dark
            existing.maxRecordingSeconds = 120
            let reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.appIcons, AppIconPreferences())
            XCTAssertEqual(reloaded.appearance, .dark)
            XCTAssertEqual(reloaded.maxRecordingSeconds, 120)
        }
    }

    func testAppIconChoicesPersistIndependentlyAcrossEveryCombination() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            for light in AppIconStyle.allCases {
                for dark in AppIconStyle.allCases {
                    settings.appIcons.light = light
                    settings.appIcons.dark = dark
                    let reloaded = AppSettings(defaults: defaults)
                    XCTAssertEqual(reloaded.appIcons.icon(isDark: false), light)
                    XCTAssertEqual(reloaded.appIcons.icon(isDark: true), dark)
                    XCTAssertEqual(reloaded.appearance, .auto)
                }
            }
        }
    }

    func testUnreadableAppIconPreferencesFallBackWithoutResettingOtherSettings() throws {
        try withDefaults { defaults in
            AppSettings(defaults: defaults).appearance = .light
            for value in ["bad", #"{"light":"removedIcon","dark":"nightWave"}"#] {
                defaults.set(Data(value.utf8), forKey: "settings.appIcons")
                let settings = AppSettings(defaults: defaults)
                XCTAssertEqual(settings.appIcons, AppIconPreferences())
                XCTAssertEqual(settings.appearance, .light)
            }
        }
    }

    func testTriggerDelayDefaultsOffPersistsAndClamps() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.triggerDelayMilliseconds, 0)
            for (input, expected) in [(350, 350), (-1, 0), (2000, 1000), (0, 0)] {
                settings.triggerDelayMilliseconds = input
                XCTAssertEqual(settings.triggerDelayMilliseconds, expected)
                XCTAssertEqual(AppSettings(defaults: defaults).triggerDelayMilliseconds, expected)
            }
            defaults.set(try JSONEncoder().encode(-500), forKey: "settings.triggerDelayMilliseconds")
            XCTAssertEqual(AppSettings(defaults: defaults).triggerDelayMilliseconds, 0)
            defaults.set(try JSONEncoder().encode(10_000), forKey: "settings.triggerDelayMilliseconds")
            XCTAssertEqual(AppSettings(defaults: defaults).triggerDelayMilliseconds, 1000)
            defaults.set(Data("bad".utf8), forKey: "settings.triggerDelayMilliseconds")
            XCTAssertEqual(AppSettings(defaults: defaults).triggerDelayMilliseconds, 0)
        }
    }

    func testRecordingLimitClampsSavedValuesAndPersistsMigration() throws {
        try withDefaults { defaults in
            XCTAssertEqual(AppSettings(defaults: defaults).maxRecordingSeconds, 300)
            for (saved, expected) in [(1_800, 600), (601, 600), (600, 600), (300, 300), (10, 10), (0, 10)] {
                defaults.set(try JSONEncoder().encode(saved), forKey: "settings.maxRecordingSeconds")
                XCTAssertEqual(AppSettings(defaults: defaults).maxRecordingSeconds, expected)
                let data = try XCTUnwrap(defaults.data(forKey: "settings.maxRecordingSeconds"))
                XCTAssertEqual(try JSONDecoder().decode(Int.self, from: data), expected)
            }
        }
    }

    func testRecordingLimitClampsProgrammaticChangesBeforeReload() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            for (requested, expected) in [(Int.max, 600), (600, 600), (120, 120), (Int.min, 10)] {
                settings.maxRecordingSeconds = requested
                XCTAssertEqual(settings.maxRecordingSeconds, expected)
                XCTAssertEqual(AppSettings(defaults: defaults).maxRecordingSeconds, expected)
            }
        }
    }

    func testIdleUnloadDefaultsToThirtyMinutesAndPreservesUserChoices() throws {
        try withDefaults { defaults in
            XCTAssertEqual(AppSettings(defaults: defaults).idleUnloadMinutes, 30)
            // Existing installations without an explicit choice get the new default.
            let settings = AppSettings(defaults: defaults)
            settings.appearance = .dark
            XCTAssertEqual(AppSettings(defaults: defaults).idleUnloadMinutes, 30)
            for minutes in [5, 10, 30, 0] {
                settings.idleUnloadMinutes = minutes
                XCTAssertEqual(AppSettings(defaults: defaults).idleUnloadMinutes, minutes)
            }
        }
    }

    func testEveryGeneralSettingSurvivesReload() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.hotkey = .optionSpace
            settings.hotkeyBehavior = .toggle
            settings.insertionMethod = .paste
            settings.outputDestination = .script
            settings.outputScriptPath = "/tmp/a script with spaces"
            settings.useAppContext = false
            settings.maxRecordingSeconds = 600
            settings.appearance = .dark
            settings.idleUnloadMinutes = 0
            settings.unloadLLMOnQuit = false
            settings.hudStyle = .none
            settings.livePreviewEnabled = true
            settings.livePreviewLocale = "en-US"
            settings.audioRetention = .forever
            let reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.hotkey, .optionSpace)
            XCTAssertEqual(reloaded.hotkeyBehavior, .toggle)
            XCTAssertEqual(reloaded.insertionMethod, .paste)
            XCTAssertEqual(reloaded.outputDestination, .script)
            XCTAssertEqual(reloaded.outputScriptPath, "/tmp/a script with spaces")
            XCTAssertFalse(reloaded.useAppContext)
            XCTAssertEqual(reloaded.maxRecordingSeconds, 600)
            XCTAssertEqual(reloaded.appearance, .dark)
            XCTAssertEqual(reloaded.idleUnloadMinutes, 0)
            XCTAssertFalse(reloaded.unloadLLMOnQuit)
            XCTAssertEqual(reloaded.hudStyle, .none)
            XCTAssertTrue(reloaded.livePreviewEnabled)
            XCTAssertEqual(reloaded.livePreviewLocale, "en-US")
            XCTAssertEqual(reloaded.audioRetention, .forever)
        }
    }

    func testAllAppearanceHUDRetentionAndInteractionChoicesRoundTrip() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            for value in AppearanceMode.allCases {
                settings.appearance = value
                XCTAssertEqual(AppSettings(defaults: defaults).appearance, value)
            }
            for value in HUDStyle.allCases {
                settings.hudStyle = value
                XCTAssertEqual(AppSettings(defaults: defaults).hudStyle, value)
            }
            for value in AudioRetention.allCases {
                settings.audioRetention = value
                XCTAssertEqual(AppSettings(defaults: defaults).audioRetention, value)
            }
            for value in HotkeyBehavior.allCases {
                settings.hotkeyBehavior = value
                XCTAssertEqual(AppSettings(defaults: defaults).hotkeyBehavior, value)
            }
            for value in InsertionMethod.allCases {
                settings.insertionMethod = value
                XCTAssertEqual(AppSettings(defaults: defaults).insertionMethod, value)
            }
            for value in TextOutputDestination.allCases {
                settings.outputDestination = value
                XCTAssertEqual(AppSettings(defaults: defaults).outputDestination, value)
            }
        }
    }

    func testCorruptAndUnknownSettingsFallBackIndependently() throws {
        try withDefaults { defaults in
            let original = AppSettings(defaults: defaults)
            original.maxRecordingSeconds = 600
            original.appearance = .light
            defaults.set(Data("not JSON".utf8), forKey: "settings.hotkey")
            defaults.set(Data("\"unknown-hud\"".utf8), forKey: "settings.hudStyle")
            defaults.set("wrong storage type", forKey: "settings.livePreviewEnabled")
            let reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.hotkey, .controlOption)
            XCTAssertEqual(reloaded.hudStyle, .classic)
            XCTAssertFalse(reloaded.livePreviewEnabled)
            XCTAssertEqual(reloaded.maxRecordingSeconds, 600)
            XCTAssertEqual(reloaded.appearance, .light)
        }
    }

    func testLocalSpeechAndRefinementSelectionsRemainIndependent() throws {
        try withDefaults { defaults in
            let settings = AppSettings(defaults: defaults)
            settings.asr = ASRConfig(kind: .qwen3, qwen3Model: "fixture/qwen-small", language: "en", chineseScript: .auto)
            settings.llm = LLMConfig(kind: .openAICompatible, baseURL: "http://localhost:1234/v1", model: "local-fixture", timeoutSeconds: 45, minWordsForLLM: 7)
            let speech = settings.asr
            settings.llm.select(.appleIntelligence)
            XCTAssertEqual(settings.asr, speech)
            settings.llm.select(.none)
            settings.llm.select(.openAICompatible)
            XCTAssertEqual(settings.llm.model, "local-fixture")
            settings.asr.kind = .senseVoice
            let reloaded = AppSettings(defaults: defaults)
            XCTAssertEqual(reloaded.asr.kind, .senseVoice)
            XCTAssertEqual(reloaded.asr.qwen3Model, "fixture/qwen-small")
            XCTAssertEqual(reloaded.llm.kind, .openAICompatible)
            XCTAssertEqual(reloaded.llm.model, "local-fixture")
            XCTAssertEqual(reloaded.llm.timeoutSeconds, 45)
            XCTAssertEqual(reloaded.llm.minWordsForLLM, 7)
        }
    }

    func testAudioRetentionCutoffs() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(AudioRetention.off.cutoff(now: now))
        XCTAssertEqual(AudioRetention.day.cutoff(now: now), now.addingTimeInterval(-86_400))
        XCTAssertEqual(AudioRetention.week.cutoff(now: now), now.addingTimeInterval(-604_800))
        XCTAssertEqual(AudioRetention.month.cutoff(now: now), now.addingTimeInterval(-2_592_000))
        XCTAssertEqual(AudioRetention.forever.cutoff(now: now), .distantPast)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "airdraft-settings-fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
