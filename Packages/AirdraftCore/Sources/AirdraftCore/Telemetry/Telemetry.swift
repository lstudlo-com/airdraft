import Foundation
import Observation

/// Where pipeline, download, onboarding, license and media code report events.
/// Recording is fire-and-forget: it never waits, throws or changes behavior.
@MainActor
public protocol TelemetryRecording: AnyObject {
    func record(_ event: TelemetryEvent)
}

/// The transport behind `Telemetry`: PostHog in official Release builds, a
/// fake in tests. Calls must return at once and do any work off the caller.
public protocol TelemetryClient: AnyObject, Sendable {
    func capture(_ event: String, properties: [String: String])
    /// Resume after an earlier opt-out persisted by the SDK.
    func optIn()
    /// Stop sending and crash capture, and shut the client down.
    func optOut()
}

/// Consent gate for opt-in product telemetry. Nothing is captured, and no
/// client is constructed, unless the build is official, non-Debug, carries a
/// valid configuration and the user chose to share. Debug and community
/// builds therefore never create the SDK client at all.
@MainActor @Observable
public final class Telemetry: TelemetryRecording {
    public let availability: TelemetryAvailability
    /// Debug renders and fixtures may show the consent UI. It never enables sending.
    public var previewShowsChoice = false
    @ObservationIgnored public let sanitizer: TelemetrySanitizer
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let makeClient: @MainActor (TelemetryConfiguration) -> (any TelemetryClient)?
    @ObservationIgnored private let purgeLocalData: @MainActor (TelemetryConfiguration) -> Void
    @ObservationIgnored public private(set) var client: (any TelemetryClient)?

    public init(availability: TelemetryAvailability, settings: AppSettings, sanitizer: TelemetrySanitizer,
                makeClient: @escaping @MainActor (TelemetryConfiguration) -> (any TelemetryClient)?,
                purgeLocalData: @escaping @MainActor (TelemetryConfiguration) -> Void = { _ in }) {
        self.availability = availability
        self.settings = settings
        self.sanitizer = sanitizer
        self.makeClient = makeClient
        self.purgeLocalData = purgeLocalData
    }

    public var consent: TelemetryConsent { settings.telemetryConsent }
    /// The consent card and the Settings switch are shown.
    public var showsChoice: Bool { availability.isOffered || previewShowsChoice }
    public var needsDecision: Bool { showsChoice && consent == .undecided }
    public var isSending: Bool { availability.allowsSending(consent: consent) && client != nil }

    /// At launch: start the client for an earlier yes, or remove local SDK data
    /// (queue, anonymous ID, pending crash report) left from an earlier session
    /// when the answer is no or was reset.
    public func start() {
        guard availability.isOffered, let configuration = availability.configuration else { return }
        if consent == .granted { activate(configuration) } else { purgeLocalData(configuration) }
    }

    /// The user's choice from the consent card or Settings.
    public func choose(_ choice: TelemetryConsent) {
        guard choice != .undecided, choice != consent else { return }
        switch choice {
        case .granted:
            settings.telemetryConsent = .granted
            guard let configuration = availability.configuration, availability.isOffered else { return }
            activate(configuration)
            client?.optIn()
            record(.consentChanged(.granted))
        case .denied:
            // Say so while sharing is still on, then stop. An undecided user
            // never had a client, so a first "no" sends nothing.
            if isSending { record(.consentChanged(.denied)) }
            settings.telemetryConsent = .denied
            client?.optOut()
            client = nil
        case .undecided:
            break
        }
    }

    public func record(_ event: TelemetryEvent) {
        guard isSending, let client else { return }
        var properties = event.properties
        properties["app"] = TelemetrySanitizer.appTag
        guard sanitizer.allows(event: event.name, properties: properties) else { return }
        client.capture(event.name, properties: properties)
    }

    private func activate(_ configuration: TelemetryConfiguration) {
        guard client == nil, availability.isOffered else { return }
        client = makeClient(configuration)
    }
}
