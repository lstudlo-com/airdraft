#if DEBUG
import AppKit
import ApplicationServices
import AirdraftCore

/// Exercises the real OS delivery boundary, only inside an explicitly prepared
/// disposable field. Never use the user's normal draft as an insertion fixture.
@MainActor enum InsertionE2E {
    static func run(bundleID: String?, token: String?, method: String?) async throws -> [String: Any] {
        guard let bundleID, !bundleID.isEmpty, let token, let id = UUID(uuidString: token),
              let method, let insertionMethod = InsertionMethod(rawValue: method) else {
            throw Failure("Provide --e2e-target-bundle, --e2e-insertion-token UUID and --e2e-insertion-method auto|paste.")
        }
        guard AXIsProcessTrusted() else { throw Failure("The running Debug app does not have Accessibility access.") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID else {
            throw Failure("The requested fixture app is not frontmost.")
        }
        let marker = "Airdraft insertion fixture \(id.uuidString)"
        let text = " Delivery \(id.uuidString) succeeded."
        let inserter = TextInserter()
        guard let target = await inserter.captureTarget() else { throw Failure("Could not capture the fixture target.") }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            throw Failure("The fixture has no accessible focused field.")
        }
        let field = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.3)
        var owner: pid_t = 0
        guard AXUIElementGetPid(field, &owner) == .success, owner == app.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == owner,
              value(field) == marker else {
            throw Failure("The field must contain only the exact disposable fixture marker.")
        }
        var selectionRef: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &selectionRef) == .success,
              let selectionRef, CFGetTypeID(selectionRef) == AXValueGetTypeID(),
              AXValueGetType(selectionRef as! AXValue) == .cfRange,
              AXValueGetValue(selectionRef as! AXValue, .cfRange, &range),
              range.location == marker.utf16.count, range.length == 0 else {
            throw Failure("Place the fixture caret immediately after its marker.")
        }

        // A failed production insertion intentionally leaves recovery text on
        // the clipboard. The fixture restores it without logging its contents.
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        var recoveryChange: Int?
        defer {
            if let recoveryChange, clipboard.changeCount == recoveryChange, clipboard.string(forType: .string) == text {
                clipboard.clearContents()
                let items = saved.map { values in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { clipboard.writeObjects(items) }
            }
        }
        var delivered = 0
        let result = await inserter.insert(text, method: insertionMethod, target: target) { delivered += 1 }
        if result.method == .clipboardOnly, clipboard.string(forType: .string) == text {
            recoveryChange = clipboard.changeCount
        }
        let expected = marker + text
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !Task.isCancelled, value(field) != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        let actualTextMatches = value(field) == expected
        return ["action": "insert", "status": result.didInsert && result.notice == nil &&
                    actualTextMatches && delivered == 1 ? "passed" : "failed",
                "targetBundle": bundleID, "requestedMethod": method,
                "reportedMethod": result.method.rawValue, "notice": result.notice ?? "",
                "actualTextMatches": actualTextMatches, "deliveryCallbacks": delivered,
                "fixtureToken": id.uuidString]
    }

    private static func value(_ field: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
#endif
