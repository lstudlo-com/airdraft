import Foundation

/// Routing is saved per model. An empty provider lets OpenRouter choose.
public struct OpenRouterRouting: Codable, Sendable, Equatable {
    public var providerID: String
    public var allowFallbacks: Bool

    public init(providerID: String = "", allowFallbacks: Bool = false) {
        self.providerID = providerID
        self.allowFallbacks = allowFallbacks
    }

    var preferences: [String: Any]? {
        guard !providerID.isEmpty else { return nil }
        var result: [String: Any] = ["order": [providerID], "allow_fallbacks": allowFallbacks]
        if !allowFallbacks { result["only"] = [providerID] }
        return result
    }
}

/// One actual model/host variant, rather than model-wide advertised performance.
public struct OpenRouterEndpoint: Decodable, Sendable, Identifiable {
    public let name: String
    public let providerName: String
    public let tag: String
    public let status: Int?
    public let contextLength: Int?
    public let maxCompletionTokens: Int?
    public let quantization: String?
    public let pricing: Pricing?
    public let throughput: Measurement?
    public let latency: Measurement?
    public let uptime: Double?

    public var id: String { tag }
    public var title: String {
        let variant = tag.split(separator: "/").dropFirst().joined(separator: "/")
        return variant.isEmpty ? providerName : "\(providerName) · \(variant)"
    }

    enum CodingKeys: String, CodingKey {
        case name, tag, status, pricing, quantization
        case providerName = "provider_name", contextLength = "context_length"
        case maxCompletionTokens = "max_completion_tokens"
        case throughput = "throughput_last_30m", latency = "latency_last_30m"
        case uptime = "uptime_last_30m"
    }

    /// The API reports percentile objects; older responses used a scalar.
    public struct Measurement: Decodable, Sendable {
        public let value: Double?
        public let isMedian: Bool

        public init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let number = try? single.decode(Double.self) {
                value = number.isFinite && number >= 0 ? number : nil
                isMedian = false
            } else {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                let number = try values.decodeIfPresent(Double.self, forKey: .p50)
                value = number.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                isMedian = true
            }
        }

        enum CodingKeys: String, CodingKey { case p50 }
    }

    public struct Pricing: Decodable, Sendable {
        public let prompt: Double?
        public let completion: Double?
        public let cachedInput: Double?

        enum CodingKeys: String, CodingKey {
            case prompt, completion
            case cachedInput = "input_cache_read"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) -> Double? {
                let value: Double?
                if let string = try? c.decode(String.self, forKey: key) { value = Double(string) }
                else { value = try? c.decode(Double.self, forKey: key) }
                return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            }
            prompt = number(.prompt)
            completion = number(.completion)
            cachedInput = number(.cachedInput)
        }
    }
}

public enum OpenRouterCatalog {
    /// Catalog entries for comparison, not a prediction of routing eligibility.
    /// Base slugs group standard endpoints; exact variants show only their entry.
    /// Service tiers require explicit opt-in and are not reached by a base slug.
    public static func relatedEndpoints(providerID: String, in endpoints: [OpenRouterEndpoint]) -> [OpenRouterEndpoint] {
        guard !providerID.isEmpty else { return [] }
        return endpoints.filter {
            $0.tag == providerID || (!providerID.contains("/") && $0.tag.hasPrefix(providerID + "/")
                && !["flex", "priority", "fast"].contains($0.tag.split(separator: "/").last.map(String.init) ?? ""))
        }
    }

    public static func endpointsURL(model: String) throws -> URL {
        // Routing variants use the base model's metadata; :free is a separate catalog entry.
        var model = model
        for suffix in [":nitro", ":floor", ":online"] where model.hasSuffix(suffix) {
            model.removeLast(suffix.count)
        }
        let parts = model.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !model.contains("?"), !model.contains("#") else { throw RefinerError.invalidResponse }
        return URL(string: "https://openrouter.ai/api/v1/models")!
            .appendingPathComponent(String(parts[0])).appendingPathComponent(String(parts[1]))
            .appendingPathComponent("endpoints")
    }

    public static func decode(_ data: Data) throws -> [OpenRouterEndpoint] {
        struct Reply: Decodable {
            struct Model: Decodable { let endpoints: [OpenRouterEndpoint] }
            let data: Model
        }
        let endpoints = try JSONDecoder().decode(Reply.self, from: data).data.endpoints
        var seen = Set<String>()
        return endpoints.filter { !$0.tag.isEmpty && seen.insert($0.tag).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Public metadata needs no credential access and sends no user text.
    public static func fetch(model: String, session: URLSession = .shared) async throws -> [OpenRouterEndpoint] {
        var request = URLRequest(url: try endpointsURL(model: model))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RefinerError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                    body: String(decoding: data, as: UTF8.self))
        }
        return try decode(data)
    }
}
