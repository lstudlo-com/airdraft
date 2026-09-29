#if DEBUG
import AirdraftCore
import Foundation

@MainActor enum LicensePreview {
    static func container(_ scenario: String) -> AppContainer {
        let org = UUID(), benefit = UUID()
        let environment: PolarEnvironment = scenario == "sandbox" ? .sandbox : .production
        let host = environment == .sandbox ? "sandbox.polar.sh" : "polar.sh"
        let config = PolarConfiguration(organizationID: org, benefitIDs: [benefit],
            checkoutURL: URL(string: "https://\(host)/checkout/preview")!,
            portalURL: URL(string: "https://\(host)/preview/portal")!, environment: environment)
        let now = Date()
        var record = LicenseRecord()
        if scenario == "trial" || scenario == "expired" {
            record.trialStartedAt = now.addingTimeInterval(-86_400)
            record.trialEndsAt = now.addingTimeInterval(scenario == "trial" ? 13 * 86_400 : -1)
        }
        if scenario == "pending" { record.activationPending = true }
        if scenario == "licensed" || scenario == "offline" || scenario == "revoked" {
            let grant: [String: Any] = ["key": "preview-not-a-real-key", "activationID": UUID().uuidString,
                "organizationID": org.uuidString, "benefitID": benefit.uuidString,
                "verifiedAt": now.timeIntervalSinceReferenceDate, "revoked": scenario == "revoked"]
            record.grant = try! JSONDecoder().decode(LicenseRecord.Grant.self, from: JSONSerialization.data(withJSONObject: grant))
        }
        let store = LicenseStore(distribution: scenario == "community" ? .community : .official,
            configuration: scenario == "unconfigured" ? nil : config,
            storage: PreviewStorage(record: record, locked: scenario == "locked"), client: PreviewClient())
        var loaded = false
        Task {
            await store.load()
            if scenario == "offline" { await store.refresh() }
            loaded = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !loaded && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-license-preview-\(UUID())")
        let defaults = UserDefaults(suiteName: "airdraft.license-preview.\(UUID())")!
        return AppContainer(settings: AppSettings(defaults: defaults), dataDirectory: dir, license: store)
    }

    private struct PreviewStorage: LicenseStorage {
        let record: LicenseRecord
        let locked: Bool
        func read(allowInteraction: Bool) throws -> LicenseRecord? {
            if locked { throw LicenseError.storageLocked }; return record
        }
        func write(_ record: LicenseRecord) throws { throw LicenseError.storage }
    }
    private struct PreviewClient: PolarLicensing {
        func validate(key: String, activationID: UUID?, installationID: UUID) throws -> PolarLicense { throw LicenseError.unavailable }
        func activate(key: String, installationID: UUID) throws -> (UUID, PolarLicense) { throw LicenseError.unavailable }
        func deactivate(key: String, activationID: UUID) throws { throw LicenseError.unavailable }
    }
}
#endif
