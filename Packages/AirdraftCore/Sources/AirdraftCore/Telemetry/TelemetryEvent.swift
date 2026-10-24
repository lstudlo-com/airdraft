import Foundation

/// Every event Airdraft can send. A closed set: each case has a fixed name and
/// only enumerated or bucketed properties. Nothing here carries free text,
/// so transcripts, vocabulary, app names, window titles, URLs, file paths,
/// endpoints, keys and custom model names cannot be expressed.
public enum TelemetryEvent: Equatable, Sendable {
    case appLaunched(AppLaunch)
    case onboardingFinished(OnboardingOutcome)
    case dictationCompleted(DictationSummary)
    case dictationFailed(FailureCategory)
    /// `model` is a catalogue ID bundled with the app, or `other`.
    case modelDownloadFinished(model: String, outcome: DownloadOutcome)
    case meetingTranscribed(duration: MeetingDuration, engine: SpeechEngine)
    case license(LicenseAction)
    case consentChanged(ConsentChange)

    public var name: String {
        switch self {
        case .appLaunched: "app_launched"
        case .onboardingFinished: "onboarding_finished"
        case .dictationCompleted: "dictation_completed"
        case .dictationFailed: "dictation_failed"
        case .modelDownloadFinished: "model_download_finished"
        case .meetingTranscribed: "meeting_transcribed"
        case .license: "license_event"
        case .consentChanged: "telemetry_consent_changed"
        }
    }

    public var properties: [String: String] {
        switch self {
        case .appLaunched(let launch):
            ["app_version": launch.appVersion, "app_build": launch.appBuild, "macos_major": String(launch.macOSMajor),
             "arch": launch.architecture.rawValue, "interface_language": launch.interfaceLanguage.rawValue,
             "license_state": launch.licenseState.rawValue]
        case .onboardingFinished(let outcome):
            ["outcome": outcome.rawValue]
        case .dictationCompleted(let summary):
            summary.engine.properties.merging([
                "refinement_provider": summary.refinementProvider.rawValue,
                "profile": summary.profile.rawValue,
                "recording_duration": summary.recordingDuration.rawValue,
                "stop_to_delivery": summary.stopToDelivery.rawValue,
                "delivery_status": summary.deliveryStatus.rawValue,
                "refinement_outcome": summary.refinementOutcome.rawValue,
            ]) { current, _ in current }
        case .dictationFailed(let category):
            ["category": category.rawValue]
        case .modelDownloadFinished(let model, let outcome):
            ["model": model, "outcome": outcome.rawValue]
        case .meetingTranscribed(let duration, let engine):
            engine.properties.merging(["duration": duration.rawValue]) { current, _ in current }
        case .license(let action):
            ["action": action.rawValue]
        case .consentChanged(let change):
            ["consent": change.rawValue]
        }
    }

    // MARK: Property types

    public struct AppLaunch: Equatable, Sendable {
        public var appVersion: String
        public var appBuild: String
        public var macOSMajor: Int
        public var architecture: Architecture
        public var interfaceLanguage: InterfaceLanguage
        public var licenseState: LicenseState
        public init(appVersion: String, appBuild: String, macOSMajor: Int, architecture: Architecture,
                    interfaceLanguage: InterfaceLanguage, licenseState: LicenseState) {
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.macOSMajor = macOSMajor
            self.architecture = architecture
            self.interfaceLanguage = interfaceLanguage
            self.licenseState = licenseState
        }
    }

    public enum Architecture: String, CaseIterable, Sendable {
        case arm64, x86_64
        public static var current: Architecture {
            #if arch(arm64)
            .arm64
            #else
            .x86_64
            #endif
        }
    }

    public enum InterfaceLanguage: String, CaseIterable, Sendable {
        case en, zhHant = "zh-Hant", zhHans = "zh-Hans", other
        /// The app's resolved localization, such as `Bundle.main.preferredLocalizations.first`.
        public init(localization: String?) {
            switch localization {
            case "en": self = .en
            case "zh-Hant": self = .zhHant
            case "zh-Hans": self = .zhHans
            default: self = .other
            }
        }
    }

    public enum LicenseState: String, CaseIterable, Sendable {
        case trial, licensed, expired, none
        public init(_ access: LicenseStore.Access) {
            switch access {
            case .trial: self = .trial
            case .licensed: self = .licensed
            case .expired, .revoked: self = .expired
            case .community, .loading, .unconfigured, .needsTrial, .locked, .clockChanged: self = .none
            }
        }
    }

    public enum OnboardingOutcome: String, CaseIterable, Sendable { case completed, skipped }

    /// The speech provider family, never a model or endpoint.
    public struct SpeechEngine: Equatable, Sendable {
        public var kind: ASRProviderKind
        public init(_ kind: ASRProviderKind) { self.kind = kind }
        var properties: [String: String] {
            ["speech_engine": kind.rawValue, "speech_location": kind.isLocal ? "local" : "cloud"]
        }
    }

    public enum Profile: String, CaseIterable, Sendable {
        case clean, concise, summary, verbatim, custom
        /// Built-in profiles keep their stable IDs; every user profile is `custom`.
        public init(_ profile: RefinementProfile) {
            switch profile.id {
            case RefinementProfile.cleanID: self = .clean
            case RefinementProfile.conciseID: self = .concise
            case RefinementProfile.summaryID: self = .summary
            case RefinementProfile.verbatimID: self = .verbatim
            default: self = .custom
            }
        }
    }

    public enum RefinementOutcome: String, CaseIterable, Sendable {
        /// No refinement ran: off, a profile that keeps exact words, or a short utterance.
        case none
        case applied
        /// Refinement failed or was rejected; the raw transcript was delivered.
        case fallback
    }

    public struct DictationSummary: Equatable, Sendable {
        public var engine: SpeechEngine
        public var refinementProvider: LLMProviderKind
        public var profile: Profile
        public var recordingDuration: RecordingDuration
        public var stopToDelivery: Latency
        public var deliveryStatus: TextDeliveryStatus
        public var refinementOutcome: RefinementOutcome
        public init(engine: SpeechEngine, refinementProvider: LLMProviderKind, profile: Profile,
                    recordingDuration: RecordingDuration, stopToDelivery: Latency,
                    deliveryStatus: TextDeliveryStatus, refinementOutcome: RefinementOutcome) {
            self.engine = engine
            self.refinementProvider = refinementProvider
            self.profile = profile
            self.recordingDuration = recordingDuration
            self.stopToDelivery = stopToDelivery
            self.deliveryStatus = deliveryStatus
            self.refinementOutcome = refinementOutcome
        }
    }

    /// Why a dictation did not complete. Cancellation is never reported, and a
    /// refinement fallback is a completed dictation, not a failure.
    public enum FailureCategory: String, CaseIterable, Sendable {
        case permission = "permission"
        case microphoneUnavailable = "microphone_unavailable"
        case modelMissing = "model_missing"
        case credentialMissing = "credential_missing"
        case setupInvalid = "setup_invalid"
        case licenseRequired = "license_required"
        case recordingFailed = "recording_failed"
        case speechError = "speech_error"
        case deliveryFailed = "delivery_failed"
        case other = "other"
    }

    public enum DownloadOutcome: String, CaseIterable, Sendable { case ok, failed, cancelled }

    public enum LicenseAction: String, CaseIterable, Sendable {
        case trialStarted = "trial_started"
        case activated = "activated"
    }

    public enum ConsentChange: String, CaseIterable, Sendable { case granted, denied }

    // MARK: Buckets

    /// Dictation length, in coarse ranges.
    public enum RecordingDuration: String, CaseIterable, Sendable {
        case under5s = "0-5s", under15s = "5-15s", under30s = "15-30s", under1m = "30-60s"
        case under2m = "1-2m", under5m = "2-5m", under10m = "5-10m", over10m = "10m+"
        public init(seconds: Double) {
            let value = seconds.isFinite ? max(0, seconds) : 0
            self = switch value {
            case ..<5: .under5s
            case ..<15: .under15s
            case ..<30: .under30s
            case ..<60: .under1m
            case ..<120: .under2m
            case ..<300: .under5m
            case ..<600: .under10m
            default: .over10m
            }
        }
    }

    /// Stop-to-delivery time, in coarse ranges; `unknown` when not measured.
    public enum Latency: String, CaseIterable, Sendable {
        case under250ms = "0-250ms", under500ms = "250-500ms", under1s = "500ms-1s", under2s = "1-2s"
        case under5s = "2-5s", under10s = "5-10s", over10s = "10s+", unknown
        public init(milliseconds: Int?) {
            guard let milliseconds else { self = .unknown; return }
            self = switch max(0, milliseconds) {
            case ..<250: .under250ms
            case ..<500: .under500ms
            case ..<1000: .under1s
            case ..<2000: .under2s
            case ..<5000: .under5s
            case ..<10000: .under10s
            default: .over10s
            }
        }
    }

    /// Meeting or imported media length, in coarse ranges.
    public enum MeetingDuration: String, CaseIterable, Sendable {
        case under5m = "0-5m", under15m = "5-15m", under30m = "15-30m", under1h = "30-60m"
        case under2h = "1-2h", over2h = "2h+"
        public init(seconds: Double) {
            let value = seconds.isFinite ? max(0, seconds) : 0
            self = switch value {
            case ..<300: .under5m
            case ..<900: .under15m
            case ..<1800: .under30m
            case ..<3600: .under1h
            case ..<7200: .under2h
            default: .over2h
            }
        }
    }
}
