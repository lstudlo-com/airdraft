import AirdraftCore
import Foundation
import PostHog

/// Builds the app's consent gate. Only an official, non-Debug build with a
/// valid embedded PostHog configuration offers telemetry, and only after the
/// user says yes is the SDK client created. Community, source, isolated and
/// Debug builds never construct it. See docs/telemetry.md.
@MainActor
enum TelemetryService {
    /// Bundled catalogue IDs: the only model names a download event may carry.
    nonisolated static let knownModelIDs: Set<String> = Set(ModelCatalogue.entries.map(\.id))

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func availability(info: [String: Any], isolated: Bool, isDebugBuild: Bool = isDebugBuild) -> TelemetryAvailability {
        // An unknown channel is a broken official build; it still needs a valid configuration.
        let channel = info["AirdraftDistribution"] as? String ?? "community"
        return TelemetryAvailability(isOfficial: !isolated && channel != "community",
                                     configuration: TelemetryConfiguration.from(info: info),
                                     isDebugBuild: isDebugBuild)
    }

    static func make(settings: AppSettings, bundle: Bundle = .main, isolated: Bool) -> Telemetry {
        let sanitizer = TelemetrySanitizer(isKnownModel: { knownModelIDs.contains($0) })
        return Telemetry(availability: availability(info: bundle.infoDictionary ?? [:], isolated: isolated),
                         settings: settings, sanitizer: sanitizer,
                         makeClient: { configuration in
                             #if DEBUG
                             // Debug builds never create the SDK client, whatever the plist says.
                             return nil
                             #else
                             return PostHogTelemetryClient(configuration: configuration, sanitizer: sanitizer)
                             #endif
                         },
                         purgeLocalData: { PostHogTelemetryClient.purgeLocalData(token: $0.token) })
    }

    /// The launch event, after the license receipt read has settled.
    static func launchEvent(license: LicenseStore.Access, bundle: Bundle = .main) -> TelemetryEvent {
        let info = bundle.infoDictionary ?? [:]
        return .appLaunched(.init(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "0",
            appBuild: info["CFBundleVersion"] as? String ?? "0",
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            architecture: .current,
            interfaceLanguage: .init(localization: bundle.preferredLocalizations.first),
            licenseState: .init(license)))
    }

    /// The bundled catalogue entry a download installs, or `other`.
    static func catalogueID(for config: ASRConfig) -> String {
        ModelCatalogue.entries.first { $0.isDownloadable && $0.isSelected(config) }?.id ?? "other"
    }
}

/// PostHog behind the consent gate. All SDK calls run on one serial queue, so
/// recording returns at once and delivery never waits on telemetry.
///
/// Unchecked Sendable: the SDK object is touched only on `queue`.
final class PostHogTelemetryClient: TelemetryClient, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.lstudlo.app.airdraft.telemetry", qos: .utility)
    private let sdk = PostHogSDK.shared

    init(configuration: TelemetryConfiguration, sanitizer: TelemetrySanitizer) {
        queue.async { self.setUp(configuration, sanitizer: sanitizer) }
    }

    /// Runs on `queue`.
    private func setUp(_ configuration: TelemetryConfiguration, sanitizer: TelemetrySanitizer) {
        let config = PostHogConfig(projectToken: configuration.token, host: configuration.host)
        // Anonymous events only: no person profiles, identify, autocapture,
        // lifecycle or screen events, flags, surveys, replay or swizzling.
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.capturePushNotificationOpened = false
        config.sendFeatureFlagEvent = false
        config.preloadFeatureFlags = false
        config.disableGeoIp = true
        // Crash reports are part of the same consent; no breadcrumbs.
        config.errorTrackingConfig.autoCapture = true
        config.errorTrackingConfig.exceptionSteps.enabled = false
        // Every outgoing event, including crash reports, passes the allowlist.
        config.setBeforeSend { event in
            guard let properties = sanitizer.outgoing(event: event.event, properties: event.properties) else { return nil }
            event.properties = properties
            return event
        }
        sdk.setup(config)
        // A previous opt-out persisted by the SDK wins over the config; consent is ours.
        sdk.optIn()
    }

    func capture(_ event: String, properties: [String: String]) {
        queue.async { self.sdk.capture(event, properties: properties) }
    }

    func optIn() {
        queue.async { self.sdk.optIn() }
    }

    func optOut() {
        queue.async {
            // Send what is already queued (the denial itself), then stop capture.
            self.sdk.flush()
            self.sdk.optOut()
            self.sdk.close()
        }
    }

    /// Removes the SDK's local queue, anonymous ID and pending crash report.
    /// Called at launch only when sharing is off, before any SDK setup. Only
    /// the SDK's own token-named folder and the crash reporter's folder for
    /// this bundle are removed.
    static func purgeLocalData(token: String, bundleID: String? = Bundle.main.bundleIdentifier,
                               support: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                               caches: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        guard let bundleID, !bundleID.isEmpty, !bundleID.contains("/"), !bundleID.hasPrefix("."),
              TelemetryConfiguration(token: token, host: TelemetryConfiguration.allowedHosts[0]) != nil else { return }
        let targets = [support?.appendingPathComponent(bundleID).appendingPathComponent(token),
                       caches?.appendingPathComponent("com.plausiblelabs.crashreporter.data").appendingPathComponent(bundleID)]
        for case let url? in targets where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
