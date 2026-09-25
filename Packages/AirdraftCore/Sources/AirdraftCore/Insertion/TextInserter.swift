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

    public func insert(_ text: String, method: InsertionMethod = .auto, target: InsertionTarget? = nil) async -> InsertionResult {
        guard !text.isEmpty else { return InsertionResult(method: .clipboardOnly, notice: nil) }

        // Dictated while airdraft itself was in front: there is nowhere sensible to type.
        if let bundle = target?.bundleID, bundle == Bundle.main.bundleIdentifier {
            copyOnly(text)
            Self.log.notice("insert: target is airdraft, copied only")
            return InsertionResult(method: .clipboardOnly, notice: "Copied to clipboard")
        }

        // Bring the original app back if focus moved while we were transcribing.
        guard let target, await restoreFocus(to: target), !Task.isCancelled else {
            copyOnly(text)
            return InsertionResult(method: .clipboardOnly, notice: "Destination changed. Text copied; paste it where you want.")
        }

        guard AXIsProcessTrusted() else {
            copyOnly(text)
            Self.log.error("insert: Accessibility not granted, copied only")
            return InsertionResult(method: .clipboardOnly, notice: "Accessibility is off, text copied")
        }

        if method == .auto {
            switch insertViaAccessibility(text, target: target) {
            case .inserted:
                return InsertionResult(method: .accessibility, notice: nil)
            case .uncertain:
                copyOnly(text)
                return InsertionResult(method: .clipboardOnly, notice: "Check the destination before pasting. Text copied; insertion could not be verified.")
            case .notAttempted: break
            }
        }
        // Focus can change during an AX request too. Revalidate before posting a paste.
        guard matches(target), !Task.isCancelled else {
            copyOnly(text)
            return InsertionResult(method: .clipboardOnly, notice: "Destination changed. Text copied.")
        }
        let ok = await insertViaPaste(text)
        return ok
            ? InsertionResult(method: .paste, notice: nil)
            : InsertionResult(method: .clipboardOnly, notice: "Couldn't paste, text copied")
    }

    // MARK: - Focus

    public func captureTarget() -> InsertionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = focusedElement(pid: app.processIdentifier)
        return InsertionTarget(processID: app.processIdentifier, bundleID: app.bundleIdentifier,
                               element: element, selection: element.flatMap(selection))
    }

    private func restoreFocus(to target: InsertionTarget) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: target.processID), !app.isTerminated,
              app.bundleIdentifier == target.bundleID else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processID {
            guard app.activate() else { return false }
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID { break }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return false }
            }
        }
        return matches(target)
    }

    private func matches(_ target: InsertionTarget) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID,
              let original = target.element, let current = focusedElement(pid: target.processID),
              CFEqual(original, current) else { return false }
        if let range = target.selection {
            guard let now = selection(current), now.location == range.location, now.length == range.length else { return false }
        }
        return true
    }

    private func focusedElement(pid: Int32) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let element = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }

    private func selection(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(ref as! AXValue, .cfRange, &range) ? range : nil
    }

    // MARK: - Accessibility

    private enum WriteResult { case notAttempted, inserted, uncertain }

    private func insertViaAccessibility(_ text: String, target: InsertionTarget) -> WriteResult {
        guard matches(target), let focused = target.element else { return .notAttempted }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        guard role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole else { return .notAttempted }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue, let before = value(focused), let range = selection(focused),
              let expected = Self.replacing(before, range: range, with: text) else { return .notAttempted }
        // Once a write is attempted, an error or unchanged length is not permission to replay it.
        guard AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success,
              value(focused) == expected else { return .uncertain }
        return .inserted
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

    private func insertViaPaste(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        // Only on the clipboard long enough to paste: keep it off other devices
        // (Universal Clipboard) and out of clipboard-manager history.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        guard postCommandV() else { return false }
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
