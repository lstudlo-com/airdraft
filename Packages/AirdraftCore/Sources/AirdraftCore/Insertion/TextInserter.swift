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
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "insert")
    /// How long the pasted text stays on the clipboard before the previous contents return.
    public var restoreDelay: TimeInterval = 1.0

    public init() {}

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
        guard AXIsProcessTrusted() else {
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
        let ok = await insertViaPaste(text, onDelivered: onDelivered)
        return ok
            ? InsertionResult(method: .paste, notice: nil)
            : InsertionResult(method: .clipboardOnly, notice: "Couldn't paste, text copied")
    }

    // MARK: - Focus

    public func captureTarget() async -> InsertionTarget? {
        guard !Task.isCancelled, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return await Self.captureTarget(processID: app.processIdentifier, bundleID: app.bundleIdentifier,
            isFrontmost: { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier },
            readFocus: {
                let element = self.focusedElement(pid: app.processIdentifier)
                return (element, element.flatMap(self.selection))
            }, enableWebAccessibility: {
                guard AXIsProcessTrusted() else { return false }
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.3)
                // Electron documents this attribute for third-party assistive
                // clients. Unsupported apps reject it without changing focus.
                return AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString,
                                                     kCFBooleanTrue) == .success
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
        guard let app = NSRunningApplication(processIdentifier: target.processID), !app.isTerminated,
              app.bundleIdentifier == target.bundleID else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processID {
            guard app.activate() else { return false }
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
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID,
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
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        let appFocus = focusedElement(in: app, pid: pid)
        if let appFocus, selection(appFocus) != nil { return appFocus }
        // Some editors report a window at application level while the system
        // reports the actual editor. Never accept a system field from another PID.
        let systemFocus = focusedElement(in: AXUIElementCreateSystemWide(), pid: pid)
        if let systemFocus, selection(systemFocus) != nil { return systemFocus }
        return appFocus ?? systemFocus
    }

    private func focusedElement(in root: AXUIElement, pid: Int32) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(root, 0.3)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let element = ref as! AXUIElement
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }

    private func selection(_ element: AXUIElement) -> CFRange? {
        Self.selection { attribute in
            var ref: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute, &ref)
            return (status, ref)
        }
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
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        guard role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole else { return .notAttempted }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue, let before = value(focused), let range = selection(focused),
              Self.selectionMatches(target.selection, range),
              let expected = Self.replacing(before, range: range, with: text) else { return .notAttempted }
        return await Self.verifiedWrite(before: before, expected: expected, isCurrent: { matches(target) }, write: {
            let status = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
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
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success else { return nil }
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

        guard (postPaste ?? postCommandV)() else { return false }
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

    private func postCommandV() -> Bool {
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
