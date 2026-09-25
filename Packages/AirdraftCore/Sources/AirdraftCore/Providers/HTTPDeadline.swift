import Foundation

enum HTTPDeadline {
    /// URLSession's request timeout is an inactivity timer. Race a wall-clock
    /// deadline as well, so a slowly trickling response cannot wait forever.
    static func data(for request: URLRequest, session: URLSession, timeoutError: Error, invalidResponse: Error) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
            group.addTask {
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { throw invalidResponse }
                    return (data, http)
                } catch let error as URLError where error.code == .timedOut {
                    throw timeoutError
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(max(0, request.timeoutInterval)))
                throw timeoutError
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw invalidResponse }
            return result
        }
    }
}

enum ProviderErrorBody {
    /// The provider's own message from a JSON error body, or short plain text.
    /// Raw JSON and HTML pages are not shown to the user.
    static func summary(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) {
            return message(in: object).map { String($0.prefix(200)) }
        }
        guard !trimmed.hasPrefix("<") else { return nil }
        return String(trimmed.prefix(200))
    }

    private static func message(in object: Any) -> String? {
        if let text = object as? String { return text }
        guard let dict = object as? [String: Any] else { return (object as? [Any])?.first.flatMap(message(in:)) }
        for key in ["message", "error", "detail", "error_message", "msg"] {
            if let value = dict[key], let text = message(in: value) { return text }
        }
        return nil
    }
}
