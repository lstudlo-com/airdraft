import Foundation

/// Browser context needs the destination, not a document's private path or URL state.
enum BrowserContextURL {
    static func origin(from value: String) -> String? {
        guard !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
              var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }
}
