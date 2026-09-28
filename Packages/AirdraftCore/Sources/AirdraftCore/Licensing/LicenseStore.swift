import Foundation
import Observation

public struct LicenseRecord: Codable, Sendable {
    public var installationID = UUID()
    public var trialStartedAt: Date?
    public var trialEndsAt: Date?
    public var lastSeenAt: Date?
    public var grant: Grant?
    public var activationPending = false
    public init() {}

    public struct Grant: Codable, Sendable {
        public var key: String
        public var activationID: UUID
        public var organizationID: UUID
        public var benefitID: UUID
        public var expiresAt: Date?
        public var verifiedAt: Date
        public var revoked = false
    }
}

public protocol LicenseStorage: Sendable {
    func read(allowInteraction: Bool) async throws -> LicenseRecord?
    func write(_ record: LicenseRecord) async throws
}

public struct KeychainLicenseStorage: LicenseStorage {
    // Separate Debug and Release license receipts; provider keys keep their existing scope.
    private let account: String
    public init(bundleID: String) { account = "license.\(bundleID).v1" }
    public func read(allowInteraction: Bool) async throws -> LicenseRecord? {
        try await Task.detached {
            let value: String?
            do { value = try Keychain.read(account, allowInteraction: allowInteraction) }
            catch { throw LicenseError.storageLocked }
            guard let value else { return nil }
            do { return try JSONDecoder().decode(LicenseRecord.self, from: Data(value.utf8)) }
            catch { throw LicenseError.storage }
        }.value
    }
    public func write(_ record: LicenseRecord) async throws {
        try await Task.detached {
            let data = try JSONEncoder().encode(record)
            guard let value = String(data: data, encoding: .utf8),
                  Keychain.set(value, for: account, allowInteraction: false) else {
                throw LicenseError.storage
            }
        }.value
    }
}

@MainActor @Observable public final class LicenseStore {
    public enum Distribution: Equatable, Sendable { case community, official }
    public enum Access: Equatable, Sendable {
        case community, loading, unconfigured, needsTrial, trial(until: Date)
        case licensed, expired, revoked, locked, clockChanged
        public var allowsUse: Bool {
            switch self { case .community, .trial, .licensed: true; default: false }
        }
    }
    public let distribution: Distribution
    public let configuration: PolarConfiguration?
    public private(set) var isBusy = false
    public private(set) var message: String?
    public private(set) var isOffline = false
    public private(set) var record: LicenseRecord?
    public private(set) var loaded = false
    public private(set) var storageBlocked = false
    public var isPresented = false
    public var deviceLabel: String? { record.map { PolarLicenseClient.deviceLabel(for: $0.installationID) } }
    private let storage: any LicenseStorage
    private let client: (any PolarLicensing)?
    private let now: @Sendable () -> Date

    public init(distribution: Distribution, configuration: PolarConfiguration?, storage: any LicenseStorage,
                client: (any PolarLicensing)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.distribution = distribution
        self.configuration = configuration
        self.storage = storage
        self.client = client ?? configuration.map { PolarLicenseClient(configuration: $0) }
        self.now = now
    }

    public var access: Access {
        if distribution == .community { return .community }
        guard configuration != nil else { return .unconfigured }
        guard loaded else { return .loading }
        guard !storageBlocked, let record else { return .locked }
        let date = now()
        if let grant = record.grant,
           grant.organizationID == configuration?.organizationID, grant.benefitID == configuration?.benefitID {
            if grant.revoked { return .revoked }
            if grant.expiresAt.map({ date >= $0 }) ?? false { return .expired }
            return .licensed
        }
        if let last = record.lastSeenAt, date < last.addingTimeInterval(-300) { return .clockChanged }
        guard let end = record.trialEndsAt else { return .needsTrial }
        return date < end ? .trial(until: end) : .expired
    }

    /// Passive reads never authorize a Keychain dialog. Only the named UI action does.
    public func load(allowInteraction: Bool = false) async {
        guard distribution == .official, configuration != nil, !isBusy else { return }
        isBusy = true
        defer { isBusy = false; loaded = true }
        do {
            record = try await storage.read(allowInteraction: allowInteraction) ?? LicenseRecord()
            storageBlocked = false
            message = nil
        } catch {
            storageBlocked = true
            message = error.localizedDescription
        }
    }

    public func startTrial() async {
        guard access == .needsTrial, !isBusy, var next = record, let configuration else { return }
        isBusy = true
        defer { isBusy = false }
        let date = now()
        next.trialStartedAt = date
        next.trialEndsAt = date.addingTimeInterval(Double(configuration.trialDays) * 86_400)
        next.lastSeenAt = date
        do { try await save(next); message = nil }
        catch { message = error.localizedDescription }
    }

    /// Called at the boundary of new work only. Never stops an active recording
    /// or blocks recovery, history, export, provider setup or model downloads.
    public func requireAccess() async throws {
        guard access.allowsUse else {
            if access == .clockChanged { throw LicenseError.clockChanged }
            throw LicenseError.accessRequired
        }
        if case .trial = access, var next = record {
            guard !isBusy else { throw LicenseError.accessRequired }
            isBusy = true
            defer { isBusy = false }
            next.lastSeenAt = max(next.lastSeenAt ?? .distantPast, now())
            try await save(next)
            guard access.allowsUse else { throw LicenseError.accessRequired }
        }
    }

    public func activate(_ input: String) async {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isBusy, !storageBlocked, loaded, var next = record,
              let client, let configuration else { return }
        guard next.grant == nil else {
            message = "Deactivate this Mac before replacing its license key."
            return
        }
        guard !next.activationPending else { message = LicenseError.activationUncertain.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Reject a key from another product before allocating a device slot.
            _ = try await client.validate(key: key, activationID: nil, installationID: next.installationID)
            // Persist before the non-idempotent request. A lost response must not
            // silently create a second seat on the next launch or button press.
            next.activationPending = true
            try await save(next)
            let (activation, license) = try await client.activate(key: key, installationID: next.installationID)
            next.grant = .init(key: key, activationID: activation, organizationID: configuration.organizationID,
                               benefitID: configuration.benefitID, expiresAt: license.expiresAt, verifiedAt: now())
            next.activationPending = false
            do { try await save(next) }
            catch {
                // Best effort compensation. A failure leaves the pending marker
                // in place and the customer portal remains the recovery path.
                try? await client.deactivate(key: key, activationID: activation)
                throw LicenseError.storage
            }
            isOffline = false
            message = nil
        } catch {
            if error as? LicenseError == .rejected || error as? LicenseError == .activationLimit {
                next.activationPending = false
                try? await save(next)
            }
            message = (record?.activationPending == true && error as? LicenseError == .unavailable)
                ? LicenseError.activationUncertain.localizedDescription : error.localizedDescription
        }
    }

    /// Explicit acknowledgement after the user has inspected the hosted portal.
    public func acknowledgePendingActivation() async {
        guard !isBusy, var next = record else { return }
        isBusy = true
        defer { isBusy = false }
        next.activationPending = false
        do { try await save(next); message = nil }
        catch { message = error.localizedDescription }
    }

    /// Rotation preserves the server activation. Validate its replacement key
    /// against the original seat instead of allocating another device.
    public func updateKey(_ input: String) async {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isBusy, !storageBlocked, var next = record,
              var grant = next.grant, let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let license = try await client.validate(key: key, activationID: grant.activationID, installationID: next.installationID)
            grant.key = key
            grant.expiresAt = license.expiresAt
            grant.verifiedAt = now()
            grant.revoked = false
            next.grant = grant
            try await save(next)
            isOffline = false
            message = nil
        } catch { message = error.localizedDescription }
    }

    /// Only after explicit confirmation that the user removed this named device
    /// in the portal. A 404 with a rotated key cannot prove remote removal.
    public func forgetRemovedActivation() async {
        guard !isBusy, !storageBlocked, var next = record, next.grant?.revoked == true else { return }
        isBusy = true
        defer { isBusy = false }
        next.grant = nil
        do { try await save(next); message = nil; isOffline = false }
        catch { message = error.localizedDescription }
    }

    public func refresh() async {
        guard !isBusy, !storageBlocked, var next = record, var grant = next.grant, let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let license = try await client.validate(key: grant.key, activationID: grant.activationID, installationID: next.installationID)
            grant.expiresAt = license.expiresAt
            grant.verifiedAt = now()
            grant.revoked = false
            next.grant = grant
            try await save(next)
            isOffline = false
            message = nil
        } catch {
            if error as? LicenseError == .rejected {
                grant.revoked = true
                next.grant = grant
                // Reject for this session even if the disk is locked or full.
                record = next
                do { try await storage.write(next) }
                catch { storageBlocked = true }
                isOffline = false
            } else { isOffline = true }
            message = error.localizedDescription
        }
    }

    public func deactivate() async {
        guard !isBusy, var next = record, let grant = next.grant, let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            do { try await client.deactivate(key: grant.key, activationID: grant.activationID) }
            catch where error as? LicenseError == .rejected {
                next.grant?.revoked = true
                record = next
                do { try await storage.write(next) }
                catch { storageBlocked = true }
                message = "Removal could not be confirmed. Update a rotated key, or remove this device in the customer portal before forgetting it here."
                return
            }
            next.grant = nil
            // A completed server revocation must not leave an in-memory unlock.
            record = next
            do { try await storage.write(next) }
            catch { storageBlocked = true; throw error }
            message = nil
            isOffline = false
        } catch { message = error.localizedDescription }
    }

    private func save(_ next: LicenseRecord) async throws {
        try await storage.write(next)
        record = next
    }
}
