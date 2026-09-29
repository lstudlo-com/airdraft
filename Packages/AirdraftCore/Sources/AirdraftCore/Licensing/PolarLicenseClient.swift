import Foundation

/// Public merchant identifiers only. Never put a Polar access token in a client.
public struct PolarConfiguration: Equatable, Sendable {
    public let organizationID: UUID
    public let benefitIDs: Set<UUID>
    public let checkoutURL: URL
    public let portalURL: URL
    public let trialDays: Int

    public static func parseBenefitIDs(_ value: String) -> Set<UUID>? {
        let entries = value.split(separator: ",", omittingEmptySubsequences: false)
        let ids = entries.compactMap { UUID(uuidString: String($0)) }
        let unique = Set(ids)
        guard !ids.isEmpty, ids.count == entries.count, unique.count == ids.count,
              !unique.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) else { return nil }
        return unique
    }

    public static func parseCheckoutURL(_ value: String) -> URL? {
        publicURL(value, hosts: ["polar.sh", "buy.polar.sh"])
    }

    public static func parsePortalURL(_ value: String) -> URL? {
        publicURL(value, hosts: ["polar.sh"])
    }

    private static func publicURL(_ value: String, hosts: Set<String>) -> URL? {
        guard !value.contains(where: { "$\n\r\t".contains($0) }),
              let url = URL(string: value), url.scheme == "https",
              let host = url.host, hosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil,
              !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else { return nil }
        return url
    }

    public init(organizationID: UUID, benefitIDs: Set<UUID>, checkoutURL: URL, portalURL: URL, trialDays: Int = 14) {
        self.organizationID = organizationID
        self.benefitIDs = benefitIDs
        self.checkoutURL = checkoutURL
        self.portalURL = portalURL
        self.trialDays = trialDays
    }
}

public struct PolarLicense: Decodable, Sendable {
    public let id: UUID
    public let organizationID: UUID
    public let benefitID: UUID
    public let status: String
    public let expiresAt: Date?
    public let activation: Activation?
    public struct Activation: Decodable, Sendable { public let id: UUID }
    enum CodingKeys: String, CodingKey {
        case id, status, activation
        case organizationID = "organization_id", benefitID = "benefit_id", expiresAt = "expires_at"
    }
}

public enum LicenseError: Error, LocalizedError, Equatable, Sendable {
    case rejected, activationLimit, unavailable, invalidResponse, storage, storageLocked, notConfigured
    case accessRequired, clockChanged, activationUncertain
    public var errorDescription: String? {
        switch self {
        case .rejected: "This license or device activation is no longer valid. Check your key and devices in the customer portal."
        case .activationLimit: "Activation was refused. Check the license and available device slots in the customer portal."
        case .unavailable: "Polar could not be reached. Your saved license has been kept. Try again when connected."
        case .invalidResponse: "The license response could not be verified. Your saved license has been kept."
        case .storage: "Could not save the license in Keychain. Access has not been changed."
        case .storageLocked: "Your license needs Keychain access. Choose Allow Access in License to restore it."
        case .notConfigured: "This official build is missing its licensing configuration. Contact Airdraft support."
        case .accessRequired: "Open License to start your trial or activate a purchased key. Your history remains available."
        case .clockChanged: "The system clock moved backwards. Correct the date and time to continue your trial."
        case .activationUncertain: "Activation may have reserved a device slot. Open the customer portal and remove that pending device before trying again."
        }
    }
}

public protocol PolarLicensing: Sendable {
    func validate(key: String, activationID: UUID?, installationID: UUID) async throws -> PolarLicense
    func activate(key: String, installationID: UUID) async throws -> (UUID, PolarLicense)
    func deactivate(key: String, activationID: UUID) async throws
}

public struct PolarLicenseClient: PolarLicensing {
    public static func deviceLabel(for installationID: UUID) -> String {
        "Airdraft · \(installationID.uuidString.prefix(8))"
    }
    private let config: PolarConfiguration
    private let session: URLSession
    public init(configuration: PolarConfiguration, session: URLSession? = nil) {
        config = configuration
        let transport = URLSessionConfiguration.ephemeral
        transport.httpCookieStorage = nil
        transport.urlCache = nil
        transport.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: transport, delegate: PolarRedirectPolicy(), delegateQueue: nil)
    }

    public func validate(key: String, activationID: UUID?, installationID: UUID) async throws -> PolarLicense {
        // Polar accepts one optional benefit filter. Validate the returned benefit
        // against our full allowlist before LicenseStore can allocate a device.
        var body: [String: Any] = ["key": key, "organization_id": config.organizationID.uuidString]
        if let activationID {
            body["activation_id"] = activationID.uuidString
            body["conditions"] = ["installation_id": installationID.uuidString]
        }
        let data = try await request("validate", body: body)
        let license = try decode(PolarLicense.self, data)
        try check(license)
        if let activationID, license.activation?.id != activationID { throw LicenseError.invalidResponse }
        return license
    }

    public func activate(key: String, installationID: UUID) async throws -> (UUID, PolarLicense) {
        let data = try await request("activate", body: ["key": key,
            "organization_id": config.organizationID.uuidString, "label": Self.deviceLabel(for: installationID),
            "conditions": ["installation_id": installationID.uuidString]])
        struct Response: Decodable {
            let id: UUID
            let licenseKey: PolarLicense
            enum CodingKeys: String, CodingKey { case id, licenseKey = "license_key" }
        }
        let response = try decode(Response.self, data)
        do { try check(response.licenseKey) }
        catch { throw LicenseError.invalidResponse }
        return (response.id, response.licenseKey)
    }

    public func deactivate(key: String, activationID: UUID) async throws {
        _ = try await request("deactivate", body: ["key": key,
            "organization_id": config.organizationID.uuidString, "activation_id": activationID.uuidString])
    }

    private func check(_ license: PolarLicense) throws {
        guard license.organizationID == config.organizationID, config.benefitIDs.contains(license.benefitID),
              license.status == "granted", license.expiresAt.map({ $0 > Date() }) ?? true else {
            throw LicenseError.rejected
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = parser.date(from: value) { return date }
            parser.formatOptions = [.withInternetDateTime]
            guard let date = parser.date(from: value) else { throw LicenseError.invalidResponse }
            return date
        }
        do { return try decoder.decode(type, from: data) }
        catch { throw LicenseError.invalidResponse }
    }

    private func request(_ operation: String, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/\(operation)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw LicenseError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw LicenseError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw LicenseError.rejected
        case 403 where operation == "activate": throw LicenseError.activationLimit
        default: throw LicenseError.unavailable
        }
    }
}

/// License keys must never follow a redirect to another endpoint or host.
private final class PolarRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
