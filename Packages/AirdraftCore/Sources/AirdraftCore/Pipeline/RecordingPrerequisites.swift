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
        public var installed: (ASRConfig) -> Bool
        public init(microphoneAuthorized: Bool, accessibilityAuthorized: Bool,
                    devices: [Microphone], defaultDeviceID: UInt32?,
                    readCredential: @escaping (String) throws -> String?,
                    installed: @escaping (ASRConfig) -> Bool) {
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
        func reject(_ message: String) throws { throw RecordingPrerequisiteError(message) }
        guard environment.microphoneAuthorized else {
            try reject("Recording did not start. Allow microphone access in Configuration before dictating."); return
        }
        guard !insertionEnabled || environment.accessibilityAuthorized else {
            try reject("Recording did not start. Grant Accessibility access in Configuration so Airdraft can insert your text."); return
        }
        guard let device = microphone.resolve(in: environment.devices, systemDefaultID: environment.defaultDeviceID) else {
            try reject("Recording did not start. The selected microphone is unavailable. Choose a connected input in Configuration."); return
        }
        let channel = microphone.channelIndex ?? 0
        guard channel >= 0, channel < device.inputChannelCount else {
            try reject("Recording did not start. The selected microphone channel is unavailable. Choose a valid input in Configuration."); return
        }
        if asr.kind.isLocal {
            guard environment.installed(asr) else {
                try reject("Recording did not start. Install the selected speech model in Models first."); return
            }
        } else {
            guard !asr.speechModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                try reject("Recording did not start. Choose a speech model in Models first."); return
            }
            if asr.kind == .openAICompatible { try validateEndpoint(asr.baseURL, stage: "speech") }
            if asr.kind.preset != nil { try requireKey(asr.keyRef, stage: "speech", environment: environment) }
            else { _ = try readKey(asr.keyRef, stage: "speech", environment: environment) }
        }
        if refinementEnabled, llm.kind != .none {
            if llm.kind.requiresKey { try requireKey(llm.keyRef, stage: "refinement", environment: environment) }
            if llm.kind.isCLI, llm.cliExecutable == nil {
                try reject("Recording did not start. Set up the selected refinement CLI in Models, or turn refinement Off."); return
            }
            if llm.kind == .openAICompatible { try validateEndpoint(llm.baseURL, stage: "refinement") }
        }
    }

    private static func validateEndpoint(_ value: String, stage: String) throws {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else {
            throw RecordingPrerequisiteError("Recording did not start. Correct the \(stage) endpoint in Models first.")
        }
    }

    private static func readKey(_ account: String, stage: String, environment: Environment) throws -> String? {
        do { return try environment.readCredential(account) }
        catch { throw RecordingPrerequisiteError("Recording did not start. The \(stage) API key is locked or inaccessible. Use Allow Access in Models first.") }
    }

    private static func requireKey(_ account: String, stage: String, environment: Environment) throws {
        guard let key = try readKey(account, stage: stage, environment: environment),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordingPrerequisiteError("Recording did not start. Add the \(stage) API key in Models first\(stage == "refinement" ? ", or turn refinement Off" : "").")
        }
    }
}
