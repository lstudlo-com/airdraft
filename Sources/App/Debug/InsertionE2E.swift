#if DEBUG
import AppKit
import ApplicationServices
import CryptoKit
import AirdraftCore

/// Exercises the real OS delivery boundary, only inside an explicitly prepared
/// disposable field. Never use the user's normal draft as an insertion fixture.
@MainActor enum InsertionE2E {
    /// How the fixture identifies its prepared field.
    /// `exact`: the focused field contains only the marker (release gate).
    /// `suffix`: the field's text, ignoring trailing whitespace, ends with the
    /// marker (a terminal showing a prompt-less receiver); the caret follows it.
    /// `none`: an editor in `TextInserter.selfDrawingEditorBundlePrefixes`,
    /// which publishes no field; the documented outcome is a sent-unverified paste.
    enum FieldMode: String { case exact, suffix, none }

    /// Reports Accessibility trust without prompting (`AXIsProcessTrusted`),
    /// with the binary hashes and the compiled self-drawing editor list, so a
    /// harness can decide each case before preparing any field.
    static func probe() throws -> [String: Any] {
        ["action": "accessibility", "status": "passed", "trusted": AXIsProcessTrusted(),
         "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "bundlePath": Bundle.main.bundlePath,
         "selfDrawingEditorBundlePrefixes": TextInserter.selfDrawingEditorBundlePrefixes,
         "binarySHA256": try binaryHashes()]
    }

    private static func placeCaretAfterMarker(_ marker: String, owner expected: pid_t) async throws {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var ref: CFTypeRef?
        var owner: pid_t = 0
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID(),
              AXUIElementGetPid(ref as! AXUIElement, &owner) == .success, owner == expected,
              fieldText(ref as! AXUIElement, mode: .exact) == marker else {
            throw Failure("The field must contain only the exact disposable fixture marker.")
        }
        var range = CFRange(location: marker.utf16.count, length: 0)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(ref as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw Failure("Place the fixture caret immediately after its marker.")
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    static func run(bundleID: String?, token: String?, method: String?, field: String? = nil,
                    placeCaret: Bool = false) async throws -> [String: Any] {
        guard let bundleID, !bundleID.isEmpty, let token, let id = UUID(uuidString: token),
              let method, let insertionMethod = InsertionMethod(rawValue: method) else {
            throw Failure("Provide --e2e-target-bundle, --e2e-insertion-token UUID and --e2e-insertion-method auto|paste.")
        }
        let selfDrawing = TextInserter.drawsOwnText(bundleID: bundleID)
        guard let mode = FieldMode(rawValue: field ?? (selfDrawing ? "none" : "exact")),
              selfDrawing == (mode == .none) else {
            throw Failure("Use --e2e-insertion-field exact|suffix for editors with a field; self-drawing editors use none.")
        }
        guard AXIsProcessTrusted() else { throw Failure("The running Debug app does not have Accessibility access.") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID else {
            throw Failure("The requested fixture app is not frontmost.")
        }
        let hashes = try binaryHashes()
        let marker = "Airdraft insertion fixture \(id.uuidString)"
        let text = " Delivery \(id.uuidString) succeeded."
        // Stands in for the user's click after a document opens with its caret
        // at the start: a selection change on the disposable field only, before
        // the production capture, never a text write.
        if placeCaret, mode == .exact { try await placeCaretAfterMarker(marker, owner: app.processIdentifier) }
        let inserter = TextInserter()
        guard let target = await inserter.captureTarget() else { throw Failure("Could not capture the fixture target.") }
        // Text before the marker that must stay unchanged (suffix mode only).
        var prefix = ""
        var field: AXUIElement?
        if mode != .none {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.3)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
                  let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
                throw Failure("The fixture has no accessible focused field.")
            }
            let focused = ref as! AXUIElement
            AXUIElementSetMessagingTimeout(focused, 0.3)
            var owner: pid_t = 0
            guard AXUIElementGetPid(focused, &owner) == .success, owner == app.processIdentifier,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == owner,
                  let current = fieldText(focused, mode: mode), current.hasSuffix(marker),
                  mode == .suffix || current == marker else {
                throw Failure("The field must contain only the exact disposable fixture marker.")
            }
            prefix = String(current.dropLast(marker.count))
            var selectionRef: CFTypeRef?
            var range = CFRange()
            guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &selectionRef) == .success,
                  let selectionRef, CFGetTypeID(selectionRef) == AXValueGetTypeID(),
                  AXValueGetType(selectionRef as! AXValue) == .cfRange,
                  AXValueGetValue(selectionRef as! AXValue, .cfRange, &range),
                  range.location == current.utf16.count, range.length == 0 else {
                throw Failure("Place the fixture caret immediately after its marker.")
            }
            field = focused
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
        var actualTextMatches = false
        if let field {
            let expected = prefix + marker + text
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !Task.isCancelled, fieldText(field, mode: mode) != expected, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(25))
            }
            actualTextMatches = fieldText(field, mode: mode) == expected
        }
        // Return the displaced clipboard before the fixture process exits; an
        // unverified paste keeps its receiver window first.
        await inserter.finishClipboardRestoration()
        // A self-drawing editor that publishes a caret may confirm its paste.
        let passed = mode == .none
            ? (result.delivery == .sentUnverified || result.delivery == .delivered) && result.method == .paste
            : result.didInsert && actualTextMatches
        return ["action": "insert", "status": passed && result.notice == nil && delivered == 1 ? "passed" : "failed",
                "targetBundle": bundleID, "requestedMethod": method,
                "reportedMethod": result.method.rawValue, "delivery": result.delivery.rawValue,
                "notice": result.notice ?? "", "fieldMode": mode.rawValue, "selfDrawingEditor": selfDrawing,
                "actualTextReadable": field != nil,
                "actualTextMatches": actualTextMatches, "deliveryCallbacks": delivered,
                "fixtureToken": id.uuidString, "binarySHA256": hashes]
    }

    private static func binaryHashes() throws -> [String: String] {
        let bundle = Bundle.main.bundleURL
        let executable = Bundle.main.executableURL!
        let binaries = [executable,
            bundle.appendingPathComponent("Contents/Frameworks/AirdraftCore.framework/AirdraftCore"),
            executable.deletingLastPathComponent().appendingPathComponent(executable.lastPathComponent + ".debug.dylib")]
        return try Dictionary(uniqueKeysWithValues: binaries.map { url in
            (url.lastPathComponent, SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined())
        })
    }

    /// The field's text; suffix mode ignores the trailing blank rows a terminal reports.
    private static func fieldText(_ field: AXUIElement, mode: FieldMode) -> String? {
        guard let text = value(field) else { return nil }
        guard mode == .suffix else { return text }
        var trimmed = Substring(text)
        while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast() }
        return String(trimmed)
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
