import XCTest
@testable import AirdraftCore

private let organization = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let benefit = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let fiveMacBenefit = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
private let activation = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let licenseConfig = PolarConfiguration(organizationID: organization, benefitIDs: [benefit],
    checkoutURL: URL(string: "https://polar.sh/checkout/test-only")!, portalURL: URL(string: "https://polar.sh/test-only/portal")!)

private actor MemoryLicenseStorage: LicenseStorage {
    var value: LicenseRecord?
    var failRead = false
    var failWrite = false
    var writes = 0
    init(_ value: LicenseRecord? = nil) { self.value = value }
    func read(allowInteraction: Bool) throws -> LicenseRecord? {
        if failRead { throw LicenseError.storageLocked }; return value
    }
    func write(_ record: LicenseRecord) throws {
        if failWrite { throw LicenseError.storage }; value = record; writes += 1
    }
    func fail(read: Bool = false, write: Bool = false) { failRead = read; failWrite = write }
}

private actor LicenseFixtureClient: PolarLicensing {
    var failure: LicenseError?
    var activationFailure: LicenseError?
    var activations = 0
    var validations = 0
    var rejectedKeys: Set<String> = []
    var lastValidationActivation: UUID?
    func rejectKey(_ key: String) { rejectedKeys.insert(key) }
    func setFailure(_ value: LicenseError?) { failure = value }
    func failActivation() { activationFailure = .unavailable }
    func validate(key: String, activationID: UUID?, installationID: UUID) throws -> PolarLicense {
        validations += 1
        lastValidationActivation = activationID
        if rejectedKeys.contains(key) { throw LicenseError.rejected }
        if let failure { throw failure }
        return fixtureLicense()
    }
    func activate(key: String, installationID: UUID) throws -> (UUID, PolarLicense) {
        activations += 1
        if let activationFailure { throw activationFailure }
        return (activation, fixtureLicense())
    }
    func deactivate(key: String, activationID: UUID) throws {
        if rejectedKeys.contains(key) { throw LicenseError.rejected }
        if let failure { throw failure }
    }
    private func fixtureLicense() -> PolarLicense {
        PolarLicense(id: UUID(), organizationID: organization, benefitID: benefit, status: "granted", expiresAt: nil, activation: .init(id: activation))
    }
}

@MainActor final class LicensingTests: XCTestCase {
    func testBuildConfigurationCannotCrossPolarEnvironments() {
        for environment in PolarEnvironment.allCases {
            let host = environment == .sandbox ? "sandbox.polar.sh" : "polar.sh"
            var info: [String: Any] = ["AirdraftPolarEnvironment": environment.rawValue,
                "AirdraftPolarOrganization": organization.uuidString,
                "AirdraftPolarBenefits": "\(benefit),\(fiveMacBenefit)",
                "AirdraftCheckoutURL": "https://\(host)/checkout/test-only",
                "AirdraftCustomerPortalURL": "https://\(host)/test-only/portal",
                "AirdraftTrialDays": "14"]
            XCTAssertEqual(PolarConfiguration.from(info: info, environment: environment)?.environment, environment)
            let other: PolarEnvironment = environment == .sandbox ? .production : .sandbox
            XCTAssertNil(PolarConfiguration.from(info: info, environment: other))
            info["AirdraftPolarEnvironment"] = nil
            XCTAssertNil(PolarConfiguration.from(info: info, environment: environment))
            info["AirdraftPolarEnvironment"] = environment.rawValue
            info["AirdraftCheckoutURL"] = "https://\(other == .sandbox ? "sandbox.polar.sh" : "buy.polar.sh")/checkout/test-only"
            XCTAssertNil(PolarConfiguration.from(info: info, environment: environment))
        }
    }

    func testSandboxURLsAndReceiptsAreIsolatedFromProduction() {
        XCTAssertNotNil(PolarConfiguration.parseCheckoutURL("https://sandbox.polar.sh/checkout/test-only", environment: .sandbox))
        XCTAssertNotNil(PolarConfiguration.parsePortalURL("https://sandbox.polar.sh/test-only/portal", environment: .sandbox))
        for value in ["https://polar.sh/checkout/test-only", "https://buy.polar.sh/polar_cl_test-only",
                      "https://sandbox.polar.sh.evil.test/a", "https://user@sandbox.polar.sh/a", "https://sandbox.polar.sh:443/a"] {
            XCTAssertNil(PolarConfiguration.parseCheckoutURL(value, environment: .sandbox))
            XCTAssertNil(PolarConfiguration.parsePortalURL(value, environment: .sandbox))
        }
        let bundle = "com.lstudlo.app.airdraft"
        XCTAssertEqual(KeychainLicenseStorage.accountName(bundleID: bundle, environment: .production), "license.\(bundle).v1")
        XCTAssertNotEqual(KeychainLicenseStorage.accountName(bundleID: bundle, environment: .production),
                          KeychainLicenseStorage.accountName(bundleID: bundle, environment: .sandbox))
        XCTAssertNotEqual(KeychainLicenseStorage.accountName(bundleID: bundle, environment: .sandbox),
                          KeychainLicenseStorage.accountName(bundleID: bundle + ".debug", environment: .sandbox))
    }

    func testSandboxPersistentCheckoutAcceptsOnlyTheCheckoutRedirectRoute() {
        let link = "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_test-only/redirect"
        XCTAssertNotNil(PolarConfiguration.parseCheckoutURL(link, environment: .sandbox))
        XCTAssertNil(PolarConfiguration.parseCheckoutURL(link, environment: .production))
        XCTAssertNil(PolarConfiguration.parsePortalURL(link, environment: .sandbox))
        for value in ["https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_/redirect",
                      "https://sandbox-api.polar.sh/v1/customer-portal/license-keys/activate",
                      "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_test-only",
                      "https://sandbox-api.polar.sh.evil.test/v1/checkout-links/polar_cl_test/redirect",
                      "https://user@sandbox-api.polar.sh/v1/checkout-links/polar_cl_test/redirect",
                      "https://sandbox-api.polar.sh:443/v1/checkout-links/polar_cl_test/redirect"] {
            XCTAssertNil(PolarConfiguration.parseCheckoutURL(value, environment: .sandbox), value)
        }
    }

    func testBenefitAllowlistRejectsEmptyMalformedAndDuplicateConfiguration() {
        XCTAssertEqual(PolarConfiguration.parseBenefitIDs("\(benefit),\(fiveMacBenefit)"), [benefit, fiveMacBenefit])
        XCTAssertEqual(PolarConfiguration.parseBenefitIDs(benefit.uuidString), [benefit])
        for value in ["", "bad", "\(benefit),", "\(benefit),bad", "\(benefit),\(benefit)",
                      "00000000-0000-0000-0000-000000000000", "$(AIRDRAFT_POLAR_BENEFITS)"] {
            XCTAssertNil(PolarConfiguration.parseBenefitIDs(value), value)
        }
    }

    func testCachedLicenseFromAnUnlistedBenefitDoesNotUnlock() async {
        var record = LicenseRecord()
        record.grant = .init(key: "fixture", activationID: activation, organizationID: organization,
                             benefitID: fiveMacBenefit, verifiedAt: Date())
        let store = make(MemoryLicenseStorage(record))
        await store.load()
        XCTAssertFalse(store.access.allowsUse)
    }

    func testPublicLinksAcceptPolarCheckoutHostWithoutBroadeningPortalHosts() {
        for value in ["https://buy.polar.sh/polar_cl_example", "https://polar.sh/checkout/test-only"] {
            XCTAssertEqual(PolarConfiguration.parseCheckoutURL(value)?.absoluteString, value)
        }
        XCTAssertNotNil(PolarConfiguration.parsePortalURL("https://polar.sh/airdraft/portal"))
        XCTAssertNil(PolarConfiguration.parsePortalURL("https://buy.polar.sh/airdraft/portal"))
        for value in ["http://buy.polar.sh/polar_cl_example", "https://buy.polar.sh.evil.test/link",
                      "https://sandbox.polar.sh/link", "https://polar.sh@evil.test/link",
                      "https://user@buy.polar.sh/link", "https://buy.polar.sh:443/link",
                      "https://buy.polar.sh/", "https://polar.sh/$(TOKEN)", "https://polar.sh/a\nb"] {
            XCTAssertNil(PolarConfiguration.parseCheckoutURL(value), value)
            XCTAssertNil(PolarConfiguration.parsePortalURL(value), value)
        }
    }

    private func make(_ storage: MemoryLicenseStorage, client: LicenseFixtureClient = .init(), date: Date = Date()) -> LicenseStore {
        LicenseStore(distribution: .official, configuration: licenseConfig, storage: storage, client: client, now: { date })
    }

    func testCommunityAndUnconfiguredOfficialStayDistinct() async throws {
        let storage = MemoryLicenseStorage()
        await storage.fail(read: true, write: true)
        let community = LicenseStore(distribution: .community, configuration: nil, storage: storage)
        await community.load()
        try await community.requireAccess()
        XCTAssertEqual(community.access, .community)
        let broken = LicenseStore(distribution: .official, configuration: nil, storage: storage)
        XCTAssertEqual(broken.access, .unconfigured)
        XCTAssertFalse(broken.access.allowsUse)
    }

    func testTrialStartsExplicitlyPersistsAndExpiresAtBoundary() async throws {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let storage = MemoryLicenseStorage()
        let store = make(storage, date: start)
        await store.load()
        XCTAssertEqual(store.access, .needsTrial)
        XCTAssertNil(store.record?.trialStartedAt)
        await store.startTrial()
        XCTAssertEqual(store.access, .trial(until: start.addingTimeInterval(14 * 86_400)))
        try await store.requireAccess()
        let expired = make(storage, date: start.addingTimeInterval(14 * 86_400))
        await expired.load()
        XCTAssertEqual(expired.access, .expired)
        await expired.startTrial()
        XCTAssertEqual(expired.record?.trialStartedAt, start)
        let rolledBack = make(storage, date: start.addingTimeInterval(-3600))
        await rolledBack.load()
        XCTAssertEqual(rolledBack.access, .clockChanged)
    }

    func testDeniedKeychainNeverCreatesAnotherTrialAndFailedWritesNeverUnlock() async {
        let storage = MemoryLicenseStorage()
        await storage.fail(read: true)
        let store = make(storage)
        await store.load()
        XCTAssertEqual(store.access, .locked)
        await store.startTrial()
        XCTAssertNil(store.record)
        await storage.fail(write: true)
        await store.load()
        await store.startTrial()
        XCTAssertEqual(store.access, .needsTrial)
        XCTAssertNotNil(store.message)
    }

    func testPaidOfflineContinuityRevocationAndNoDuplicateActivation() async {
        let storage = MemoryLicenseStorage()
        let client = LicenseFixtureClient()
        let store = make(storage, client: client)
        await store.load()
        await store.activate("fixture-key")
        XCTAssertEqual(store.access, .licensed)
        await store.activate("fixture-key")
        let activations = await client.activations
        XCTAssertEqual(activations, 1)
        await client.setFailure(.unavailable)
        await store.refresh()
        XCTAssertEqual(store.access, .licensed)
        XCTAssertTrue(store.isOffline)
        let restarted = make(storage, client: client)
        await restarted.load()
        XCTAssertEqual(restarted.access, .licensed)
        await client.setFailure(.rejected)
        await restarted.refresh()
        XCTAssertEqual(restarted.access, .revoked)
        let revokedRestart = make(storage)
        await revokedRestart.load()
        XCTAssertEqual(revokedRestart.access, .revoked)
    }

    func testAmbiguousActivationSurvivesRestartAndRequiresExplicitRecovery() async {
        let storage = MemoryLicenseStorage()
        let client = LicenseFixtureClient()
        await client.failActivation()
        let store = make(storage, client: client)
        await store.load()
        await store.activate("fixture-key")
        XCTAssertEqual(store.record?.activationPending, true)
        let restarted = make(storage, client: client)
        await restarted.load()
        await restarted.activate("fixture-key")
        let count = await client.activations
        XCTAssertEqual(count, 1)
        await restarted.acknowledgePendingActivation()
        XCTAssertEqual(restarted.record?.activationPending, false)
    }

    func testWrongProductDoesNotReserveADeviceAndDeactivationDoesNotResetTrial() async {
        let storage = MemoryLicenseStorage()
        let client = LicenseFixtureClient()
        let store = make(storage, client: client)
        await store.load()
        await store.startTrial()
        let originalTrial = store.record?.trialEndsAt
        await client.setFailure(.rejected)
        await store.activate("wrong-product")
        let count = await client.activations
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.record?.activationPending, false)
        await client.setFailure(nil)
        await store.activate("valid-key")
        await store.deactivate()
        XCTAssertNil(store.record?.grant)
        XCTAssertEqual(store.record?.trialEndsAt, originalTrial)
    }

    func testRotatedKeyKeepsItsOriginalSeatEvenAfterFailedDeactivation() async {
        let storage = MemoryLicenseStorage()
        let client = LicenseFixtureClient()
        let store = make(storage, client: client)
        await store.load()
        await store.activate("old-key")
        await client.rejectKey("old-key")
        await store.refresh()
        XCTAssertEqual(store.access, .revoked)
        await store.deactivate()
        XCTAssertEqual(store.record?.grant?.activationID, activation)
        let restarted = make(storage, client: client)
        await restarted.load()
        await restarted.updateKey("replacement-key")
        XCTAssertEqual(restarted.access, .licensed)
        XCTAssertEqual(restarted.record?.grant?.key, "replacement-key")
        XCTAssertEqual(restarted.record?.grant?.activationID, activation)
        let validatedActivation = await client.lastValidationActivation
        let allocations = await client.activations
        XCTAssertEqual(validatedActivation, activation)
        XCTAssertEqual(allocations, 1, "Key rotation must not allocate another seat")
        await client.rejectKey("wrong-replacement")
        await restarted.updateKey("wrong-replacement")
        XCTAssertEqual(restarted.record?.grant?.key, "replacement-key")
        XCTAssertEqual(restarted.access, .licensed)
    }

    func testExplicitPortalCleanupPreservesTrialAndOnlyForgetsInvalidActivation() async {
        let storage = MemoryLicenseStorage()
        let client = LicenseFixtureClient()
        let store = make(storage, client: client)
        await store.load()
        await store.startTrial()
        let end = store.record?.trialEndsAt
        await store.activate("fixture-key")
        await store.forgetRemovedActivation()
        XCTAssertNotNil(store.record?.grant)
        await client.rejectKey("fixture-key")
        await store.refresh()
        await store.forgetRemovedActivation()
        XCTAssertNil(store.record?.grant)
        XCTAssertEqual(store.record?.trialEndsAt, end)
    }
}

final class PolarLicenseWireTests: XCTestCase {
    func testEverySandboxOperationUsesOnlySandboxAndDoesNotFallBack() async throws {
        let config = PolarConfiguration(organizationID: organization, benefitIDs: [benefit],
            checkoutURL: URL(string: "https://sandbox.polar.sh/checkout/test-only")!,
            portalURL: URL(string: "https://sandbox.polar.sh/test-only/portal")!, environment: .sandbox)
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [LicenseURLProtocol.self]
        let session = URLSession(configuration: transport)
        defer { session.invalidateAndCancel() }
        let client = PolarLicenseClient(configuration: config, session: session)
        let installation = UUID()
        let receipt = "{\"id\":\"\(UUID())\",\"organization_id\":\"\(organization)\",\"benefit_id\":\"\(benefit)\",\"status\":\"granted\",\"expires_at\":null,\"activation\":{\"id\":\"\(activation)\"}}"
        var operations: [String] = []
        LicenseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "sandbox-api.polar.sh")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let operation = request.url!.lastPathComponent
            operations.append(operation)
            switch operation {
            case "activate": return (200, "{\"id\":\"\(activation)\",\"license_key\":\(receipt)}")
            case "deactivate": return (204, "")
            default: return (200, receipt)
            }
        }
        _ = try await client.validate(key: "sandbox-fixture", activationID: activation, installationID: installation)
        _ = try await client.activate(key: "sandbox-fixture", installationID: installation)
        try await client.deactivate(key: "sandbox-fixture", activationID: activation)
        XCTAssertEqual(operations, ["validate", "activate", "deactivate"])
        var requests = 0
        LicenseURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "sandbox-api.polar.sh")
            return (503, "")
        }
        do {
            _ = try await client.validate(key: "sandbox-fixture", activationID: activation, installationID: installation)
            XCTFail("Unavailable sandbox must not succeed")
        } catch { XCTAssertEqual(error as? LicenseError, .unavailable) }
        XCTAssertEqual(requests, 1)
        let mixed = PolarConfiguration(organizationID: organization, benefitIDs: [benefit],
            checkoutURL: licenseConfig.checkoutURL, portalURL: config.portalURL, environment: .sandbox)
        do {
            _ = try await PolarLicenseClient(configuration: mixed, session: session).activate(key: "fixture", installationID: installation)
            XCTFail("Mixed environment must fail before making a request")
        } catch { XCTAssertEqual(error as? LicenseError, .notConfigured) }
        XCTAssertEqual(requests, 1)
    }

    @MainActor func testBothPlansPersistTheirOwnBenefitAndRejectOtherProductsBeforeActivation() async throws {
        let config = PolarConfiguration(organizationID: organization, benefitIDs: [benefit, fiveMacBenefit],
            checkoutURL: licenseConfig.checkoutURL, portalURL: licenseConfig.portalURL)
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [LicenseURLProtocol.self]
        let session = URLSession(configuration: transport)
        defer { session.invalidateAndCancel() }
        let client = PolarLicenseClient(configuration: config, session: session)
        for issuedBenefit in [benefit, fiveMacBenefit, UUID()] {
            var allocations = 0
            let receipt = "{\"id\":\"\(UUID())\",\"organization_id\":\"\(organization)\",\"benefit_id\":\"\(issuedBenefit)\",\"status\":\"granted\",\"expires_at\":null,\"activation\":{\"id\":\"\(activation)\"}}"
            LicenseURLProtocol.handler = { request in
                let body = try! JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
                XCTAssertNil(body["benefit_id"])
                XCTAssertEqual(body["organization_id"] as? String, organization.uuidString)
                if request.url?.lastPathComponent == "activate" {
                    allocations += 1
                    return (200, "{\"id\":\"\(activation)\",\"license_key\":\(receipt)}")
                }
                return (200, receipt)
            }
            let storage = MemoryLicenseStorage()
            let store = LicenseStore(distribution: .official, configuration: config, storage: storage, client: client)
            await store.load()
            await store.activate("fixture-key")
            if config.benefitIDs.contains(issuedBenefit) {
                XCTAssertEqual(allocations, 1)
                XCTAssertEqual(store.access, .licensed)
                XCTAssertEqual(store.record?.grant?.benefitID, issuedBenefit)
                LicenseURLProtocol.handler = { _ in (503, "") }
                let restarted = LicenseStore(distribution: .official, configuration: config, storage: storage, client: client)
                await restarted.load()
                await restarted.refresh()
                XCTAssertEqual(restarted.access, .licensed)
                XCTAssertTrue(restarted.isOffline)
                XCTAssertEqual(restarted.record?.grant?.benefitID, issuedBenefit)
            } else {
                XCTAssertEqual(allocations, 0)
                XCTAssertNil(store.record?.grant)
                XCTAssertEqual(store.record?.activationPending, false)
                XCTAssertFalse(store.access.allowsUse)
            }
        }
    }

    func testPublicEndpointShapesAndResponseValidation() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = PolarLicenseClient(configuration: licenseConfig, session: session)
        let installation = UUID()
        let receipt = "{\"id\":\"\(UUID())\",\"organization_id\":\"\(organization)\",\"benefit_id\":\"\(benefit)\",\"status\":\"granted\",\"expires_at\":null,\"activation\":{\"id\":\"\(activation)\"}}"
        LicenseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.polar.sh")
            XCTAssertEqual(request.url?.path, "/v1/customer-portal/license-keys/validate")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let data = Self.body(request)
            let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(body["activation_id"] as? String, activation.uuidString)
            XCTAssertNil(body["benefit_id"], "Check the returned benefit against the allowlist, not a single plan filter")
            XCTAssertEqual((body["conditions"] as? [String: String])?["installation_id"], installation.uuidString)
            XCTAssertNil(body["increment_usage"])
            return (200, receipt)
        }
        _ = try await client.validate(key: "fixture", activationID: activation, installationID: installation)
        for (code, response, expected) in [(404, "", LicenseError.rejected), (500, "", .unavailable),
            (200, receipt.replacingOccurrences(of: benefit.uuidString, with: UUID().uuidString), .rejected),
            (200, receipt.replacingOccurrences(of: organization.uuidString, with: UUID().uuidString), .rejected),
            (200, "{}", .invalidResponse),
            (200, receipt.replacingOccurrences(of: activation.uuidString, with: UUID().uuidString), .invalidResponse)] {
            LicenseURLProtocol.handler = { _ in (code, response) }
            do { _ = try await client.validate(key: "fixture", activationID: activation, installationID: installation); XCTFail("Must reject") }
            catch { XCTAssertEqual(error as? LicenseError, expected) }
        }
        LicenseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "activate")
            let body = try! JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
            XCTAssertEqual(body["label"] as? String, PolarLicenseClient.deviceLabel(for: installation))
            XCTAssertTrue((body["label"] as? String)?.contains(String(installation.uuidString.prefix(8))) == true)
            return (200, "{\"id\":\"\(activation)\",\"license_key\":\(receipt)}")
        }
        let result = try await client.activate(key: "fixture", installationID: installation)
        XCTAssertEqual(result.0, activation)
        LicenseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "deactivate")
            return (204, "")
        }
        try await client.deactivate(key: "fixture", activationID: activation)
    }
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }; result.append(buffer, count: read)
        }
        return result
    }
}

private final class LicenseURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
