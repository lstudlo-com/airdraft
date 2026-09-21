import Foundation
import Observation

/// Shared state for speech and refinement key fields. Failed reads cannot turn
/// into accidental deletes; delayed operations cannot populate another provider.
@MainActor
@Observable
public final class CredentialEditor {
    public var value = ""
    public private(set) var savedValue = ""
    public private(set) var needsAccess = false
    public private(set) var isBusy = false
    public private(set) var message: String?
    public private(set) var failed = false
    @ObservationIgnored private var account = ""
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let read: @Sendable (String, Bool) async throws -> String?
    @ObservationIgnored private let write: @Sendable (String, String) async -> Bool

    public init(
        read: @escaping @Sendable (String, Bool) async throws -> String? = { account, allowed in
            try await Task.detached { try Keychain.read(account, allowInteraction: allowed) }.value
        },
        write: @escaping @Sendable (String, String) async -> Bool = { value, account in
            await Task.detached { Keychain.set(value, for: account) }.value
        }
    ) {
        self.read = read
        self.write = write
    }

    public var key: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var canSave: Bool { !isBusy && !account.isEmpty && key != savedValue }

    public func load(account: String, allowInteraction: Bool = false) async {
        let token = UUID()
        generation = token
        self.account = account
        value = ""
        savedValue = ""
        needsAccess = false
        message = nil
        failed = false
        isBusy = true
        defer { if generation == token { isBusy = false } }
        do {
            let stored = try await read(account, allowInteraction)
            guard generation == token, !Task.isCancelled else { return }
            value = stored ?? ""
            savedValue = key
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            needsAccess = (error as? Keychain.AccessError) == .authorizationRequired
            message = needsAccess ? "Your saved key needs access approval." : error.localizedDescription
            failed = true
        }
    }

    public func authorize() async {
        guard !isBusy else { return }
        await load(account: account, allowInteraction: true)
    }

    public func save() async {
        guard canSave else { return }
        let token = generation
        let value = key
        isBusy = true
        let ok = await write(value, account)
        guard generation == token, !Task.isCancelled else { return }
        isBusy = false
        if ok {
            savedValue = value
            needsAccess = false
            message = value.isEmpty ? "API key removed." : "API key saved."
            failed = false
        } else {
            message = "Could not save the API key. The existing key was not replaced."
            failed = true
        }
    }

    public func cancel() {
        generation = UUID()
        isBusy = false
    }
}
