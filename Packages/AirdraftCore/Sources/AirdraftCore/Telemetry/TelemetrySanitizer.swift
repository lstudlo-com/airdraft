import Foundation

/// The last check before anything leaves the app. It accepts only the known
/// event names, only each event's allowlisted keys, and only values from that
/// key's enumerated set or strict pattern. Anything else drops the event. The
/// app runs it twice: when an event is recorded and in the SDK's `beforeSend`,
/// where it also strips identifying properties the SDK attaches itself.
public struct TelemetrySanitizer: Sendable {
    /// Sent with every event so a shared project can separate the Mac app.
    public static let appTag = "airdraft-mac"
    public static let exceptionEvent = "$exception"

    /// SDK-attached keys that may pass `beforeSend`. Device names, models,
    /// locale, time zone, screen size, network, bundle identifiers, groups,
    /// screen names, feature flags and person properties are removed.
    public static let sdkKeys: Set<String> = ["$lib", "$lib_version", "$os_name", "$os_version",
                                              "$app_version", "$app_build", "$session_id",
                                              "$process_person_profile", "$geoip_disable"]
    /// Crash report fields. Steps (breadcrumbs) are not kept.
    public static let exceptionKeys: Set<String> = ["$exception_list", "$exception_level",
                                                    "$exception_source", "$debug_images"]

    private let isKnownModel: @Sendable (String) -> Bool

    /// `isKnownModel` accepts the catalogue IDs bundled with the app.
    public init(isKnownModel: @escaping @Sendable (String) -> Bool) {
        self.isKnownModel = isKnownModel
    }

    public static var eventNames: Set<String> {
        ["app_launched", "onboarding_finished", "dictation_completed", "dictation_failed",
         "model_download_finished", "meeting_transcribed", "license_event", "telemetry_consent_changed"]
    }

    private enum Rule {
        case oneOf(Set<String>)
        case pattern(String)
        case model
    }

    private static func values<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> Rule where T.RawValue == String {
        .oneOf(Set(type.allCases.map(\.rawValue)))
    }

    private static let speech: [String: Rule] = [
        "speech_engine": values(ASRProviderKind.self), "speech_location": .oneOf(["local", "cloud"]),
    ]

    private static let schema: [String: [String: Rule]] = [
        "app_launched": [
            "app_version": .pattern(#"^[0-9]{1,3}(\.[0-9]{1,3}){0,3}$"#),
            "app_build": .pattern(#"^[0-9]{1,7}$"#),
            "macos_major": .pattern(#"^[0-9]{2}$"#),
            "arch": values(TelemetryEvent.Architecture.self),
            "interface_language": values(TelemetryEvent.InterfaceLanguage.self),
            "license_state": values(TelemetryEvent.LicenseState.self),
        ],
        "onboarding_finished": ["outcome": values(TelemetryEvent.OnboardingOutcome.self)],
        "dictation_completed": speech.merging([
            "refinement_provider": values(LLMProviderKind.self),
            "profile": values(TelemetryEvent.Profile.self),
            "recording_duration": values(TelemetryEvent.RecordingDuration.self),
            "stop_to_delivery": values(TelemetryEvent.Latency.self),
            "delivery_status": values(TextDeliveryStatus.self),
            "refinement_outcome": values(TelemetryEvent.RefinementOutcome.self),
        ]) { current, _ in current },
        "dictation_failed": ["category": values(TelemetryEvent.FailureCategory.self)],
        "model_download_finished": ["model": .model, "outcome": values(TelemetryEvent.DownloadOutcome.self)],
        "meeting_transcribed": speech.merging(["duration": values(TelemetryEvent.MeetingDuration.self)]) { current, _ in current },
        "license_event": ["action": values(TelemetryEvent.LicenseAction.self)],
        "telemetry_consent_changed": ["consent": values(TelemetryEvent.ConsentChange.self)],
    ]

    /// True only for a known event whose keys are exactly its schema plus `app`,
    /// with every value allowed.
    public func allows(event: String, properties: [String: String]) -> Bool {
        guard let rules = Self.schema[event], properties["app"] == Self.appTag,
              Set(properties.keys) == Set(rules.keys).union(["app"]) else { return false }
        for (key, rule) in rules {
            guard let value = properties[key], accepts(value, rule) else { return false }
        }
        return true
    }

    private func accepts(_ value: String, _ rule: Rule) -> Bool {
        switch rule {
        case .oneOf(let allowed): return allowed.contains(value)
        case .pattern(let pattern): return value.range(of: pattern, options: .regularExpression) != nil
        case .model: return value == "other" || (isKnownModel(value) && Self.isIdentifier(value))
        }
    }

    /// Catalogue IDs are short identifiers such as `qwen3:1.7b`, never paths or URLs.
    static func isIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}(:[a-z0-9][a-z0-9._-]{0,63})?$"#, options: [.regularExpression, .caseInsensitive]) != nil
            && !value.contains("..")
    }

    /// The outgoing properties for an SDK event, or nil to drop it. Airdraft's
    /// own events keep only their validated keys and the allowed SDK keys.
    /// Crash reports keep their exception fields, with user names in paths
    /// replaced and long strings shortened. Every other SDK event is dropped.
    public func outgoing(event: String, properties: [String: Any]) -> [String: Any]? {
        var result: [String: Any] = [:]
        for key in Self.sdkKeys {
            if let value = properties[key], let safe = Self.safeSDKValue(value) { result[key] = safe }
        }
        if event == Self.exceptionEvent {
            for key in Self.exceptionKeys {
                if let value = properties[key] { result[key] = Self.scrubbed(value) }
            }
            result["app"] = Self.appTag
            return result
        }
        guard let rules = Self.schema[event] else { return nil }
        var own: [String: String] = [:]
        for key in rules.keys.sorted() + ["app"] {
            guard let value = properties[key] as? String else { return nil }
            own[key] = value
        }
        guard allows(event: event, properties: own) else { return nil }
        return result.merging(own) { _, new in new }
    }

    private static func safeSDKValue(_ value: Any) -> Any? {
        if let flag = value as? Bool { return flag }
        guard let text = value as? String,
              text.range(of: #"^[A-Za-z0-9._ -]{1,64}$"#, options: .regularExpression) != nil else { return nil }
        return text
    }

    /// Crash text can quote paths below a home folder; the user name is replaced.
    static func scrubbed(_ value: Any) -> Any {
        switch value {
        case let text as String:
            let replaced = text.replacingOccurrences(of: #"/Users/[^/\s]+"#, with: "/Users/<user>", options: .regularExpression)
            return replaced.count > 1024 ? String(replaced.prefix(1024)) : replaced
        case let list as [Any]: return list.map(scrubbed)
        case let map as [String: Any]: return map.mapValues(scrubbed)
        default: return value
        }
    }
}
