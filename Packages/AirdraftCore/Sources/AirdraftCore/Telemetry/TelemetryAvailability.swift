import Foundation

/// The user's answer to the anonymous usage data question. Absent means
/// undecided; nothing is sent until the answer is `granted`.
public enum TelemetryConsent: String, Codable, CaseIterable, Sendable {
    case undecided, granted, denied
}

/// The public PostHog project an official build reports to. The token is a
/// client-side project token, not a secret; release builds embed it from
/// `scripts/telemetry-config.json`. Source and community builds have none.
public struct TelemetryConfiguration: Equatable, Sendable {
    /// The only ingestion origins accepted: PostHog US and EU cloud.
    public static let allowedHosts = ["https://us.i.posthog.com", "https://eu.i.posthog.com"]

    public let token: String
    public let host: String

    /// Nil unless the token is a PostHog project token and the host is exactly
    /// one of the allowed ingestion origins.
    public init?(token: String, host: String) {
        guard token.range(of: #"^phc_[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
              Self.allowedHosts.contains(host) else { return nil }
        self.token = token
        self.host = host
    }

    /// Reads `AirdraftTelemetryToken` and `AirdraftTelemetryHost` from Info.plist.
    public static func from(info: [String: Any]) -> TelemetryConfiguration? {
        guard let token = info["AirdraftTelemetryToken"] as? String,
              let host = info["AirdraftTelemetryHost"] as? String else { return nil }
        return TelemetryConfiguration(token: token, host: host)
    }
}

/// Whether this build may ever offer, and after consent send, telemetry.
/// Only an official, non-Debug build with a valid embedded configuration does.
public struct TelemetryAvailability: Equatable, Sendable {
    public let isOfficial: Bool
    public let configuration: TelemetryConfiguration?
    public let isDebugBuild: Bool

    public init(isOfficial: Bool, configuration: TelemetryConfiguration?, isDebugBuild: Bool) {
        self.isOfficial = isOfficial
        self.configuration = configuration
        self.isDebugBuild = isDebugBuild
    }

    /// The consent question and the Settings switch exist only in such a build.
    public var isOffered: Bool { isOfficial && configuration != nil && !isDebugBuild }

    public func allowsSending(consent: TelemetryConsent) -> Bool { isOffered && consent == .granted }
}
