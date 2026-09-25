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
    /// No recording window.
    case none
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .mini: return "Mini"
        case .none: return "None"
        }
    }
}

/// UserDefaults-backed settings. Secrets live in Keychain, not here.
@MainActor
@Observable
public final class AppSettings {
    public var asr: ASRConfig { didSet { persist("asr", asr) } }
    public var llm: LLMConfig { didSet { persist("llm", llm) } }
    public var hotkey: Hotkey { didSet { persist("hotkey", hotkey) } }
    public var hotkeyBehavior: HotkeyBehavior { didSet { persist("hotkeyBehavior", hotkeyBehavior) } }
    public var insertionMethod: InsertionMethod { didSet { persist("insertionMethod", insertionMethod) } }
    public var useAppContext: Bool { didSet { persist("useAppContext", useAppContext) } }
    public var maxRecordingSeconds: Int { didSet { persist("maxRecordingSeconds", maxRecordingSeconds) } }
    public var appearance: AppearanceMode { didSet { persist("appearance", appearance) } }
    /// Unload local speech models after this many idle minutes. 0 = keep loaded.
    public var idleUnloadMinutes: Int { didSet { persist("idleUnloadMinutes", idleUnloadMinutes) } }
    /// Ask LM Studio to unload the LLM when the app quits.
    public var unloadLLMOnQuit: Bool { didSet { persist("unloadLLMOnQuit", unloadLLMOnQuit) } }
    public var hudStyle: HUDStyle { didSet { persist("hudStyle", hudStyle) } }
    public var microphone: MicrophonePreference { didSet { persist("microphone", microphone) } }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard, Bundle.main.bundleIdentifier == AppIdentity.bundleID {
            AppIdentity.importLegacyDefaults(into: defaults,
                legacy: defaults.persistentDomain(forName: AppIdentity.legacyBundleID) ?? [:])
        }
        asr = Self.load("asr", from: defaults) ?? ASRConfig()
        llm = Self.load("llm", from: defaults) ?? LLMConfig()
        hotkey = Self.load("hotkey", from: defaults) ?? .controlOption
        hotkeyBehavior = Self.load("hotkeyBehavior", from: defaults) ?? .hold
        insertionMethod = Self.load("insertionMethod", from: defaults) ?? .auto
        useAppContext = Self.load("useAppContext", from: defaults) ?? true
        maxRecordingSeconds = Self.load("maxRecordingSeconds", from: defaults) ?? 300
        appearance = Self.load("appearance", from: defaults) ?? .auto
        idleUnloadMinutes = Self.load("idleUnloadMinutes", from: defaults) ?? 10
        unloadLLMOnQuit = Self.load("unloadLLMOnQuit", from: defaults) ?? true
        hudStyle = Self.load("hudStyle", from: defaults) ?? .classic
        microphone = Self.load("microphone", from: defaults) ?? .systemDefault
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
