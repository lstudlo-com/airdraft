import Foundation
import os

/// Shared deadline and resource deletion, independent of provider payloads.
enum CloudSpeechResources {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "cloud-speech")

    static func request(_ url: URL, method: String = "GET", key: String, header: String = "Authorization",
                        prefix: String = "Bearer ", deadline: Date) throws -> URLRequest {
        try Task.checkCancellation()
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw TranscriberError.timedOut }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = remaining
        request.setValue(prefix + key, forHTTPHeaderField: header)
        return request
    }

    static func isResourceID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil
    }

    static func pause(interval: TimeInterval, deadline: Date) async throws {
        try Task.checkCancellation()
        guard deadline.timeIntervalSinceNow > 0 else { throw TranscriberError.timedOut }
        try await Task.sleep(for: .seconds(min(max(0.01, interval), deadline.timeIntervalSinceNow)))
    }

    /// Callers supply only a validated ID from this invocation and a fixed provider host.
    static func delete(_ url: URL?, key: String, header: String = "Authorization", prefix: String = "Bearer ",
                       http: TranscriptionHTTP) async {
        guard let url else { return }
        // Cancellation of the recording must not cancel its cleanup attempt.
        await Task.detached {
            do {
                let request = try request(url, method: "DELETE", key: key, header: header, prefix: prefix,
                                          deadline: Date().addingTimeInterval(2))
                _ = try await http.send(request)
            } catch {
                log.warning("Cloud speech cleanup failed. Check the provider console for retained resources.")
            }
        }.value
    }
}
