import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import os

public enum InsertionMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Legacy automatic setting; uses the same validated paste path as `paste`.
    case auto
    /// Always paste (clipboard is restored afterwards).
    case paste
    public var id: String { rawValue }
}

public struct InsertionResult: Sendable, Equatable {
    public enum Method: String, Sendable { case accessibility, paste, clipboardOnly }
    public let method: Method
    public let notice: String?
    public var didInsert: Bool { method != .clipboardOnly }
}

/// Local insertion identity, never serialized or sent to a provider.
/// With `element` and `selection`, delivery requires that field and caret.
/// Editors that draw their own text (Zed, Warp, other GPU terminals) expose
/// no caret; their target is the process and its focused window instead.
@MainActor
public struct InsertionTarget {
    let processID: Int32
    let bundleID: String?
    let element: AXUIElement?
    let selection: CFRange?
    var window: AXUIElement? = nil
}

/// Puts text at the cursor of the app the user was dictating into.
@MainActor
public final class TextInserter {
    /// The OS boundary is injectable so regression tests execute capture,
    /// validation and delivery together without touching real apps or clipboard.
    @MainActor
    struct Environment {
        struct Application {
            let processID: Int32
            let bundleID: String?
        }
        var frontmostApplication: () -> Application?
        var application: (Int32) -> Application?
        var activate: (Int32) -> Bool
        var isTrusted: () -> Bool
        var applicationFocus: (Int32) -> AXUIElement?
        var systemFocus: () -> AXUIElement?
        var focusedWindow: (Int32) -> AXUIElement?
        var processID: (AXUIElement) -> Int32?
        var readAttribute: (AXUIElement, CFString) -> (AXError, CFTypeRef?)
        var enableWebAccessibility: (Int32) -> Bool
        var postPaste: () -> Bool
        var pasteboard: NSPasteboard

        static var live: Environment {
            Environment(frontmostApplication: {
                NSWorkspace.shared.frontmostApplication.map { Application(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
            }, application: { pid in
                guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
                return Application(processID: app.processIdentifier, bundleID: app.bundleIdentifier)
            }, activate: { NSRunningApplication(processIdentifier: $0)?.activate() == true },
            isTrusted: { AXIsProcessTrusted() }, applicationFocus: { copyFocus(in: AXUIElementCreateApplication($0)) },
            systemFocus: { copyFocus(in: AXUIElementCreateSystemWide()) },
            focusedWindow: { copyFocus(in: AXUIElementCreateApplication($0), attribute: kAXFocusedWindowAttribute) },
            processID: { element in
                var pid: pid_t = 0
                return AXUIElementGetPid(element, &pid) == .success ? pid : nil
            }, readAttribute: { element, attribute in
                var ref: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, attribute, &ref)
                return (status, ref)
            }, enableWebAccessibility: { pid in
                guard AXIsProcessTrusted() else { return false }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.3)
                return AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
            }, postPaste: { postCommandV() }, pasteboard: .general)
        }

        private static func copyFocus(in root: AXUIElement,
                                      attribute: String = kAXFocusedUIElementAttribute) -> AXUIElement? {
            AXUIElementSetMessagingTimeout(root, 0.3)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, attribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
            let element = ref as! AXUIElement
            AXUIElementSetMessagingTimeout(element, 0.3)
            return element
        }
    }

    private let environment: Environment
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "insert")
    /// How long the pasted text stays on the clipboard before the previous contents return.
    public var restoreDelay: TimeInterval = 1.0

    public init() { environment = .live }
    init(environment: Environment) { self.environment = environment }

    public func insert(_ text: String, method: InsertionMethod = .auto, target: InsertionTarget? = nil,
                       onDelivered: (() -> Void)? = nil) async -> InsertionResult {
        guard !Task.isCancelled, !text.isEmpty else { return InsertionResult(method: .clipboardOnly, notice: nil) }

        // Dictated while airdraft itself was in front: there is nowhere sensible to type.
        if let bundle = target?.bundleID, bundle == Bundle.main.bundleIdentifier {
            copyOnly(text)
            Self.log.notice("insert: target is airdraft, copied only")
            return InsertionResult(method: .clipboardOnly, notice: "Copied to clipboard")
        }

        // Bring the original app back if focus moved while we were transcribing.
        guard environment.isTrusted() else {
            copyOnly(text)
            Self.log.error("insert: Accessibility not granted, copied only")
            return InsertionResult(method: .clipboardOnly, notice: "Accessibility is off, text copied")
        }
        let restored = if let target { await restoreFocus(to: target) } else { false }
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        guard restored, let target else {
            copyOnly(text)
            Self.log.notice("insert: destination unavailable=\(target == nil, privacy: .public)")
            return InsertionResult(method: .clipboardOnly, notice: target == nil
                ? "Couldn't identify the destination app. Text copied; paste it where you want."
                : "Destination changed. Text copied; paste it where you want.")
        }

        // Both persisted settings use one paste operation. AXSelectedText can
        // report writable and still fail or expose a stale value after a write.
        // Probing it by writing made ordinary dictation impossible to recover
        // safely: a subsequent paste could duplicate text. AX is read-only here.
        // Revalidate immediately before changing the clipboard and posting ⌘V.
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        guard await Self.waitForMatch(matches: { self.matches(target) }) else {
            guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
            copyOnly(text)
            Self.log.notice("insert: destination changed before paste")
            return InsertionResult(method: .clipboardOnly, notice: "Destination changed. Text copied.")
        }
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        Self.log.notice("insert: paste verified by \(target.selection == nil ? "app window" : "field and caret", privacy: .public)")
        let ok = await insertViaPaste(text, pasteboard: environment.pasteboard,
                                     postPaste: environment.postPaste, onDelivered: onDelivered)
        return ok
            ? InsertionResult(method: .paste, notice: nil)
            : InsertionResult(method: .clipboardOnly, notice: "Couldn't paste, text copied")
    }

    // MARK: - Focus

    public func captureTarget() async -> InsertionTarget? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(1500))
        // Recording has not begun yet. Follow an in-flight app switch instead
        // of retaining the old app or discarding the destination altogether.
        while !Task.isCancelled, clock.now < deadline {
            if let app = environment.frontmostApplication() {
                var webAccessibility: Bool?
                let target = await Self.captureTarget(processID: app.processID, bundleID: app.bundleID,
                    timeout: clock.now.duration(to: deadline),
                    isFrontmost: { self.environment.frontmostApplication()?.processID == app.processID },
                    readFocus: {
                        let element = self.focusedElement(pid: app.processID)
                        return (element, element.flatMap(self.selection))
                    }, readWindow: {
                        self.environment.isTrusted() ? self.environment.focusedWindow(app.processID) : nil
                    }, enableWebAccessibility: {
                        guard self.environment.isTrusted() else { return false }
                        webAccessibility = self.environment.enableWebAccessibility(app.processID)
                        return webAccessibility!
                    })
                if let target {
                    logCapture(target, webAccessibility: webAccessibility)
                    return target
                }
            }
            do { try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(25)))) }
            catch { return nil }
        }
        return nil
    }

    /// How long an app that rejected the web accessibility request must keep
    /// the same caretless focus before capture accepts its app-level target.
    static let caretlessSettleTime: Duration = .milliseconds(250)

    static func captureTarget(processID: Int32, bundleID: String?, timeout: Duration = .milliseconds(500),
                              isFrontmost: () -> Bool,
                              readFocus: () -> (AXUIElement?, CFRange?),
                              readWindow: () -> AXUIElement? = { nil },
                              enableWebAccessibility: () -> Bool) async -> InsertionTarget? {
        guard !Task.isCancelled, isFrontmost() else { return nil }
        var element: AXUIElement?
        var range: CFRange?
        var stableSince: ContinuousClock.Instant?
        var webAccessibility: Bool?
        var caretSettled = false
        _ = await waitForMatch(timeout: timeout) {
            // Stop this attempt promptly. The caller may follow the newly
            // frontmost app while still inside the shared capture deadline.
            guard isFrontmost() else { return true }
            let (next, selection) = readFocus()
            let sameField = (element == nil && next == nil) || (element != nil && next != nil && CFEqual(element!, next!))
            let sameSelection = (range == nil && selection == nil) || selectionMatches(range, selection)
            if !sameField || !sameSelection { stableSince = nil }
            element = next
            range = selection
            let now = ContinuousClock.now
            if stableSince == nil { stableSince = now }
            let stable = stableSince!.duration(to: now)
            if next != nil, selectionMatches(selection, selection) {
                // AX and NSWorkspace can briefly expose the previous editor during
                // activation. Yield the run loop and require a stable field/caret.
                caretSettled = stable >= .milliseconds(50)
                return caretSettled
            }
            caretSettled = false
            if webAccessibility == nil { webAccessibility = enableWebAccessibility() }
            // Electron publishes its editor some time after accepting the request
            // above, so it keeps the full wait. Editors that draw their own text
            // never publish a caret; waiting for one only delays recording.
            return webAccessibility == false && stable >= caretlessSettleTime
        }
        guard !Task.isCancelled, isFrontmost() else { return nil }
        return InsertionTarget(processID: processID, bundleID: bundleID,
                               element: caretSettled ? element : nil, selection: caretSettled ? range : nil,
                               window: readWindow())
    }

    /// Records which verification a destination gets, so a caretless editor
    /// can be diagnosed from the log. Contains no text or field values.
    private func logCapture(_ target: InsertionTarget, webAccessibility: Bool?) {
        guard target.selection == nil else {
            Self.log.notice("capture: field and caret")
            return
        }
        let focus = focusedElement(pid: target.processID)
        let role = focus.flatMap { environment.readAttribute($0, kAXRoleAttribute as CFString).1 as? String } ?? "none"
        let selectionStatus = focus.map { environment.readAttribute($0, kAXSelectedTextRangeAttribute as CFString).0.rawValue }
        Self.log.notice("""
            capture: app window app=\(target.bundleID ?? "?", privacy: .public) role=\(role, privacy: .public) \
            selectionStatus=\(selectionStatus.map(String.init) ?? "none", privacy: .public) \
            window=\(target.window != nil, privacy: .public) web=\(webAccessibility.map(String.init) ?? "none", privacy: .public)
            """)
    }

    private func restoreFocus(to target: InsertionTarget) async -> Bool {
        guard let app = environment.application(target.processID), app.bundleID == target.bundleID else { return false }
        if environment.frontmostApplication()?.processID != target.processID {
            guard environment.activate(target.processID) else { return false }
        }
        // AX focus can lag even while the same app remains frontmost. Require
        // the original destination, allowing a bounded read-only wait.
        return await Self.waitForMatch(timeout: .milliseconds(1500)) { self.matches(target) }
    }

    static func waitForMatch(timeout: Duration = .milliseconds(500), matches: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !Task.isCancelled {
            if matches() { return true }
            let now = clock.now
            guard now < deadline else { return false }
            do { try await clock.sleep(until: min(deadline, now.advanced(by: .milliseconds(25)))) }
            catch { return false }
        }
        return false
    }

    private func matches(_ target: InsertionTarget) -> Bool {
        guard environment.frontmostApplication()?.processID == target.processID else { return false }
        let matched: Bool
        if let original = target.element, let caret = target.selection {
            guard let current = focusedElement(pid: target.processID), CFEqual(original, current) else { return false }
            matched = Self.selectionMatches(caret, selection(current))
        } else {
            matched = applicationMatches(target)
        }
        return matched && environment.frontmostApplication()?.processID == target.processID
    }

    /// A caretless editor is verified by what it does expose: keyboard focus
    /// stays in the same process and, when the app reports one, the same window.
    private func applicationMatches(_ target: InsertionTarget) -> Bool {
        guard environment.isTrusted() else { return false }
        if let system = environment.systemFocus(), environment.processID(system) != target.processID { return false }
        guard let window = target.window else { return true }
        guard let current = environment.focusedWindow(target.processID) else { return false }
        return CFEqual(window, current)
    }

    static func selectionMatches(_ expected: CFRange?, _ current: CFRange?) -> Bool {
        guard let expected, let current, expected.location >= 0, expected.length >= 0,
              expected.length <= Int.max - expected.location else { return false }
        return expected.location == current.location && expected.length == current.length
    }

    private func focusedElement(pid: Int32) -> AXUIElement? {
        guard environment.isTrusted() else { return nil }
        let appFocus = ownedFocus(environment.applicationFocus(pid), pid: pid)
        // Keyboard events go to system focus. The application's own cached AX
        // field can still describe its previous editor while activation settles.
        let rawSystemFocus = environment.systemFocus()
        let systemFocus = ownedFocus(rawSystemFocus, pid: pid)
        if rawSystemFocus != nil, systemFocus == nil { return nil }
        if let systemFocus, selection(systemFocus) != nil { return systemFocus }
        if let appFocus, selection(appFocus) != nil { return appFocus }
        return appFocus ?? systemFocus
    }

    private func ownedFocus(_ element: AXUIElement?, pid: Int32) -> AXUIElement? {
        guard let element, environment.processID(element) == pid else { return nil }
        return element
    }

    private func selection(_ element: AXUIElement) -> CFRange? {
        Self.selection { environment.readAttribute(element, $0) }
    }

    static func selection(readAttribute: (CFString) -> (AXError, CFTypeRef?)) -> CFRange? {
        let (status, ref) = readAttribute(kAXSelectedTextRangeAttribute as CFString)
        if status == .success { return selectionRange(ref) }
        guard status == .attributeUnsupported || status == .noValue else { return nil }
        let (rangesStatus, rangesRef) = readAttribute(kAXSelectedTextRangesAttribute as CFString)
        guard rangesStatus == .success, let rangesRef, CFGetTypeID(rangesRef) == CFArrayGetTypeID(),
              let ranges = rangesRef as? [AnyObject], ranges.count == 1 else { return nil }
        // Multiple carets would paste into more than the captured selection.
        return selectionRange(ranges[0])
    }

    private static func selectionRange(_ ref: CFTypeRef?) -> CFRange? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID(),
              AXValueGetType(ref as! AXValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range), selectionMatches(range, range) else { return nil }
        return range
    }

    // MARK: - Paste

    func insertViaPaste(_ text: String, pasteboard: NSPasteboard = .general,
                        postPaste: (() -> Bool)? = nil, onDelivered: (() -> Void)? = nil) async -> Bool {
        let saved = snapshot(pasteboard)

        // Only on the clipboard long enough to paste: keep it off other devices
        // (Universal Clipboard) and out of clipboard-manager history.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        guard (postPaste ?? Self.postCommandV)() else { return false }
        // Delivery feedback must not wait for clipboard restoration.
        onDelivered?()
        // The receiving app handles the posted event asynchronously. Once it is
        // posted, cancellation must not restore the old clipboard before that
        // app reads it. This unstructured task owns the short restoration delay
        // independently of the cancelled dictation; it never posts another key.
        let delay = restoreDelay
        await Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            // Restore only if nobody replaced the clipboard in the meantime.
            if pasteboard.changeCount == ourChange {
                self.restore(pasteboard, items: saved)
            }
        }.value
        return true
    }

    private func copyOnly(_ text: String) {
        environment.pasteboard.clearContents()
        environment.pasteboard.setString(text, forType: .string)
    }

    private func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private func restore(_ pb: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(restored)
    }

    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return false }
        // Explicit flags so a still-held modifier (e.g. the hotkey) cannot leak into ⌘V.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
