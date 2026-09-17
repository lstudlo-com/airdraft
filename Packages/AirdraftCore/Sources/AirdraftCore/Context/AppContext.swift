import Foundation

/// What the user is looking at when they dictate. Everything is optional;
/// the pipeline degrades gracefully when Accessibility is unavailable.
public struct AppContext: Codable, Sendable, Equatable {
    public var bundleId: String?
    public var appName: String?
    public var windowTitle: String?
    public var url: String?
    public var selectedText: String?
    public var textBeforeCursor: String?
    public var textAfterCursor: String?
    /// Final text of the last few dictations into the same app (oldest first).
    public var recentDictations: [String]
    /// Process id of the app that was frontmost when recording started.
    public var processID: Int32?

    public init(
        bundleId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        selectedText: String? = nil,
        textBeforeCursor: String? = nil,
        textAfterCursor: String? = nil,
        recentDictations: [String] = [],
        processID: Int32? = nil
    ) {
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.textBeforeCursor = textBeforeCursor
        self.textAfterCursor = textAfterCursor
        self.recentDictations = recentDictations
        self.processID = processID
    }

    public static let empty = AppContext()

    public var hasSelection: Bool {
        guard let s = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !s.isEmpty
    }
}
