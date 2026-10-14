import CryptoKit
import Foundation

/// Remembers a successful compatibility negotiation briefly, never a response,
/// prompt or credential. Each model and set of inference options negotiates
/// independently. Expiry retries the full contract after a server update.
actor RefinerCompatibility {
    static let shared = RefinerCompatibility()

    struct Key: Hashable, Sendable {
        private let digest: Data

        init(endpoint: URL, wire: String, model: String, options: [String: Any], apiKey: String? = nil) throws {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            let scheme = components?.scheme?.lowercased()
            let host = components?.host?.lowercased()
            components?.scheme = scheme
            components?.host = host
            if components?.port == (scheme == "https" ? 443 : 80) { components?.port = nil }
            components?.fragment = nil
            let material: [String: Any] = [
                "endpoint": components?.string ?? endpoint.absoluteString,
                "wire": wire, "model": model, "options": options,
                // Account-dependent compatibility must not survive a credential
                // change. Only the final combined digest is retained in memory.
                "credentialScope": Data(SHA256.hash(data: Data((apiKey ?? "").utf8))).base64EncodedString(),
            ]
            digest = Data(SHA256.hash(data: try JSONSerialization.data(withJSONObject: material, options: [.sortedKeys])))
        }
    }

    private var negotiated: [Key: TimeInterval] = [:]
    private let lifetime: TimeInterval
    private let capacity: Int
    private let clock: @Sendable () -> TimeInterval

    init(lifetime: TimeInterval = 300, capacity: Int = 64,
         clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.lifetime = lifetime
        self.capacity = max(1, capacity)
        self.clock = clock
    }

    func prefersMinimal(_ key: Key) -> Bool {
        guard let recorded = negotiated[key] else { return false }
        guard clock() - recorded < lifetime else {
            negotiated[key] = nil
            return false
        }
        return true
    }

    /// Call only after full 400 + a valid, complete minimal result. A failed
    /// minimal request provides no evidence that the options were unsupported.
    func recordSuccess(_ key: Key) {
        let now = clock()
        negotiated = negotiated.filter { now - $0.value < lifetime }
        if negotiated[key] == nil, negotiated.count >= capacity,
           let oldest = negotiated.min(by: { $0.value < $1.value })?.key {
            negotiated[oldest] = nil
        }
        negotiated[key] = now
    }

    func forget(_ key: Key) { negotiated[key] = nil }
}
