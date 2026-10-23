import Foundation
import Observation

public enum HotkeyBehavior: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Hold to record, release to transcribe.
    case hold
    /// Press to start, press again to stop.
    case toggle
    public var id: String { rawValue }
    /// Verb for instructions shown next to the shortcut: "Hold ⌃ ⌥ and speak".
    public var instructionVerb: String { self == .hold ? String(localized: "Hold", bundle: .module) : String(localized: "Press", bundle: .module) }
    public func instructionVerb(triggerDelayMilliseconds: Int) -> String {
        triggerDelayMilliseconds > 0 ? String(localized: "Hold", bundle: .module) : instructionVerb
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: return String(localized: "Auto", bundle: .module)
        case .light: return String(localized: "Light", bundle: .module)
        case .dark: return String(localized: "Dark", bundle: .module)
        }
    }
}

/// Interface text size. macOS gives SwiftUI no Dynamic Type for most text, so the
/// app scales its shared typography tokens itself. Titles are localized by the app.
public enum TextSizePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case standard, large, larger
    public var id: String { rawValue }
    /// Multiplier for every shared text style; `standard` keeps the design sizes.
    public var scale: Double {
        switch self {
        case .standard: return 1
        case .large: return 1.12
        case .larger: return 1.24
        }
    }
}

public enum HUDStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The original scrolling waveform.
    case classic
    /// Audio-reactive, faceted rotating cube.
    case cube
    /// Flowing sonic ribbons.
    case sonic
    /// Interlocking silver gyroscope rings.
    case orbit
    /// A folded metallic ribbon.
    case silk
    /// No recording window.
    case none
    public var id: String { rawValue }
    public static var visibleStyles: [Self] { allCases.filter { $0 != .none } }
    public var title: String {
        switch self {
        case .classic: return String(localized: "Classic", bundle: .module)
        case .cube: return String(localized: "Cube", bundle: .module)
        case .sonic: return String(localized: "Sonic", bundle: .module)
        case .orbit: return String(localized: "Orbit", bundle: .module)
        case .silk: return String(localized: "Silk", bundle: .module)
        case .none: return String(localized: "None", bundle: .module)
        }
    }
}

public enum TextOutputDestination: String, Codable, CaseIterable, Sendable, Identifiable {
    case cursor, script
    public var id: String { rawValue }
    public var title: String { self == .cursor ? String(localized: "Insert at cursor", bundle: .module) : String(localized: "Send to script", bundle: .module) }
}

/// Audio retention is independent of text history; Off also removes saved audio.
public enum AudioRetention: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, day, week, month, forever
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return String(localized: "Off", bundle: .module)
        case .day: return String(localized: "1 day", bundle: .module)
        case .week: return String(localized: "7 days", bundle: .module)
        case .month: return String(localized: "30 days", bundle: .module)
        case .forever: return String(localized: "Until deleted", bundle: .module)
        }
    }
    public func cutoff(now: Date = Date()) -> Date? {
        switch self {
        case .off: return nil
        case .day: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return now.addingTimeInterval(-30 * 86_400)
        case .forever: return .distantPast
        }
    }
}

/// UserDefaults-backed settings. Secrets live in Keychain, not here.
@MainActor
@Observable
public final class AppSettings {
    public let hadExistingSetup: Bool
    public let onboarding: OnboardingProgress
    public private(set) var isOnboardingPractice = false
    public var asr: ASRConfig { didSet { persist("asr", asr) } }
    public var llm: LLMConfig { didSet { persist("llm", llm) } }
    public var hotkey: Hotkey { didSet { persist("hotkey", hotkey) } }
    public var hotkeyBehavior: HotkeyBehavior { didSet { persist("hotkeyBehavior", hotkeyBehavior) } }
    /// Minimum hold before a shortcut starts dictation. Zero disables the gate.
    public var triggerDelayMilliseconds: Int {
        didSet {
            let clamped = HotkeyTriggerState.clampedDelay(triggerDelayMilliseconds)
            if triggerDelayMilliseconds != clamped {
                triggerDelayMilliseconds = clamped
                return
            }
            persist("triggerDelayMilliseconds", triggerDelayMilliseconds)
        }
    }
    public var insertionMethod: InsertionMethod { didSet { persist("insertionMethod", insertionMethod) } }
    public var outputDestination: TextOutputDestination { didSet { persist("outputDestination", outputDestination) } }
    public var outputScriptPath: String { didSet { persist("outputScriptPath", outputScriptPath) } }
    public var useAppContext: Bool { didSet { persist("useAppContext", useAppContext) } }
    /// AD-081: offer Vocabulary terms to on-device speech models that support
    /// biasing. Cloud keyword fields always receive them.
    public var vocabularyBiasesOnDeviceSpeech: Bool {
        didSet { persist("vocabularyBiasesOnDeviceSpeech", vocabularyBiasesOnDeviceSpeech) }
    }
    public var maxRecordingSeconds: Int {
        didSet {
            let clamped = SpeechInputLimits.clampedRecordingSeconds(maxRecordingSeconds)
            if maxRecordingSeconds != clamped {
                maxRecordingSeconds = clamped
                return
            }
            persist("maxRecordingSeconds", maxRecordingSeconds)
        }
    }
    public var appearance: AppearanceMode { didSet { persist("appearance", appearance) } }
    public var appIcons: AppIconPreferences { didSet { persist("appIcons", appIcons) } }
    public var textSize: TextSizePreference { didSet { persist("textSize", textSize) } }
    /// Unload local speech models after this many idle minutes. 0 = keep loaded.
    public var idleUnloadMinutes: Int { didSet { persist("idleUnloadMinutes", idleUnloadMinutes) } }
    /// Ask LM Studio to unload the LLM when the app quits.
    public var unloadLLMOnQuit: Bool { didSet { persist("unloadLLMOnQuit", unloadLLMOnQuit) } }
    public var hudStyle: HUDStyle { didSet { persist("hudStyle", hudStyle) } }
    public var hudDiscoEnabled: Bool { didSet { persist("hudDiscoEnabled", hudDiscoEnabled) } }
    public var hudTimer: HUDTimerOptions { didSet { persist("hudTimer", hudTimer) } }
    public var livePreviewEnabled: Bool { didSet { persist("livePreviewEnabled", livePreviewEnabled) } }
    public var livePreviewLocale: String { didSet { persist("livePreviewLocale", livePreviewLocale) } }
    public var audioRetention: AudioRetention { didSet { persist("audioRetention", audioRetention) } }
    public var microphone: MicrophonePreference { didSet { persist("microphone", microphone) } }
    /// The last template chosen from a meeting transcript's Summarize menu.
    public var meetingSummaryTemplate: MeetingSummaryTemplate { didSet { persist("meetingSummaryTemplate", meetingSummaryTemplate) } }
    /// AD-071: Models lists the whole local catalogue instead of the compact
    /// recommended set. A view preference, kept outside the `settings.` keys so
    /// it never counts as an existing setup.
    public var showsAllLocalModels: Bool {
        didSet { defaults.set(showsAllLocalModels, forKey: Self.showsAllLocalModelsKey) }
    }
    static let showsAllLocalModelsKey = "models.showsAllLocalModels"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard, Bundle.main.bundleIdentifier == AppIdentity.bundleID {
            AppIdentity.importLegacyDefaults(into: defaults,
                legacy: defaults.persistentDomain(forName: AppIdentity.legacyBundleID) ?? [:])
        }
        let existingSetup = defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("settings.") }
        hadExistingSetup = existingSetup
        onboarding = OnboardingProgress(defaults: defaults, existingSetup: existingSetup)
        asr = Self.load("asr", from: defaults) ?? ASRConfig()
        llm = Self.load("llm", from: defaults) ?? LLMConfig()
        hotkey = Self.load("hotkey", from: defaults) ?? .controlOption
        hotkeyBehavior = Self.load("hotkeyBehavior", from: defaults) ?? .hold
        triggerDelayMilliseconds = HotkeyTriggerState.clampedDelay(
            Self.load("triggerDelayMilliseconds", from: defaults) ?? 0)
        insertionMethod = Self.load("insertionMethod", from: defaults) ?? .auto
        outputDestination = Self.load("outputDestination", from: defaults) ?? .cursor
        outputScriptPath = Self.load("outputScriptPath", from: defaults) ?? ""
        useAppContext = Self.load("useAppContext", from: defaults) ?? false
        vocabularyBiasesOnDeviceSpeech = Self.load("vocabularyBiasesOnDeviceSpeech", from: defaults) ?? true
        let savedRecordingSeconds: Int = Self.load("maxRecordingSeconds", from: defaults) ?? 300
        maxRecordingSeconds = SpeechInputLimits.clampedRecordingSeconds(savedRecordingSeconds)
        appearance = Self.load("appearance", from: defaults) ?? .auto
        appIcons = Self.load("appIcons", from: defaults) ?? AppIconPreferences()
        textSize = Self.load("textSize", from: defaults) ?? .standard
        idleUnloadMinutes = Self.load("idleUnloadMinutes", from: defaults) ?? 30
        unloadLLMOnQuit = Self.load("unloadLLMOnQuit", from: defaults) ?? true
        let savedHUDStyle: String? = Self.load("hudStyle", from: defaults)
        hudStyle = savedHUDStyle.flatMap(HUDStyle.init(rawValue:)) ?? .classic
        hudDiscoEnabled = Self.load("hudDiscoEnabled", from: defaults) ?? false
        hudTimer = Self.load("hudTimer", from: defaults) ?? HUDTimerOptions()
        livePreviewEnabled = Self.load("livePreviewEnabled", from: defaults) ?? false
        livePreviewLocale = Self.load("livePreviewLocale", from: defaults) ?? "zh-TW"
        audioRetention = Self.load("audioRetention", from: defaults) ?? .off
        microphone = Self.load("microphone", from: defaults) ?? .systemDefault
        meetingSummaryTemplate = Self.load("meetingSummaryTemplate", from: defaults) ?? .default
        showsAllLocalModels = defaults.bool(forKey: Self.showsAllLocalModelsKey)
        if savedHUDStyle == "mini" {
            persist("hudStyle", hudStyle)
        }
        if maxRecordingSeconds != savedRecordingSeconds {
            persist("maxRecordingSeconds", maxRecordingSeconds)
        }
        endOnboardingPractice()
    }

    private struct PracticeSettings: Codable {
        var llm: LLMConfig
        var output: TextOutputDestination
    }

    private var practiceRestore: PracticeSettings? {
        defaults.data(forKey: "onboarding.restore").flatMap { try? JSONDecoder().decode(PracticeSettings.self, from: $0) }
    }

    /// Keep returning users' setup, including script destinations, recoverable
    /// even if the app quits during the exercise. New users keep the basic setup.
    public func beginOnboardingPractice() {
        if (hadExistingSetup || onboarding.hasBeenDismissed), defaults.data(forKey: "onboarding.restore") == nil,
           let data = try? JSONEncoder().encode(PracticeSettings(llm: llm, output: outputDestination)) {
            defaults.set(data, forKey: "onboarding.restore")
        }
        llm.select(.none)
        outputDestination = .cursor
        isOnboardingPractice = true
    }

    public func endOnboardingPractice() {
        isOnboardingPractice = false
        guard let saved = practiceRestore else { return }
        llm = saved.llm
        outputDestination = saved.output
        defaults.removeObject(forKey: "onboarding.restore")
    }

    /// Setup's one-click refinement choice is the user's own saved setting. Practice
    /// keeps its raw transcript, so a choice made while it runs is applied when
    /// practice ends, including after a restart, instead of being overwritten.
    public func chooseRefinement(_ kind: LLMProviderKind) {
        guard isOnboardingPractice else {
            llm.select(kind)
            return
        }
        var saved = practiceRestore ?? PracticeSettings(llm: llm, output: outputDestination)
        saved.llm.select(kind)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "onboarding.restore") }
    }

    /// Practice uses its explicitly chosen speech setup without changing the
    /// saved profile. Every consumer resolves the same temporary override.
    public func effectiveProfile(_ profile: RefinementProfile) -> RefinementProfile {
        guard isOnboardingPractice else { return profile }
        var practice = profile
        practice.speechModel = nil
        practice.usesLLM = false
        return practice
    }

    public func speechConfig(for profile: RefinementProfile) -> ASRConfig {
        effectiveProfile(profile).speechConfig(default: asr)
    }

    public nonisolated static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Keep the existing directory for downloaded models, history, dictionary and profiles.
        return base.appendingPathComponent("Transcribar", isDirectory: true)
    }

    private func persist<T: Encodable>(_ key: String, _ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "settings.\(key)")
    }

    private static func load<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: "settings.\(key)") else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
