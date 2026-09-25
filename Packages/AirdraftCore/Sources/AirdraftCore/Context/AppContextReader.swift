import AppKit
import ApplicationServices
import Foundation

/// Reads the frontmost app and, when Accessibility is granted, the focused
/// text field's selection and surrounding text. Every AX call is bounded by
/// a short messaging timeout so a hung app cannot stall dictation.
@MainActor
public final class AppContextReader {
    public var maxBeforeChars = 1000
    public var maxAfterChars = 300
    public var maxSelectionChars = 5000

    public init() {}

    /// Password managers: their window titles and fields must never reach a refinement provider.
    static let privateApps: Set<String> = [
        "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password",
        "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc", "com.lastpass.LastPass",
    ]

    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt the first time.
    public static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public func read() -> AppContext {
        var ctx = AppContext()
        guard let app = NSWorkspace.shared.frontmostApplication else { return ctx }
        ctx.bundleId = app.bundleIdentifier
        ctx.appName = app.localizedName
        ctx.processID = app.processIdentifier

        guard Self.isAccessibilityTrusted,
              !Self.privateApps.contains(app.bundleIdentifier ?? "") else { return ctx }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)

        if let window: AXUIElement = attribute(appElement, kAXFocusedWindowAttribute) {
            AXUIElementSetMessagingTimeout(window, 0.3)
            ctx.windowTitle = attribute(window, kAXTitleAttribute) as String?
            if let doc: String = attribute(window, kAXDocumentAttribute), doc.hasPrefix("http") {
                ctx.url = doc
            }
        }

        guard let focused: AXUIElement = attribute(appElement, kAXFocusedUIElementAttribute) else { return ctx }
        AXUIElementSetMessagingTimeout(focused, 0.3)

        if ctx.url == nil, let url: String = attribute(focused, "AXURL" as CFString), url.hasPrefix("http") {
            ctx.url = url
        }
        if ctx.url == nil, let web = findWebArea(from: focused, depth: 6),
           let url: String = attribute(web, "AXURL" as CFString), url.hasPrefix("http") {
            ctx.url = url
        }

        let role: String? = attribute(focused, kAXRoleAttribute)
        // Password fields: no selection or surrounding text, whatever the app reports.
        if let subrole: String = attribute(focused, kAXSubroleAttribute), subrole == kAXSecureTextFieldSubrole {
            return ctx
        }
        if let sel: String = attribute(focused, kAXSelectedTextAttribute), !sel.isEmpty {
            ctx.selectedText = String(sel.prefix(maxSelectionChars))
        }

        // Value + selected range gives us text around the cursor for plain
        // text fields. Web areas are skipped: their AXValue is the whole page.
        if role != "AXWebArea",
           let value: String = attribute(focused, kAXValueAttribute),
           let rangeValue: AXValue = attribute(focused, kAXSelectedTextRangeAttribute) {
            var range = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &range) {
                let utf16 = Array(value.utf16)
                let loc = max(0, min(range.location, utf16.count))
                let end = max(loc, min(range.location + range.length, utf16.count))
                let before = String(utf16CodeUnits: Array(utf16[max(0, loc - maxBeforeChars)..<loc]), count: min(loc, maxBeforeChars))
                let after = String(utf16CodeUnits: Array(utf16[end..<min(utf16.count, end + maxAfterChars)]), count: min(utf16.count - end, maxAfterChars))
                ctx.textBeforeCursor = before
                ctx.textAfterCursor = after
            }
        }
        return ctx
    }

    // MARK: - AX helpers

    private func attribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name, &value)
        guard status == .success, let value else { return nil }
        return value as? T
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        attribute(element, name as CFString)
    }

    private func findWebArea(from element: AXUIElement, depth: Int) -> AXUIElement? {
        var current = element
        for _ in 0..<depth {
            if let role: String = attribute(current, kAXRoleAttribute), role == "AXWebArea" { return current }
            guard let parent: AXUIElement = attribute(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }
}
