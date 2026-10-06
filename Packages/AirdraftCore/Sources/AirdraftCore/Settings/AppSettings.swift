import Foundation
import Observation

public enum HotkeyBehavior: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Hold to record, release to transcribe.
    case hold
    /// Press to start, press again to stop.
    case toggle
    public var id: String { rawValue }
    /// Verb for instructions shown next to the shortcut: "Hold ⌃ ⌥ and speak".
    public var instructionVerb: String { self == .hold ? "Hold" : "Press" }
    public func instructionVerb(triggerDelayMilliseconds: Int) -> String {
        triggerDelayMilliseconds > 0 ? "Hold" : instructionVerb
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum HUDStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Waveform plus elapsed time.
    case classic
    /// Waveform only.
    case mini
    /// Audio-reactive, faceted rotating cube plus elapsed time.
    case cube
    /// Flowing sonic ribbons through a spatial cube plus elapsed time.
    case sonic
    /// No recording window.
    case none
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .mini: return "Mini"
        case .cube: return "Cube"
        case .sonic: return "Sonic"
        case .none: return "None"
        }
    }
}

public enum TextOutputDestination: String, Codable, CaseIterable, Sendable, Identifiable {
    case cursor, script
    public var id: String { rawValue }
    public var title: String { self == .cursor ? "Insert at cursor" : "Send to script" }
}

/// Audio retention is independent of text history; Off also removes saved audio.
public enum AudioRetention: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, day, week, month, forever
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .day: return "1 day"
        case .week: return "7 days"
        case .month: return "30 days"
        case .forever: return "Until deleted"
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
    /// Unload local speech models after this many idle minutes. 0 = keep loaded.
    public var idleUnloadMinutes: Int { didSet { persist("idleUnloadMinutes", idleUnloadMinutes) } }
    /// Ask LM Studio to unload the LLM when the app quits.
    public var unloadLLMOnQuit: Bool { didSet { persist("unloadLLMOnQuit", unloadLLMOnQuit) } }
    public var hudStyle: HUDStyle { didSet { persist("hudStyle", hudStyle) } }
    public var livePreviewEnabled: Bool { didSet { persist("livePreviewEnabled", livePreviewEnabled) } }
    public var livePreviewLocale: String { didSet { persist("livePreviewLocale", livePreviewLocale) } }
    public var audioRetention: AudioRetention { didSet { persist("audioRetention", audioRetention) } }
    public var microphone: MicrophonePreference { didSet { persist("microphone", microphone) } }

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
        let savedRecordingSeconds: Int = Self.load("maxRecordingSeconds", from: defaults) ?? 300
        maxRecordingSeconds = SpeechInputLimits.clampedRecordingSeconds(savedRecordingSeconds)
        appearance = Self.load("appearance", from: defaults) ?? .auto
        appIcons = Self.load("appIcons", from: defaults) ?? AppIconPreferences()
        idleUnloadMinutes = Self.load("idleUnloadMinutes", from: defaults) ?? 30
        unloadLLMOnQuit = Self.load("unloadLLMOnQuit", from: defaults) ?? true
        hudStyle = Self.load("hudStyle", from: defaults) ?? .classic
        livePreviewEnabled = Self.load("livePreviewEnabled", from: defaults) ?? false
        livePreviewLocale = Self.load("livePreviewLocale", from: defaults) ?? "zh-TW"
        audioRetention = Self.load("audioRetention", from: defaults) ?? .off
        microphone = Self.load("microphone", from: defaults) ?? .systemDefault
        if maxRecordingSeconds != savedRecordingSeconds {
            persist("maxRecordingSeconds", maxRecordingSeconds)
        }
        endOnboardingPractice()
    }

    private struct PracticeSettings: Codable {
        let llm: LLMConfig
        let output: TextOutputDestination
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
    }

    public func endOnboardingPractice() {
        guard let data = defaults.data(forKey: "onboarding.restore"),
              let saved = try? JSONDecoder().decode(PracticeSettings.self, from: data) else { return }
        llm = saved.llm
        outputDestination = saved.output
        defaults.removeObject(forKey: "onboarding.restore")
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
