import AirdraftCore
import PostHog
import XCTest

/// The app's telemetry wiring, with disposable settings. No SDK is set up and
/// nothing is sent: these tests run in Debug, where no client may exist.
@MainActor
final class TelemetryServiceTests: XCTestCase {
    private let official: [String: Any] = ["AirdraftDistribution": "official",
                                           "AirdraftTelemetryToken": "phc_TestOnly0123456789",
                                           "AirdraftTelemetryHost": "https://us.i.posthog.com"]

    /// Only official non-Debug builds with valid configuration offer telemetry; a Debug build never
    /// constructs the PostHog client even with an official plist and consent; community and isolated
    /// containers have no client and hide the choice.
    func testOnlyOfficialReleaseBuildsOfferTelemetryAndDebugOrIsolatedNeverConstructAClient() throws {
        do {
            XCTAssertTrue(TelemetryService.availability(info: official, isolated: false, isDebugBuild: false).isOffered)
            XCTAssertFalse(TelemetryService.availability(info: official, isolated: false, isDebugBuild: true).isOffered)
            XCTAssertFalse(TelemetryService.availability(info: official, isolated: true, isDebugBuild: false).isOffered)
            var community = official
            community["AirdraftDistribution"] = "community"
            XCTAssertFalse(TelemetryService.availability(info: community, isolated: false, isDebugBuild: false).isOffered)
            var unconfigured = official
            unconfigured["AirdraftTelemetryToken"] = ""
            XCTAssertFalse(TelemetryService.availability(info: unconfigured, isolated: false, isDebugBuild: false).isOffered)
            XCTAssertTrue(TelemetryService.isDebugBuild, "App tests run the Debug configuration")
        }

        do {
            let fixture = IsolatedContainer()
            defer { fixture.tearDown() }
            let settings = fixture.container.settings
            settings.telemetryConsent = .granted
            let bundle = try plistBundle(official)
            let telemetry = TelemetryService.make(settings: settings, bundle: bundle, isolated: false)
            XCTAssertTrue(telemetry.availability.isOfficial)
            XCTAssertNotNil(telemetry.availability.configuration)
            XCTAssertFalse(telemetry.availability.isOffered)
            telemetry.start()
            telemetry.choose(.denied)
            telemetry.choose(.granted)
            telemetry.record(.dictationFailed(.permission))
            XCTAssertNil(telemetry.client)
            XCTAssertFalse(telemetry.isSending)
            XCTAssertTrue(PostHogSDK.shared.isOptOut(), "The shared SDK was never set up")
        }

        do {
            let fixture = IsolatedContainer()
            defer { fixture.tearDown() }
            let telemetry = fixture.container.telemetry
            XCTAssertFalse(telemetry.availability.isOfficial, "Isolated containers are community builds")
            XCTAssertFalse(telemetry.showsChoice)
            XCTAssertFalse(telemetry.needsDecision)
            telemetry.choose(.granted)
            XCTAssertNil(telemetry.client)
            XCTAssertTrue(PostHogSDK.shared.isOptOut())
            // The real bundle running these tests is a community Debug build.
            XCTAssertFalse(TelemetryService.availability(info: Bundle.main.infoDictionary ?? [:], isolated: false).isOffered)
        }
    }

    /// Every bundled catalogue ID passes the allowlist; the launch event uses only enumerated fields.
    func testBundledCatalogueIDsAndTheLaunchEventPassTheAllowlist() {
        do {
            let sanitizer = TelemetrySanitizer(isKnownModel: { TelemetryService.knownModelIDs.contains($0) })
            XCTAssertFalse(TelemetryService.knownModelIDs.isEmpty)
            for id in TelemetryService.knownModelIDs.sorted() {
                XCTAssertTrue(sanitizer.allows(event: "model_download_finished",
                                               properties: ["model": id, "outcome": "ok", "app": TelemetrySanitizer.appTag]), id)
            }
            let entry = try? XCTUnwrap(ModelCatalogue.entries.first { $0.isDownloadable })
            if let entry { XCTAssertEqual(TelemetryService.catalogueID(for: entry.config(from: ASRConfig())), entry.id) }
            var custom = ASRConfig(kind: .openAICompatible)
            custom.baseURL = "http://192.168.1.20:1234/v1"
            XCTAssertEqual(TelemetryService.catalogueID(for: custom), "other")
        }

        do {
            let event = TelemetryService.launchEvent(license: .trial(until: .distantFuture))
            var properties = event.properties
            properties["app"] = TelemetrySanitizer.appTag
            XCTAssertEqual(properties["license_state"], "trial")
            XCTAssertEqual(Set(properties.keys), ["app_version", "app_build", "macos_major", "arch", "interface_language",
                                                  "license_state", "app"])
        }
    }

    func testPurgeRemovesOnlyTheSDKFoldersInsideTheGivenRoots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-telemetry-purge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("Application Support"), caches = root.appendingPathComponent("Caches")
        let token = "phc_TestOnly0123456789", bundle = "com.lstudlo.app.airdraft"
        let queue = support.appendingPathComponent(bundle).appendingPathComponent(token)
        let other = support.appendingPathComponent(bundle).appendingPathComponent("keep.json")
        let crash = caches.appendingPathComponent("com.plausiblelabs.crashreporter.data").appendingPathComponent(bundle)
        for directory in [queue, crash] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        try Data("x".utf8).write(to: other)
        PostHogTelemetryClient.purgeLocalData(token: "../etc", bundleID: bundle, support: support, caches: caches)
        PostHogTelemetryClient.purgeLocalData(token: token, bundleID: "../x", support: support, caches: caches)
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.path))
        PostHogTelemetryClient.purgeLocalData(token: token, bundleID: bundle, support: support, caches: caches)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: crash.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    /// A disposable bundle whose Info.plist carries the given keys.
    private func plistBundle(_ info: [String: Any]) throws -> Bundle {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TelemetryFixture-\(UUID().uuidString).bundle")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        var plist = info
        plist["CFBundleIdentifier"] = "com.lstudlo.app.airdraft.telemetry-fixture"
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(Bundle(url: url))
    }
}
