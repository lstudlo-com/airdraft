import Foundation

/// Audio, prompts and authenticated provider responses must not share persistent
/// URL loading state. Anonymous model downloads deliberately use their own transport.
enum ProviderTransport {
    static let shared = makeSession()

    static func makeSession(timeout: TimeInterval = 60) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = timeout
        return URLSession(configuration: configuration, delegate: ProviderRedirectPolicy(), delegateQueue: nil)
    }

    /// Compare with the original request so every hop remains inside its origin.
    static func allowsRedirect(from source: URL?, to destination: URL?) -> Bool {
        guard let source, let destination,
              let original = Origin(source), let redirected = Origin(destination) else { return false }
        return original == redirected
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ url: URL) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = components.host?.lowercased(), !host.isEmpty else { return nil }
            self.scheme = scheme
            self.host = host
            self.port = components.port ?? (scheme == "https" ? 443 : 80)
            guard (1...65535).contains(port) else { return nil }
        }
    }
}

private final class ProviderRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(ProviderTransport.allowsRedirect(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}
