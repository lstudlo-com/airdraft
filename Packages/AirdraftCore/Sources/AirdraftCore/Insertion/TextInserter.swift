import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import os

public enum InsertionMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Try Accessibility first, fall back to paste.
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
@MainActor
public struct InsertionTarget {
    let processID: Int32
    let bundleID: String?
    let element: AXUIElement?
    let selection: CFRange?
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
        var processID: (AXUIElement) -> Int32?
        var readAttribute: (AXUIElement, CFString) -> (AXError, CFTypeRef?)
        var isSettable: (AXUIElement, CFString) -> Bool
        var writeAttribute: (AXUIElement, CFString, CFTypeRef) -> AXError
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
            systemFocus: { copyFocus(in: AXUIElementCreateSystemWide()) }, processID: { element in
                var pid: pid_t = 0
                return AXUIElementGetPid(element, &pid) == .success ? pid : nil
            }, readAttribute: { element, attribute in
                var ref: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, attribute, &ref)
                return (status, ref)
            }, isSettable: { element, attribute in
                var settable: DarwinBoolean = false
                return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
            }, writeAttribute: { AXUIElementSetAttributeValue($0, $1, $2) }, enableWebAccessibility: { pid in
                guard AXIsProcessTrusted() else { return false }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.3)
                return AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
            }, postPaste: { postCommandV() }, pasteboard: .general)
        }

        private static func copyFocus(in root: AXUIElement) -> AXUIElement? {
            AXUIElementSetMessagingTimeout(root, 0.3)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
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
            let unavailable = target?.element == nil || target?.selection == nil
            Self.log.notice("insert: destination unavailable=\(unavailable, privacy: .public)")
            return InsertionResult(method: .clipboardOnly, notice: unavailable
                ? "Couldn't verify the destination's cursor. Text copied; paste it where you want."
                : "Destination changed. Text copied; paste it where you want.")
        }

        if method == .auto {
            let result = await insertViaAccessibility(text, target: target)
            // Verification yields while the destination updates. Cancelled sessions
            // must not replace the clipboard or fall through to a paste afterwards.
            guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
            switch result {
            case .inserted:
                onDelivered?()
                return InsertionResult(method: .accessibility, notice: nil)
            case .uncertain:
                copyOnly(text)
                return InsertionResult(method: .clipboardOnly, notice: "Check the destination before pasting. Text copied; insertion could not be verified.")
            case .notAttempted, .rejected: break
            }
        }
        // Focus can change during an AX request too. Revalidate before posting a paste.
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        guard matches(target) else {
            copyOnly(text)
            return InsertionResult(method: .clipboardOnly, notice: "Destination changed. Text copied.")
        }
        let ok = await insertViaPaste(text, pasteboard: environment.pasteboard,
                                     postPaste: environment.postPaste, onDelivered: onDelivered)
        return ok
            ? InsertionResult(method: .paste, notice: nil)
            : InsertionResult(method: .clipboardOnly, notice: "Couldn't paste, text copied")
    }

    // MARK: - Focus

    public func captureTarget() async -> InsertionTarget? {
        guard !Task.isCancelled, let app = environment.frontmostApplication() else { return nil }
        return await Self.captureTarget(processID: app.processID, bundleID: app.bundleID,
            isFrontmost: { self.environment.frontmostApplication()?.processID == app.processID },
            readFocus: {
                let element = self.focusedElement(pid: app.processID)
                return (element, element.flatMap(self.selection))
            }, enableWebAccessibility: {
                guard self.environment.isTrusted() else { return false }
                // Electron documents this attribute for third-party assistive
                // clients. Unsupported apps reject it without changing focus.
                return self.environment.enableWebAccessibility(app.processID)
            })
    }

    static func captureTarget(processID: Int32, bundleID: String?, isFrontmost: () -> Bool,
                              readFocus: () -> (AXUIElement?, CFRange?),
                              enableWebAccessibility: () -> Bool) async -> InsertionTarget? {
        guard !Task.isCancelled, isFrontmost() else { return nil }
        var (element, range) = readFocus()
        if (element == nil || !selectionMatches(range, range)), enableWebAccessibility() {
            // Creating the web accessibility tree is asynchronous. Capture its
            // real field and caret before recording, never substitute nil == nil.
            _ = await waitForMatch {
                guard isFrontmost() else { return false }
                (element, range) = readFocus()
                return element != nil && selectionMatches(range, range)
            }
        }
        guard !Task.isCancelled, isFrontmost() else { return nil }
        return InsertionTarget(processID: processID, bundleID: bundleID, element: element, selection: range)
    }

    private func restoreFocus(to target: InsertionTarget) async -> Bool {
        guard let app = environment.application(target.processID), app.bundleID == target.bundleID else { return false }
        if environment.frontmostApplication()?.processID != target.processID {
            guard environment.activate(target.processID) else { return false }
            // Being frontmost can precede the editor's focused-field update.
            return await Self.waitForMatch { self.matches(target) }
        }
        return matches(target)
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
        guard environment.frontmostApplication()?.processID == target.processID,
              let original = target.element, let current = focusedElement(pid: target.processID),
              CFEqual(original, current) else { return false }
        return Self.selectionMatches(target.selection, selection(current))
    }

    static func selectionMatches(_ expected: CFRange?, _ current: CFRange?) -> Bool {
        guard let expected, let current, expected.location >= 0, expected.length >= 0,
              expected.length <= Int.max - expected.location else { return false }
        return expected.location == current.location && expected.length == current.length
    }

    private func focusedElement(pid: Int32) -> AXUIElement? {
        guard environment.isTrusted() else { return nil }
        let appFocus = ownedFocus(environment.applicationFocus(pid), pid: pid)
        if let appFocus, selection(appFocus) != nil { return appFocus }
        // Some editors report a window at application level while the system
        // reports the actual editor. Never accept a system field from another PID.
        let systemFocus = ownedFocus(environment.systemFocus(), pid: pid)
        if let systemFocus, selection(systemFocus) != nil { return systemFocus }
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

    // MARK: - Accessibility

    enum WriteResult: Equatable { case notAttempted, rejected, inserted, uncertain }

    private func insertViaAccessibility(_ text: String, target: InsertionTarget) async -> WriteResult {
        guard matches(target), let focused = target.element else { return .notAttempted }
        let (_, roleRef) = environment.readAttribute(focused, kAXRoleAttribute as CFString)
        let role = roleRef as? String ?? ""
        guard role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole else { return .notAttempted }
        guard environment.isSettable(focused, kAXSelectedTextAttribute as CFString),
              let before = value(focused), let range = selection(focused),
              Self.selectionMatches(target.selection, range),
              let expected = Self.replacing(before, range: range, with: text) else { return .notAttempted }
        return await Self.verifiedWrite(before: before, expected: expected, isCurrent: { matches(target) }, write: {
            let status = environment.writeAttribute(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if status != .success {
                Self.log.notice("insert: Accessibility write returned \(status.rawValue, privacy: .public)")
            }
            return status
        }, read: { value(focused) })
    }

    static func verifiedWrite(before: String, expected: String, isCurrent: () -> Bool,
                              write: () -> AXError, read: () -> String?,
                              verificationTimeout: Duration = .milliseconds(500)) async -> WriteResult {
        guard !Task.isCancelled, isCurrent() else { return .notAttempted }
        switch write() {
        case .success: break
        case .attributeUnsupported, .notImplemented:
            // The destination rejected this operation. Only allow the paste
            // fallback while the original field, selection and value are intact.
            return !Task.isCancelled && isCurrent() && read() == before ? .rejected : .uncertain
        default:
            // A timeout or transport error can arrive after the write took effect.
            // Neither that error nor an unchanged value permits another insertion.
            return .uncertain
        }

        // Some apps expose a cached AXValue that lags the accepted write. Read
        // that same element until it catches up; never repeat the write itself.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: verificationTimeout)
        while !Task.isCancelled {
            if read() == expected { return .inserted }
            let now = clock.now
            guard now < deadline else { break }
            do {
                try await clock.sleep(until: min(deadline, now.advanced(by: .milliseconds(25))))
            } catch { break }
        }
        return .uncertain
    }

    static func replacing(_ value: String, range: CFRange, with text: String) -> String? {
        let original = value as NSString
        guard range.location >= 0, range.length >= 0, range.location <= original.length,
              range.length <= original.length - range.location else { return nil }
        return original.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
    }

    private func value(_ element: AXUIElement) -> String? {
        let (status, ref) = environment.readAttribute(element, kAXValueAttribute as CFString)
        guard status == .success else { return nil }
        return ref as? String
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
        try? await Task.sleep(for: .seconds(restoreDelay))
        // Restore only if nobody replaced the clipboard in the meantime.
        if pasteboard.changeCount == ourChange {
            restore(pasteboard, items: saved)
        }
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
