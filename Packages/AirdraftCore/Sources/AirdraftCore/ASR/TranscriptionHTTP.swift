import Foundation

/// Shared transport only. Each transcriber owns its provider's request/response contract.
struct TranscriptionHTTP: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await HTTPDeadline.data(for: request, session: session,
                                                       timeoutError: TranscriberError.timedOut,
                                                       invalidResponse: TranscriberError.invalidResponse)
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriberError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let data = try await send(request)
        guard let reply = try? JSONDecoder().decode(type, from: data) else { throw TranscriberError.invalidResponse }
        return reply
    }

    static func requireKey(_ key: String?, provider: String) throws -> String {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw TranscriberError.missingAPIKey(provider)
        }
        return key
    }
}

extension TranscriptionHints {
    var languageCode: String? {
        guard let code = language?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { return nil }
        return code
    }

    var isoLanguage: String? { languageCode?.split(separator: "-").first.map { $0.lowercased() } }

    /// Keep dictionary input deterministic and within a modest request budget.
    var vocabularyTerms: [String] {
        var seen = Set<String>()
        return vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
