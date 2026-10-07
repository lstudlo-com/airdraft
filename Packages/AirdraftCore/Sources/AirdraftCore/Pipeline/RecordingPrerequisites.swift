import ApplicationServices
import AVFoundation
import Foundation

public struct RecordingPrerequisiteError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
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
        func reject(_ message: String) throws { throw RecordingPrerequisiteError(message) }
        guard environment.microphoneAuthorized else {
            try reject("Allow microphone access in Settings."); return
        }
        guard !insertionEnabled || environment.accessibilityAuthorized else {
            try reject("Allow Accessibility access in Settings."); return
        }
        guard let device = microphone.resolve(in: environment.devices, systemDefaultID: environment.defaultDeviceID) else {
            try reject("Microphone unavailable. Choose an input in Settings."); return
        }
        let channel = microphone.channelIndex ?? 0
        guard channel >= 0, channel < device.inputChannelCount else {
            try reject("Input channel unavailable. Choose one in Settings."); return
        }
        if asr.kind.isLocal {
            guard environment.installed(asr) else {
                try reject("Install the speech model in Models."); return
            }
        } else {
            guard !asr.speechModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try reject("Choose a speech model in Models."); return
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
                try reject("Set up the refinement CLI in Models, or turn it Off."); return
            }
            if llm.kind == .openAICompatible { try validateEndpoint(llm.baseURL, stage: "refinement") }
        }
    }

    private static func validateEndpoint(_ value: String, stage: String) throws {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else {
            throw RecordingPrerequisiteError("Check the \(stage) endpoint in Models.")
        }
    }

    private static func readKey(_ account: String, stage: String, environment: Environment) throws -> String? {
        do { return try environment.readCredential(account) }
        catch { throw RecordingPrerequisiteError("\(stage.capitalized) key locked. Use Allow Access in Models.") }
    }

    private static func requireKey(_ account: String, stage: String, environment: Environment) throws {
        guard let key = try readKey(account, stage: stage, environment: environment),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordingPrerequisiteError("Add a \(stage) API key in Models\(stage == "refinement" ? ", or turn refinement Off" : "").")
        }
    }
}
