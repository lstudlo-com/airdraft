import XCTest
@testable import AirdraftCore

/// Records what the gate hands to the transport. Never sends anything.
final class FakeTelemetryClient: TelemetryClient, Sendable {
    struct Captured: Equatable, Sendable { let event: String; let properties: [String: String] }
    let captured = Locked<[Captured]>([])
    let calls = Locked<[String]>([])
    func capture(_ event: String, properties: [String: String]) {
        captured.withLock { $0.append(.init(event: event, properties: properties)) }
        calls.withLock { $0.append("capture:\(event)") }
    }
    func optIn() { calls.withLock { $0.append("optIn") } }
    func optOut() { calls.withLock { $0.append("optOut") } }
}

@MainActor
private final class HarnessBox {
    weak var harness: TelemetryHarness?
}

@MainActor
final class TelemetryHarness {
    let suite = "airdraft.telemetry.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: AppSettings
    let telemetry: Telemetry
    private(set) var constructions = 0
    private(set) var purges = 0
    private(set) var clients: [FakeTelemetryClient] = []
    nonisolated static let configuration = TelemetryConfiguration(token: "phc_TestOnlyToken123", host: "https://us.i.posthog.com")!
    nonisolated static let knownModels: Set<String> = ["qwen3:1.7b", "sherpa:senseVoiceMultilingual", "coreml:parakeet-tdt-0.6b-v3"]

    init(official: Bool = true, configuration: TelemetryConfiguration? = TelemetryHarness.configuration,
         debug: Bool = false, consent: TelemetryConsent = .undecided) {
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
        settings.telemetryConsent = consent
        let box = HarnessBox()
        telemetry = Telemetry(
            availability: TelemetryAvailability(isOfficial: official, configuration: configuration, isDebugBuild: debug),
            settings: settings,
            sanitizer: TelemetrySanitizer(isKnownModel: { Self.knownModels.contains($0) }),
            makeClient: { _ in
                let client = FakeTelemetryClient()
                box.harness?.constructions += 1
                box.harness?.clients.append(client)
                return client
            },
            purgeLocalData: { _ in box.harness?.purges += 1 })
        box.harness = self
    }

    var captured: [FakeTelemetryClient.Captured] { clients.flatMap { $0.captured.value } }
    func tearDown() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
final class TelemetryTests: XCTestCase {
    private var harnesses: [TelemetryHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { harness.tearDown() }
        harnesses = []
    }

    private func harness(official: Bool = true, configuration: TelemetryConfiguration? = TelemetryHarness.configuration,
                         debug: Bool = false, consent: TelemetryConsent = .undecided) -> TelemetryHarness {
        let harness = TelemetryHarness(official: official, configuration: configuration, debug: debug, consent: consent)
        harnesses.append(harness)
        return harness
    }

    static var sampleEvents: [TelemetryEvent] {
        [.appLaunched(.init(appVersion: "0.12.1", appBuild: "1234", macOSMajor: 26, architecture: .arm64,
                            interfaceLanguage: .zhHant, licenseState: .trial)),
         .onboardingFinished(.completed),
         .dictationCompleted(.init(engine: .init(.senseVoiceMultilingual), refinementProvider: .appleIntelligence,
                                   profile: .clean, recordingDuration: .under15s, stopToDelivery: .under1s,
                                   deliveryStatus: .delivered, refinementOutcome: .applied)),
         .dictationFailed(.speechError),
         .modelDownloadFinished(model: "qwen3:1.7b", outcome: .ok),
         .meetingTranscribed(duration: .under1h, engine: .init(.whisperKit)),
         .license(.trialStarted),
         .consentChanged(.granted)]
    }

    // MARK: Gating

    /// Nothing is captured or constructed unless an official release has consent; community and
    /// Debug builds never construct a client even when choosing to share; previews show the choice
    /// without sending; configuration accepts only project tokens and ingestion origins.
    func testOnlyConsentedOfficialReleasesSendAndConfigurationIsStrict() {
        do {
            let builds: [(String, Bool, TelemetryConfiguration?, Bool)] = [
                ("community", false, TelemetryHarness.configuration, false),
                ("debug", true, TelemetryHarness.configuration, true),
                ("unconfigured", true, nil, false),
                ("official", true, TelemetryHarness.configuration, false),
            ]
            for (name, official, configuration, debug) in builds {
                for consent in TelemetryConsent.allCases {
                    let harness = harness(official: official, configuration: configuration, debug: debug, consent: consent)
                    harness.telemetry.start()
                    for event in Self.sampleEvents { harness.telemetry.record(event) }
                    let allowed = name == "official" && consent == .granted
                    XCTAssertEqual(harness.constructions, allowed ? 1 : 0, "\(name) \(consent)")
                    XCTAssertEqual(harness.captured.count, allowed ? Self.sampleEvents.count : 0, "\(name) \(consent)")
                    XCTAssertEqual(harness.telemetry.isSending, allowed)
                    XCTAssertEqual(harness.telemetry.showsChoice, name == "official", "\(name)")
                }
            }
        }

        do {
            for (official, debug) in [(false, false), (true, true), (false, true)] {
                let harness = harness(official: official, debug: debug)
                harness.telemetry.start()
                harness.telemetry.choose(.granted)
                for event in Self.sampleEvents { harness.telemetry.record(event) }
                harness.telemetry.choose(.denied)
                harness.telemetry.choose(.granted)
                XCTAssertEqual(harness.constructions, 0)
                XCTAssertNil(harness.telemetry.client)
                XCTAssertTrue(harness.captured.isEmpty)
                XCTAssertEqual(harness.purges, 0, "Only an offered build manages SDK data")
            }
        }

        do {
            let harness = harness(debug: true)
            harness.telemetry.previewShowsChoice = true
            XCTAssertTrue(harness.telemetry.needsDecision)
            harness.telemetry.choose(.granted)
            harness.telemetry.record(.dictationFailed(.permission))
            XCTAssertEqual(harness.settings.telemetryConsent, .granted)
            XCTAssertEqual(harness.constructions, 0)
            XCTAssertTrue(harness.captured.isEmpty)
        }

        XCTAssertNotNil(TelemetryConfiguration(token: "phc_abc123XYZ", host: "https://us.i.posthog.com"))
        XCTAssertNotNil(TelemetryConfiguration(token: "phc_abc123XYZ", host: "https://eu.i.posthog.com"))
        for (token, host) in [("phx_abc", "https://us.i.posthog.com"), ("phc_", "https://us.i.posthog.com"),
                              ("phc_abc-123", "https://us.i.posthog.com"), ("phc_abc$(X)", "https://us.i.posthog.com"),
                              ("", "https://us.i.posthog.com"), ("phc_abc", "http://us.i.posthog.com"),
                              ("phc_abc", "https://us.i.posthog.com/"), ("phc_abc", "https://us.posthog.com"),
                              ("phc_abc", "https://us.i.posthog.com.evil.test"), ("phc_abc", "https://app.posthog.com"),
                              ("phc_abc", "")] {
            XCTAssertNil(TelemetryConfiguration(token: token, host: host), "\(token) \(host)")
        }
        XCTAssertNil(TelemetryConfiguration.from(info: ["AirdraftTelemetryToken": "", "AirdraftTelemetryHost": ""]))
        XCTAssertNil(TelemetryConfiguration.from(info: [:]))
        XCTAssertEqual(TelemetryConfiguration.from(info: ["AirdraftTelemetryToken": "phc_abc", "AirdraftTelemetryHost": "https://eu.i.posthog.com"])?.host,
                       "https://eu.i.posthog.com")
    }

    /// Consent sends only after yes and reports denial before stopping; a first no sends nothing
    /// and later launches purge local data; consent persists outside existing-setup detection.
    func testConsentTransitionsLaunchPurgesAndPersistence() {
        do {
            let harness = harness()
            harness.telemetry.start()
            XCTAssertEqual(harness.purges, 1, "Undecided launches remove leftover SDK data")
            XCTAssertTrue(harness.telemetry.needsDecision)
            harness.telemetry.record(.onboardingFinished(.skipped))
            XCTAssertEqual(harness.constructions, 0, "Nothing is created before a choice")

            harness.telemetry.choose(.granted)
            XCTAssertFalse(harness.telemetry.needsDecision)
            XCTAssertEqual(harness.constructions, 1)
            XCTAssertEqual(harness.clients[0].calls.value, ["optIn", "capture:telemetry_consent_changed"])
            XCTAssertEqual(harness.captured.last?.properties, ["consent": "granted", "app": "airdraft-mac"])

            harness.telemetry.choose(.denied)
            XCTAssertEqual(harness.clients[0].calls.value.suffix(2), ["capture:telemetry_consent_changed", "optOut"])
            XCTAssertEqual(harness.captured.last?.properties["consent"], "denied")
            XCTAssertNil(harness.telemetry.client)
            harness.telemetry.record(.dictationFailed(.permission))
            XCTAssertEqual(harness.captured.count, 2)
            XCTAssertEqual(AppSettings(defaults: harness.defaults).telemetryConsent, .denied)

            // Turning it on again creates a fresh client that opts in.
            harness.telemetry.choose(.granted)
            XCTAssertEqual(harness.constructions, 2)
            XCTAssertEqual(harness.clients[1].calls.value.first, "optIn")
        }

        do {
            let first = harness()
            first.telemetry.choose(.denied)
            XCTAssertEqual(first.constructions, 0)
            XCTAssertTrue(first.captured.isEmpty)
            let relaunch = harness(consent: .denied)
            relaunch.telemetry.start()
            XCTAssertEqual(relaunch.purges, 1)
            XCTAssertEqual(relaunch.constructions, 0)
            let granted = harness(consent: .granted)
            granted.telemetry.start()
            XCTAssertEqual(granted.purges, 0)
            XCTAssertEqual(granted.constructions, 1)
            XCTAssertEqual(granted.clients[0].calls.value, [], "A launch with earlier consent sends nothing by itself")
        }

        let suite = "airdraft.telemetry.consent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppSettings(defaults: defaults).telemetryConsent, .undecided)
        let settings = AppSettings(defaults: defaults)
        settings.telemetryConsent = .granted
        XCTAssertEqual(defaults.string(forKey: "telemetry.consent"), "granted")
        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.telemetryConsent, .granted)
        XCTAssertFalse(reopened.hadExistingSetup, "An answer alone is not an existing setup")
        XCTAssertTrue(reopened.onboarding.shouldPresentOnLaunch)
        reopened.telemetryConsent = .undecided
        XCTAssertNil(defaults.object(forKey: "telemetry.consent"))
        defaults.set("maybe", forKey: "telemetry.consent")
        XCTAssertEqual(AppSettings(defaults: defaults).telemetryConsent, .undecided)
    }

    // MARK: Allowlist

    private var sanitizer: TelemetrySanitizer { TelemetrySanitizer(isKnownModel: { TelemetryHarness.knownModels.contains($0) }) }

    /// Every value of every enumerated property, combined across events.
    static var allEvents: [TelemetryEvent] {
        var events: [TelemetryEvent] = []
        for language in TelemetryEvent.InterfaceLanguage.allCases {
            for license in TelemetryEvent.LicenseState.allCases {
                for arch in TelemetryEvent.Architecture.allCases {
                    events.append(.appLaunched(.init(appVersion: "1.0", appBuild: "7", macOSMajor: 15, architecture: arch,
                                                     interfaceLanguage: language, licenseState: license)))
                }
            }
        }
        events += TelemetryEvent.OnboardingOutcome.allCases.map { .onboardingFinished($0) }
        for kind in ASRProviderKind.allCases {
            for provider in LLMProviderKind.allCases {
                for profile in TelemetryEvent.Profile.allCases {
                    events.append(.dictationCompleted(.init(engine: .init(kind), refinementProvider: provider, profile: profile,
                        recordingDuration: .under5s, stopToDelivery: .unknown, deliveryStatus: .sentUnverified, refinementOutcome: .none)))
                }
            }
            for duration in TelemetryEvent.MeetingDuration.allCases { events.append(.meetingTranscribed(duration: duration, engine: .init(kind))) }
        }
        for duration in TelemetryEvent.RecordingDuration.allCases {
            for latency in TelemetryEvent.Latency.allCases {
                for status in TextDeliveryStatus.allCases {
                    for outcome in TelemetryEvent.RefinementOutcome.allCases {
                        events.append(.dictationCompleted(.init(engine: .init(.parakeet), refinementProvider: .none, profile: .custom,
                            recordingDuration: duration, stopToDelivery: latency, deliveryStatus: status, refinementOutcome: outcome)))
                    }
                }
            }
        }
        events += TelemetryEvent.FailureCategory.allCases.map { .dictationFailed($0) }
        for model in TelemetryHarness.knownModels.sorted() + ["other"] {
            for outcome in TelemetryEvent.DownloadOutcome.allCases { events.append(.modelDownloadFinished(model: model, outcome: outcome)) }
        }
        events += TelemetryEvent.LicenseAction.allCases.map { .license($0) }
        events += TelemetryEvent.ConsentChange.allCases.map { .consentChanged($0) }
        return events
    }

    /// Every enumerated event value passes the allowlist; hostile values in any key, extra keys,
    /// foreign tags and event names are rejected and never reach the client.
    func testEveryEnumeratedValuePassesAndHostileValuesNeverReachTheClient() {
        do {
            let events = Self.allEvents
            XCTAssertGreaterThan(events.count, 1000)
            var names = Set<String>()
            for event in events {
                var properties = event.properties
                properties["app"] = TelemetrySanitizer.appTag
                names.insert(event.name)
                XCTAssertTrue(sanitizer.allows(event: event.name, properties: properties), "\(event)")
                XCTAssertNotNil(sanitizer.outgoing(event: event.name, properties: properties))
                for value in properties.values {
                    XCTAssertLessThanOrEqual(value.count, 32, "Values are short labels: \(value)")
                    XCTAssertFalse(value.contains("/") && !value.contains("-") && value != "0-5s", "No paths: \(value)")
                    XCTAssertFalse(value.contains(" "), "No free text: \(value)")
                }
            }
            XCTAssertEqual(names, TelemetrySanitizer.eventNames)
        }

        do {
            for event in Self.allEvents.prefix(400) + Self.sampleEvents {
                var base = event.properties
                base["app"] = TelemetrySanitizer.appTag
                for key in base.keys {
                    for value in Self.hostile {
                        var properties = base
                        properties[key] = value
                        XCTAssertFalse(sanitizer.allows(event: event.name, properties: properties), "\(event.name).\(key)=\(value)")
                        XCTAssertNil(sanitizer.outgoing(event: event.name, properties: properties), "\(event.name).\(key)=\(value)")
                    }
                }
                for extra in ["transcript", "app_name", "bundle_id", "window_title", "url", "path", "endpoint", "api_key", "model_id", "$ip"] {
                    var properties = base
                    properties[extra] = "x"
                    XCTAssertFalse(sanitizer.allows(event: event.name, properties: properties), "Extra key \(extra)")
                }
                var untagged = base
                untagged["app"] = "airdraft-web"
                XCTAssertFalse(sanitizer.allows(event: event.name, properties: untagged))
            }
            for name in Self.hostile + ["$pageview", "Application Opened", "$identify", "$set"] {
                XCTAssertFalse(sanitizer.allows(event: name, properties: ["app": TelemetrySanitizer.appTag]))
            }
        }

        let harness = harness(consent: .granted)
        harness.telemetry.start()
        for value in Self.hostile {
            harness.telemetry.record(.modelDownloadFinished(model: value, outcome: .ok))
            harness.telemetry.record(.appLaunched(.init(appVersion: value, appBuild: value, macOSMajor: 26, architecture: .arm64,
                                                        interfaceLanguage: .en, licenseState: .none)))
        }
        XCTAssertTrue(harness.captured.isEmpty, "\(harness.captured)")
        harness.telemetry.record(.modelDownloadFinished(model: "other", outcome: .failed))
        XCTAssertEqual(harness.captured.map(\.event), ["model_download_finished"])
        // Every captured value is in the event's allowlist; nothing else is attached.
        for capture in harness.captured {
            XCTAssertTrue(sanitizer.allows(event: capture.event, properties: capture.properties))
        }
    }

    static let hostile = [
        "Please send the quarterly report to Alice before Friday", // transcript
        "Kubernetes, Airdraft, 林小明", // vocabulary
        "Visual Studio Code", "com.microsoft.VSCode", // app name, bundle ID
        "Re: Contract draft — Mail", // window title
        "https://mail.example.com/inbox?id=42", // URL
        "/Users/alice/Documents/Secret Plan.pages", "~/Library/Application Support/Transcribar/history.sqlite",
        "http://192.168.1.20:1234/v1", "https://api.openai.com/v1/chat/completions", // endpoints
        "sk-proj-AbCdEf0123456789", "phc_leakedKey", "gsk_live_123", // keys
        "mlx-community/my-private-finetune", "custom:whisper-large-v3-acme", "qwen3:../../etc/passwd", // custom models
        "", " ", "clean\n", "delivered ", "../../", "ok; DROP TABLE", String(repeating: "a", count: 300),
    ]

    /// Outgoing strips identifying SDK properties and drops other SDK events; crash reports keep
    /// exception fields without user names or steps.
    func testOutgoingStripsSDKPropertiesAndCrashReportsDropUserNamesAndSteps() throws {
        do {
            var properties: [String: Any] = TelemetryEvent.dictationFailed(.permission).properties
            properties["app"] = TelemetrySanitizer.appTag
            let sdk: [String: Any] = [
                "$lib": "posthog-ios", "$lib_version": "3.92.4", "$os_name": "macOS", "$os_version": "26.0.1",
                "$app_version": "0.12.1", "$app_build": "1234", "$session_id": "01920c3e-7c1a-7d5b-9f3a-3b5c8e2a1f00",
                "$process_person_profile": false, "$geoip_disable": true,
                "$device_name": "Alice’s MacBook Pro", "$device_model": "Mac15,3", "$device_manufacturer": "Apple",
                "$device_type": "Desktop", "$locale": "zh-Hant-TW", "$timezone": "Asia/Taipei",
                "$screen_width": 1512.0, "$screen_height": 982.0, "$network_wifi": true, "$app_namespace": "com.lstudlo.app.airdraft",
                "$app_name": "Airdraft", "$groups": ["company": "x"], "$set": ["name": "x"], "$screen_name": "Home",
                "$active_feature_flags": ["beta"], "$ip": "203.0.113.4", "$os_version_bad": "/Users/alice",
            ]
            properties.merge(sdk) { current, _ in current }
            let out = try XCTUnwrap(sanitizer.outgoing(event: "dictation_failed", properties: properties))
            XCTAssertEqual(Set(out.keys), Set(["category", "app"]).union(TelemetrySanitizer.sdkKeys))
            XCTAssertEqual(out["$geoip_disable"] as? Bool, true)
            XCTAssertNil(out["$ip"])
            // An SDK value that is not a short label is dropped too.
            var odd = properties
            odd["$os_version"] = "/Users/alice/secret"
            XCTAssertNil(try XCTUnwrap(sanitizer.outgoing(event: "dictation_failed", properties: odd))["$os_version"])
            for name in ["Application Opened", "Application Installed", "$screen", "$identify", "$feature_flag_called",
                         "$snapshot", "$create_alias", "$groupidentify", "$set", "$autocapture"] {
                XCTAssertNil(sanitizer.outgoing(event: name, properties: sdk), name)
            }
        }

        let crash: [String: Any] = [
            "$exception_level": "fatal", "$exception_source": "ios.crash_reporter",
            "$exception_list": [["type": "EXC_BAD_ACCESS", "value": "Crashed in /Users/alice/Library/x.dylib " + String(repeating: "x", count: 2000),
                                 "stacktrace": ["frames": [["image_addr": "0x1000", "package": "/Users/alice/Applications/airdraft.app/Contents/MacOS/airdraft"]]]]],
            "$debug_images": [["code_file": "/Users/bob smith/Applications/airdraft.app", "image_addr": "0x1000"]],
            "$exception_steps": [["$message": "Typed: secret text"]],
            "$device_name": "Alice’s Mac", "$lib": "posthog-ios",
        ]
        let out = try XCTUnwrap(sanitizer.outgoing(event: "$exception", properties: crash))
        XCTAssertNil(out["$exception_steps"])
        XCTAssertNil(out["$device_name"])
        XCTAssertEqual(out["app"] as? String, "airdraft-mac")
        let text = String(describing: out)
        XCTAssertFalse(text.contains("alice"))
        XCTAssertFalse(text.contains("bob"))
        XCTAssertTrue(text.contains("/Users/<user>/Applications/airdraft.app"))
        let list = try XCTUnwrap(out["$exception_list"] as? [[String: Any]])
        XCTAssertLessThanOrEqual((list[0]["value"] as? String)?.count ?? 0, 1024)
    }

    // MARK: Buckets

    func testBucketsUseCoarseRanges() {
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: -1), .under5s)
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: .nan), .under5s)
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: 4.99), .under5s)
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: 5), .under15s)
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: 59.9), .under1m)
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: 299), .under5m)
        XCTAssertEqual(TelemetryEvent.RecordingDuration(seconds: 600), .over10m)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: nil), .unknown)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: -5), .under250ms)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: 249), .under250ms)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: 250), .under500ms)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: 999), .under1s)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: 4_999), .under5s)
        XCTAssertEqual(TelemetryEvent.Latency(milliseconds: 60_000), .over10s)
        XCTAssertEqual(TelemetryEvent.MeetingDuration(seconds: 299), .under5m)
        XCTAssertEqual(TelemetryEvent.MeetingDuration(seconds: 3_600), .under2h)
        XCTAssertEqual(TelemetryEvent.MeetingDuration(seconds: 10_000), .over2h)
        XCTAssertEqual(TelemetryEvent.InterfaceLanguage(localization: "zh-Hans"), .zhHans)
        XCTAssertEqual(TelemetryEvent.InterfaceLanguage(localization: "ja"), .other)
        XCTAssertEqual(TelemetryEvent.InterfaceLanguage(localization: nil), .other)
        XCTAssertEqual(TelemetryEvent.LicenseState(.revoked), .expired)
        XCTAssertEqual(TelemetryEvent.LicenseState(.needsTrial), .none)
        XCTAssertEqual(TelemetryEvent.Profile(RefinementProfile(name: "Clean", instructions: "")), .custom,
                       "A user profile named like a built-in is still custom")
        for profile in RefinementProfile.defaults {
            XCTAssertNotEqual(TelemetryEvent.Profile(profile), .custom)
        }
    }
}
