import XCTest
@testable import AirdraftCore

@MainActor
final class AppSettingsTests: XCTestCase {
    /// Disco and timer default off and persist across presets; Mini migrates to Classic; unreadable values fall back independently.
    func testHUDStyleTimerAndDiscoDefaultsMigrationPersistenceAndFallbacks() throws {
        // DiscoDefaultsOffAndSurvivesPresetChangesAndRestart
        do {
            try withDefaults { defaults in
                let settings = AppSettings(defaults: defaults)
                XCTAssertFalse(settings.hudDiscoEnabled)
                let timer = HUDTimerOptions(isEnabled: true, position: .left)
                settings.hudTimer = timer
                for enabled in [true, false] {
                    settings.hudDiscoEnabled = enabled
                    for style in HUDStyle.allCases {
                        settings.hudStyle = style
                        let reloaded = AppSettings(defaults: defaults)
                        XCTAssertEqual(reloaded.hudDiscoEnabled, enabled)
                        XCTAssertEqual(reloaded.hudStyle, style)
                        XCTAssertEqual(reloaded.hudTimer, timer)
                    }
                }
                defaults.set(Data("\"invalid\"".utf8), forKey: "settings.hudDiscoEnabled")
                XCTAssertFalse(AppSettings(defaults: defaults).hudDiscoEnabled)
                XCTAssertEqual(AppSettings(defaults: defaults).hudTimer, timer)
            }
        }
        // DiscoIntensityDefaultsToTheOriginalLookClampsAndSurvivesDisablingDisco
        do {
            try withDefaults { defaults in
                let settings = AppSettings(defaults: defaults)
                XCTAssertEqual(settings.hudDiscoIntensity, AppSettings.defaultDiscoIntensity)
                for (requested, expected) in [(0.8, 0.8), (1.7, 1.0), (-0.2, 0.0), (Double.nan, 0.5), (0.25, 0.25)] {
                    settings.hudDiscoIntensity = requested
                    XCTAssertEqual(settings.hudDiscoIntensity, expected)
                    XCTAssertEqual(AppSettings(defaults: defaults).hudDiscoIntensity, expected)
                }
                settings.hudDiscoEnabled = false
                XCTAssertEqual(AppSettings(defaults: defaults).hudDiscoIntensity, 0.25, "Turning Disco off keeps its intensity")
                defaults.set(try JSONEncoder().encode(4.0), forKey: "settings.hudDiscoIntensity")
                XCTAssertEqual(AppSettings(defaults: defaults).hudDiscoIntensity, 1)
                defaults.set(Data("\"invalid\"".utf8), forKey: "settings.hudDiscoIntensity")
                XCTAssertEqual(AppSettings(defaults: defaults).hudDiscoIntensity, AppSettings.defaultDiscoIntensity)
            }
        }
        // ClassicIsDefaultAndMiniMigratesWithoutChangingTimerPreferences
        do {
            try withDefaults { defaults in
                XCTAssertEqual(AppSettings(defaults: defaults).hudStyle, .classic)
                XCTAssertFalse(HUDStyle.allCases.map(\.rawValue).contains("mini"))
                for savedStyle in ["mini", "classic"] {
                    for enabled in [false, true] {
                        for position in HUDTimerOptions.Position.allCases {
                            let timer = HUDTimerOptions(isEnabled: enabled, position: position)
                            AppSettings(defaults: defaults).hudTimer = timer
                            defaults.set(try JSONEncoder().encode(savedStyle), forKey: "settings.hudStyle")
                            let migrated = AppSettings(defaults: defaults)
                            XCTAssertEqual(migrated.hudStyle, .classic)
                            XCTAssertEqual(migrated.hudTimer, timer)
                            let saved = try XCTUnwrap(defaults.data(forKey: "settings.hudStyle"))
                            XCTAssertEqual(try JSONDecoder().decode(String.self, from: saved), "classic")
                            XCTAssertEqual(AppSettings(defaults: defaults).hudTimer, timer)
                        }
                    }
                }
            }
        }
        // HUDTimerDefaultsOffWithoutChangingExistingPreset
        do {
            try withDefaults { defaults in
                XCTAssertEqual(AppSettings(defaults: defaults).hudTimer, HUDTimerOptions())
                for style in HUDStyle.allCases {
                    AppSettings(defaults: defaults).hudStyle = style
                    let reloaded = AppSettings(defaults: defaults)
                    XCTAssertFalse(reloaded.hudTimer.isEnabled)
                    XCTAssertEqual(reloaded.hudTimer.position, .right)
                    XCTAssertEqual(reloaded.hudStyle, style)
                }
            }
        }
        // HUDTimerPersistsAcrossPresetsAndRemembersPositionWhenDisabled
        do {
            try withDefaults { defaults in
                let settings = AppSettings(defaults: defaults)
                for position in HUDTimerOptions.Position.allCases {
                    settings.hudTimer.position = position
                    for enabled in [true, false] {
                        settings.hudTimer.isEnabled = enabled
                        for style in HUDStyle.allCases {
                            settings.hudStyle = style
                            let reloaded = AppSettings(defaults: defaults)
                            XCTAssertEqual(reloaded.hudTimer, HUDTimerOptions(isEnabled: enabled, position: position))
                            XCTAssertEqual(reloaded.hudStyle, style)
                        }
                    }
                }
            }
        }
        // UnreadableHUDTimerFallsBackIndependently
        do {
            try withDefaults { defaults in
                AppSettings(defaults: defaults).hudStyle = .sonic
                for value in ["bad", #"{"isEnabled":true,"position":"removed"}"#] {
                    defaults.set(Data(value.utf8), forKey: "settings.hudTimer")
                    let settings = AppSettings(defaults: defaults)
                    XCTAssertEqual(settings.hudTimer, HUDTimerOptions())
                    XCTAssertEqual(settings.hudStyle, .sonic)
                }
            }
        }
    }

    func testAppIconsAndTextSizeDefaultPersistAndFallBackIndependently() throws {
        // AppIconsDefaultByThemeForNewAndExistingSettings
        do {
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
        // AppIconChoicesPersistIndependentlyAcrossEveryCombination
        do {
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
        // UnreadableAppIconPreferencesFallBackWithoutResettingOtherSettings
        do {
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
        // TextSizeDefaultsToStandardPersistsAndIgnoresUnknownValues
        do {
            try withDefaults { defaults in
                XCTAssertEqual(AppSettings(defaults: defaults).textSize, .standard)
                XCTAssertEqual(TextSizePreference.standard.scale, 1)
                XCTAssertEqual(TextSizePreference.allCases.map(\.scale), [1, 1.12, 1.24])
                for size in TextSizePreference.allCases {
                    let settings = AppSettings(defaults: defaults)
                    settings.textSize = size
                    XCTAssertEqual(AppSettings(defaults: defaults).textSize, size)
                }
                AppSettings(defaults: defaults).appearance = .dark
                defaults.set(Data("\"huge\"".utf8), forKey: "settings.textSize")
                let reloaded = AppSettings(defaults: defaults)
                XCTAssertEqual(reloaded.textSize, .standard)
                XCTAssertEqual(reloaded.appearance, .dark)
            }
        }
    }

    /// Trigger delay, recording limit (saved and programmatic), idle unload and audio retention cutoffs.
    func testNumericSettingsDefaultsClampingPersistenceAndRetentionCutoffs() throws {
        // TriggerDelayDefaultsOffPersistsAndClamps
        do {
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
        // RecordingLimitDefaultsToTenMinutesClampsSavedValuesAndPersistsMigration
        do {
            try withDefaults { defaults in
                XCTAssertEqual(AppSettings(defaults: defaults).maxRecordingSeconds, 600)
                for (saved, expected) in [(1_800, 600), (601, 600), (600, 600), (300, 300), (10, 10), (0, 10)] {
                    defaults.set(try JSONEncoder().encode(saved), forKey: "settings.maxRecordingSeconds")
                    XCTAssertEqual(AppSettings(defaults: defaults).maxRecordingSeconds, expected)
                    let data = try XCTUnwrap(defaults.data(forKey: "settings.maxRecordingSeconds"))
                    XCTAssertEqual(try JSONDecoder().decode(Int.self, from: data), expected)
                }
            }
        }
        // RecordingLimitClampsProgrammaticChangesBeforeReload
        do {
            try withDefaults { defaults in
                let settings = AppSettings(defaults: defaults)
                for (requested, expected) in [(Int.max, 600), (600, 600), (120, 120), (Int.min, 10)] {
                    settings.maxRecordingSeconds = requested
                    XCTAssertEqual(settings.maxRecordingSeconds, expected)
                    XCTAssertEqual(AppSettings(defaults: defaults).maxRecordingSeconds, expected)
                }
            }
        }
        // IdleUnloadDefaultsToThirtyMinutesAndPreservesUserChoices
        do {
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
        // AudioRetentionCutoffs
        do {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            XCTAssertNil(AudioRetention.off.cutoff(now: now))
            XCTAssertEqual(AudioRetention.day.cutoff(now: now), now.addingTimeInterval(-86_400))
            XCTAssertEqual(AudioRetention.week.cutoff(now: now), now.addingTimeInterval(-604_800))
            XCTAssertEqual(AudioRetention.month.cutoff(now: now), now.addingTimeInterval(-2_592_000))
            XCTAssertEqual(AudioRetention.forever.cutoff(now: now), .distantPast)
        }
    }

    func testGeneralSettingsRoundTripFallBackIndependentlyAndKeepSpeechAndRefinementSeparate() throws {
        // EveryGeneralSettingSurvivesReload
        do {
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
        // AllAppearanceHUDRetentionAndInteractionChoicesRoundTrip
        do {
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
        // CorruptAndUnknownSettingsFallBackIndependently
        do {
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
        // LocalSpeechAndRefinementSelectionsRemainIndependent
        do {
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
    }

    func testChineseScriptDefaultsFollowTheSystemLanguageWithoutRewritingSavedChoices() throws {
        // ChineseScriptDefaultFollowsTheFirstChineseSystemLanguage
        do {
            for languages in [["zh-Hans-CN"], ["zh-Hans"], ["en-US", "zh-Hans-SG"], ["zh-CN"], ["zh_CN"], ["zh-SG"], ["zh"]] {
                XCTAssertEqual(ChineseScript.systemDefault(preferredLanguages: languages), .simplified, "\(languages)")
            }
            for languages in [["zh-Hant-TW"], ["zh-Hant"], ["zh-TW"], ["zh-HK"], ["en-TW", "zh-Hant-TW", "zh-Hans-CN"],
                              ["ja-JP", "zh-Hant-TW"]] {
                XCTAssertEqual(ChineseScript.systemDefault(preferredLanguages: languages), .traditional, "\(languages)")
            }
            // Macs without a Chinese language keep every other script untouched: Japanese
            // kanji, Korean hanja, and no Chinese rule in other languages' prompts.
            for languages in [["ja-JP"], ["ja-JP", "fr-FR"], ["ko-KR"], ["ko", "en-US"], ["en-US"], ["fr-FR", "ja-JP"],
                              ["es-419"], ["ar-SA"], []] {
                XCTAssertEqual(ChineseScript.systemDefault(preferredLanguages: languages), .auto, "\(languages)")
            }
            // Only Mandarin, Cantonese and Auto apply the saved script.
            for (language, script) in [("ja", ChineseScript.auto), ("ja-JP", .auto), ("ko", .auto), ("zh", .traditional),
                                       ("zh-TW", .traditional), ("yue", .traditional), ("", .traditional), ("en", .auto),
                                       ("es", .auto), ("hi", .auto)] {
                XCTAssertEqual(ASRConfig(language: language, chineseScript: .traditional).effectiveChineseScript, script, language)
            }
            XCTAssertEqual(ChineseScript.simplified.appleMandarinLocale, "zh-CN")
            XCTAssertEqual(ChineseScript.traditional.appleMandarinLocale, "zh-TW")
            // The plain initializer and old settings blobs keep their fixed Traditional defaults.
            XCTAssertEqual(ASRConfig().chineseScript, .traditional)
            XCTAssertEqual(ASRConfig().appleLocale, "zh-TW")
        }
        // NewSetupOnSimplifiedChineseSystemDefaultsToSimplifiedWithoutRewritingSavedChoices
        do {
            try withDefaults { defaults in
                let simplified = AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"])
                XCTAssertEqual(simplified.asr.chineseScript, .simplified)
                XCTAssertEqual(simplified.asr.appleLocale, "zh-CN")
                XCTAssertEqual(simplified.livePreviewLocale, "zh-CN")
                XCTAssertNil(defaults.object(forKey: "settings.asr"), "Defaults are not written until the user changes them")
                XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["zh-Hant-TW"]).asr.chineseScript, .traditional)
                XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["en-US"]).livePreviewLocale, "en-US")

                // A saved choice wins over the system language in both directions.
                AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]).asr.chineseScript = .traditional
                AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]).livePreviewLocale = "zh-TW"
                let reloaded = AppSettings(defaults: defaults, preferredLanguages: ["zh-Hans-CN"])
                XCTAssertEqual(reloaded.asr.chineseScript, .traditional)
                XCTAssertEqual(reloaded.livePreviewLocale, "zh-TW")
                reloaded.asr.chineseScript = .simplified
                XCTAssertEqual(AppSettings(defaults: defaults, preferredLanguages: ["zh-Hant-TW"]).asr.chineseScript, .simplified)
            }
        }
    }

    /// AD-124: pinned speech models persist by ID, never count as an existing
    /// setup, and Reset All's preference reset removes them.
    func testPinnedSpeechModelsPersistWithoutCountingAsSetupAndResetClearsThem() throws {
        let name = "airdraft-settings-fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.pinnedSpeechModels, [])
        settings.setSpeechModel("sherpa:parakeet", pinned: true)
        settings.setSpeechModel("groq/whisper-large-v3-turbo", pinned: true)
        settings.setSpeechModel("unknown-model", pinned: true)
        settings.setSpeechModel("unknown-model", pinned: false)
        settings.setSpeechModel("never-pinned", pinned: false)

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.pinnedSpeechModels, ["sherpa:parakeet", "groq/whisper-large-v3-turbo"])
        XCTAssertFalse(reopened.hadExistingSetup, "Pins are a view preference, not a setup")
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("settings.") })

        AppResetAdapters.resetPreferences(in: defaults, domains: [name])
        XCTAssertEqual(AppSettings(defaults: defaults).pinnedSpeechModels, [])
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "airdraft-settings-fixture-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
