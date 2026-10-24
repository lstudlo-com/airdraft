import ApplicationServices
import AVFoundation
import Foundation

public struct RecordingPrerequisiteError: LocalizedError, Sendable {
    /// Which prerequisite failed. Used only for anonymous failure categories.
    public enum Kind: Sendable { case permission, microphone, modelMissing, credential, setup, setupChanged }
    public let message: String
    public let kind: Kind
    public var errorDescription: String? { message }
    public init(_ message: String, kind: Kind = .setup) {
        self.message = message
        self.kind = kind
    }
}

/// Cheap, noninteractive checks run before opening the microphone. A saved key
/// cannot prove future service availability, but a missing or inaccessible key
/// must never cost the user a recording.
public enum RecordingPrerequisites {
    public struct Environment {
        public var microphoneAuthorized: Bool
        public var accessibilityAuthorized: Bool
        public var devices: [Microphone]
        public var defaultDeviceID: UInt32?
        public var readCredential: (String) throws -> String?
        public var appleIntelligenceUnavailable: () -> String?
        public var installed: (ASRConfig) -> Bool
        public init(microphoneAuthorized: Bool, accessibilityAuthorized: Bool,
                    devices: [Microphone], defaultDeviceID: UInt32?,
                    readCredential: @escaping (String) throws -> String?,
                    installed: @escaping (ASRConfig) -> Bool,
                    appleIntelligenceUnavailable: @escaping () -> String? = { AppleIntelligenceRefiner.unavailableReason }) {
            self.appleIntelligenceUnavailable = appleIntelligenceUnavailable
            self.microphoneAuthorized = microphoneAuthorized
            self.accessibilityAuthorized = accessibilityAuthorized
            self.devices = devices
            self.defaultDeviceID = defaultDeviceID
            self.readCredential = readCredential
            self.installed = installed
        }
        public static var live: Environment {
            .init(microphoneAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                  accessibilityAuthorized: AXIsProcessTrusted(), devices: MicrophoneDevices.available(),
                  defaultDeviceID: MicrophoneDevices.systemDefaultID,
                  readCredential: { try Keychain.read($0) }, installed: LocalModels.isInstalled)
        }
    }

    public static func check(asr: ASRConfig, llm: LLMConfig, refinementEnabled: Bool,
                             microphone: MicrophonePreference, insertionEnabled: Bool,
                             environment: Environment = .live) throws {
        _ = try SpeechLanguagePolicy.resolve(asr)
        func reject(_ message: String, _ kind: RecordingPrerequisiteError.Kind = .setup) throws {
            throw RecordingPrerequisiteError(message, kind: kind)
        }
        guard environment.microphoneAuthorized else {
            try reject(String(localized: "Allow microphone access in Settings.", bundle: .module), .permission); return
        }
        guard !insertionEnabled || environment.accessibilityAuthorized else {
            try reject(String(localized: "Allow Accessibility access in Settings.", bundle: .module), .permission); return
        }
        guard let device = microphone.resolve(in: environment.devices, systemDefaultID: environment.defaultDeviceID) else {
            try reject(String(localized: "Microphone unavailable. Choose an input in Settings.", bundle: .module), .microphone); return
        }
        let channel = microphone.channelIndex ?? 0
        guard channel >= 0, channel < device.inputChannelCount else {
            try reject(String(localized: "Input channel unavailable. Choose one in Settings.", bundle: .module), .microphone); return
        }
        if asr.kind.isLocal {
            if let error = LocalModels.catalogueError(for: asr) { try reject(error.localizedDescription, .modelMissing); return }
            guard environment.installed(asr) else {
                try reject(String(localized: "Install the speech model in Models.", bundle: .module), .modelMissing); return
            }
        } else {
            guard !asr.speechModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try reject(String(localized: "Choose a speech model in Models.", bundle: .module), .modelMissing); return
            }
            if asr.kind == .openAICompatible { try validateEndpoint(asr.baseURL, stage: "speech") }
            if asr.kind.preset != nil { try requireKey(asr.keyRef, stage: "speech", environment: environment) }
            else { _ = try readKey(asr.keyRef, stage: "speech", environment: environment) }
        }
        if refinementEnabled, llm.kind != .none {
            if llm.kind == .appleIntelligence, let reason = environment.appleIntelligenceUnavailable() {
                try reject(reason)
            }
            if llm.kind.requiresKey { try requireKey(llm.keyRef, stage: "refinement", environment: environment) }
            if llm.kind.isCLI, llm.cliExecutable == nil {
                try reject(String(localized: "Set up the refinement CLI in Models, or turn it Off.", bundle: .module)); return
            }
            if llm.kind == .openAICompatible { try validateEndpoint(llm.baseURL, stage: "refinement") }
        }
    }

    /// An HTTP(S) URL with a host; readiness uses the same test.
    static func isValidEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    private static func validateEndpoint(_ value: String, stage: String) throws {
        guard isValidEndpoint(value) else {
            throw RecordingPrerequisiteError(stage == "speech" ? String(localized: "Check the speech endpoint in Models.", bundle: .module)
                                             : String(localized: "Check the refinement endpoint in Models.", bundle: .module))
        }
    }

    private static func readKey(_ account: String, stage: String, environment: Environment) throws -> String? {
        do { return try environment.readCredential(account) }
        catch {
            throw RecordingPrerequisiteError(stage == "speech" ? String(localized: "Speech key locked. Use Allow Access in Models.", bundle: .module)
                                             : String(localized: "Refinement key locked. Use Allow Access in Models.", bundle: .module),
                                             kind: .credential)
        }
    }

    private static func requireKey(_ account: String, stage: String, environment: Environment) throws {
        guard let key = try readKey(account, stage: stage, environment: environment),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordingPrerequisiteError(stage == "refinement" ? String(localized: "Add a refinement API key in Models, or turn refinement Off.", bundle: .module)
                                             : String(localized: "Add a speech API key in Models.", bundle: .module),
                                             kind: .credential)
        }
    }
}
