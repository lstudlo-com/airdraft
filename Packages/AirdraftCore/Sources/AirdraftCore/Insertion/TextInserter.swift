import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import os

public enum InsertionMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Legacy automatic setting; uses the same validated paste path as `paste`.
    case auto
    /// Always paste (clipboard is restored after confirmed delivery).
    case paste
    public var id: String { rawValue }
}

/// What the destination is known to have received.
public enum TextDeliveryStatus: String, Sendable, Codable, CaseIterable {
    /// The original field shows the text (or a script completed).
    case delivered
    /// One paste reached a validated editor that draws its own text and exposes
    /// none to read back (`TextInserter.drawsOwnText`: Warp, Zed, GPU terminals).
    /// Not a failure: there is simply nothing that could confirm it.
    case sentUnverified
    /// Nothing was sent, or a paste that could have been confirmed was not.
    case notDelivered
}

public struct InsertionResult: Sendable, Equatable {
    public enum Method: String, Sendable {
        case accessibility, paste, clipboardOnly
        /// Onboarding practice's own editor received the text directly.
        case practiceEditor
    }
    public let method: Method
    public let notice: String?
    /// Recovery messages stay readable; an intentional copy is only a confirmation.
    public var noticeRequiresAttention = true
    /// False only for a paste into a validated editor that draws its own text.
    public var isVerified = true
    public var delivery: TextDeliveryStatus {
        method == .clipboardOnly ? .notDelivered : (isVerified ? .delivered : .sentUnverified)
    }
    /// True only when the destination confirmed the text.
    public var didInsert: Bool { delivery == .delivered }
    /// True when the text reached the destination, confirmed or not.
    public var wasSent: Bool { delivery != .notDelivered }
}

/// Local insertion identity, never serialized or sent to a provider.
/// With `element` and `selection`, delivery requires that field and caret.
/// Without them the target is the process and its focused window: editors that
/// draw their own text (Zed, Warp, other GPU terminals), but also any app that
/// exposed no caret in time, such as Finder or a page without a focused field.
@MainActor
public struct InsertionTarget {
    let processID: Int32
    let bundleID: String?
    let element: AXUIElement?
    let selection: CFRange?
    var window: AXUIElement? = nil

    /// No field and caret could be captured, so read-back cannot confirm a paste.
    var isCaretless: Bool { element == nil || selection == nil }
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
        var readText: (AXUIElement, CFRange) -> String? = { _, _ in nil }

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
            }, postPaste: { postCommandV() }, pasteboard: .general, readText: { element, range in
                var range = range
                guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
                var ref: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(element,
                    kAXStringForRangeParameterizedAttribute as CFString, parameter, &ref) == .success else { return nil }
                return ref as? String
            })
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
    /// Counted from the paste; delivery returns before it ends so the next dictation can start.
    public var restoreDelay: TimeInterval = 1.0
    private typealias ClipboardItems = [[NSPasteboard.PasteboardType: Data]]
    /// One confirmed paste's restoration, owned by the inserter rather than the
    /// dictation: it survives cancellation and a newer paste can take it over.
    private struct PendingRestoration {
        let id: UUID
        let pasteboard: NSPasteboard
        let changeCount: Int
        let items: ClipboardItems
        let task: Task<Void, Never>
        /// Nothing confirmed that the receiver read the clipboard yet.
        let waitsForReceiver: Bool
        /// When an unverified paste's receiver window ends (its restore deadline).
        let deadline: ContinuousClock.Instant
    }
    private var pendingRestoration: PendingRestoration?
    /// True while a confirmed or unverified paste's text still waits to be
    /// replaced by the clipboard it displaced.
    public var hasPendingClipboardRestoration: Bool { pendingRestoration != nil }
    /// A caretless editor cannot prove it read the clipboard, so its restore
    /// waits longer than a confirmed paste's: a busy receiver still reads the
    /// transcript, not the clipboard it displaced. Quit waits it out too.
    public var unverifiedRestoreDelay: TimeInterval = 2.0

    /// Bundle-ID prefixes of editors and terminals that draw their own text and
    /// never publish a caret through Accessibility. This is the only place the
    /// list lives. A caretless target from one of these apps gets one paste that
    /// is reported as sent unverified. Every other caretless target (Finder,
    /// Preview, System Settings, a web page without a focused field, an Electron
    /// app that never exposed its editor) keeps the transcript on the clipboard
    /// with a recovery notice. Terminal and iTerm2 publish a caret, so they are
    /// verified by read-back instead and are not listed.
    public static let selfDrawingEditorBundlePrefixes = [
        "dev.warp.Warp",            // Warp (Stable, Preview)
        "dev.zed.Zed",              // Zed (Stable, Preview, Nightly)
        "com.mitchellh.ghostty",    // Ghostty
        "net.kovidgoyal.kitty",     // kitty
        "org.alacritty",            // Alacritty
        "com.github.wez.wezterm",   // WezTerm
    ]

    /// True for an app in `selfDrawingEditorBundlePrefixes`.
    public static func drawsOwnText(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return selfDrawingEditorBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }
    /// A posted event has no acknowledgement. Wait only for read-only evidence
    /// from the original field; an unobservable or slow receiver keeps the text.
    var confirmationTimeout: Duration = .seconds(1)

    public init() { environment = .live }
    init(environment: Environment) { self.environment = environment }
    /// The live OS boundary with a disposable pasteboard (tests).
    init(pasteboard: NSPasteboard) {
        var environment = Environment.live
        environment.pasteboard = pasteboard
        self.environment = environment
    }

    /// `allowsUnconfirmedPaste` false (an explicit retry of a kept recording)
    /// copies instead of pasting into a caretless target: its window may now
    /// show something else, and nothing could confirm where the text went.
    public func insert(_ text: String, method: InsertionMethod = .auto, target: InsertionTarget? = nil,
                       allowsUnconfirmedPaste: Bool = true,
                       onDelivered: (() -> Void)? = nil) async -> InsertionResult {
        guard !Task.isCancelled, !text.isEmpty else { return InsertionResult(method: .clipboardOnly, notice: nil) }

        // A previous unverified paste's receiver may still read the clipboard.
        // Nothing new is written to it until that window has passed.
        await waitForUnverifiedReceiver(of: environment.pasteboard)
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }

        // Dictated while airdraft itself was in front: there is nowhere sensible to type.
        if let bundle = target?.bundleID, bundle == Bundle.main.bundleIdentifier {
            Self.log.notice("insert: target is airdraft, copied only")
            return copyOnly(text, notice: String(localized: "Copied to clipboard", bundle: .module), requiresAttention: false)
        }

        if let target, target.isCaretless, !allowsUnconfirmedPaste {
            Self.log.notice("insert: retry for a caretless destination, copied only")
            return copyOnly(text, notice: String(localized: "Retried text copied. Paste it where you want it.", bundle: .module),
                            requiresAttention: false)
        }

        // Bring the original app back if focus moved while we were transcribing.
        guard environment.isTrusted() else {
            Self.log.error("insert: Accessibility not granted, copied only")
            return copyOnly(text, notice: String(localized: "Accessibility is off, text copied", bundle: .module))
        }
        let restored = if let target { await restoreFocus(to: target) } else { false }
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        guard restored, let target else {
            Self.log.notice("insert: destination unavailable=\(target == nil, privacy: .public)")
            return copyOnly(text, notice: target == nil
                ? String(localized: "Couldn't identify the destination app. Text copied; paste it where you want.", bundle: .module)
                : String(localized: "Destination changed. Text copied; paste it where you want.", bundle: .module))
        }

        // Both persisted settings use one paste operation. AXSelectedText can
        // report writable and still fail or expose a stale value after a write.
        // Probing it by writing made ordinary dictation impossible to recover
        // safely: a subsequent paste could duplicate text. AX is read-only here.
        // Revalidate immediately before changing the clipboard and posting ⌘V.
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        guard await Self.waitForMatch(matches: { self.matches(target) }) else {
            guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
            Self.log.notice("insert: destination changed before paste")
            return copyOnly(text, notice: String(localized: "Destination changed. Text copied.", bundle: .module))
        }
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        Self.log.notice("insert: destination matched by \(target.selection == nil ? "app window" : "field and caret", privacy: .public)")
        let confirmation = pasteConfirmation(text, target: target)
        // Reading the baseline may involve another process. Recheck the field
        // and caret after that read, immediately before posting the only paste.
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        guard matches(target) else {
            return copyOnly(text, notice: String(localized: "Destination changed. Text copied.", bundle: .module))
        }
        return await insertViaPaste(text, pasteboard: environment.pasteboard,
                                    postPaste: environment.postPaste, confirmation: confirmation,
                                    unverifiable: target.isCaretless && Self.drawsOwnText(bundleID: target.bundleID),
                                    unconfirmedIsUnverified: !target.isCaretless && Self.drawsOwnText(bundleID: target.bundleID),
                                    onDelivered: onDelivered)
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
        // Consecutive identical reads: stability spans run-loop turns as well as
        // time, so a slow machine that polls rarely still confirms the field twice.
        var stableReads = 0
        var webAccessibility: Bool?
        var caretSettled = false
        _ = await waitForMatch(timeout: timeout) {
            // Stop this attempt promptly. The caller may follow the newly
            // frontmost app while still inside the shared capture deadline.
            guard isFrontmost() else { return true }
            let (next, selection) = readFocus()
            let sameField = (element == nil && next == nil) || (element != nil && next != nil && CFEqual(element!, next!))
            let sameSelection = (range == nil && selection == nil) || selectionMatches(range, selection)
            if !sameField || !sameSelection { stableSince = nil; stableReads = 0 } else { stableReads += 1 }
            element = next
            range = selection
            let now = ContinuousClock.now
            if stableSince == nil { stableSince = now }
            let stable = stableSince!.duration(to: now)
            if next != nil, selectionMatches(selection, selection) {
                // AX and NSWorkspace can briefly expose the previous editor during
                // activation. Yield the run loop and require a stable field/caret.
                caretSettled = stable >= .milliseconds(50) && stableReads >= 2
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

    /// Only the expected text in the original field confirms delivery. A moved
    /// caret or an arbitrary value change is insufficient. Nothing is written
    /// through AX, logged, persisted or supplied as refinement context.
    private func pasteConfirmation(_ text: String, target: InsertionTarget) -> (() -> Bool)? {
        guard let field = target.element, let range = target.selection else { return nil }
        let (status, ref) = environment.readAttribute(field, kAXValueAttribute as CFString)
        let before = status == .success ? ref as? String : nil
        let expected: String? = before.flatMap { value in
            let source = value as NSString
            guard range.location <= source.length, range.length <= source.length - range.location else { return nil }
            return source.replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
        }
        let length = (text as NSString).length
        guard length <= Int.max - range.location else { return nil }
        let insertedRange = CFRange(location: range.location, length: length)
        let finalCaret = CFRange(location: range.location + length, length: 0)
        return {
            guard self.environment.isTrusted(), self.environment.processID(field) == target.processID else { return false }
            if let before, let expected {
                let (status, ref) = self.environment.readAttribute(field, kAXValueAttribute as CFString)
                if status == .success, let value = ref as? String {
                    if value == expected {
                        return value != before || Self.selectionMatches(finalCaret, self.selection(field))
                    }
                    // The editor normalized the pasted text, so its value must differ from before.
                    if Self.equivalentDeliveredText(value, expected), !Self.equivalentDeliveredText(value, before) {
                        return true
                    }
                }
            }
            // Some editors expose text by range without exposing AXValue.
            return Self.selectionMatches(finalCaret, self.selection(field)) &&
                !Self.selectionMatches(range, finalCaret) &&
                self.environment.readText(field, insertedRange).map { Self.equivalentDeliveredText($0, text) } == true
        }
    }

    /// Editors may store pasted text with their own line endings, typographic
    /// quotes or non-breaking spaces. Only those presentation-equivalent forms
    /// match; any other added, removed or changed character (auto-indent,
    /// trimmed whitespace, a partial paste) still leaves delivery unconfirmed.
    static func equivalentDeliveredText(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || normalizedDeliveredText(lhs) == normalizedDeliveredText(rhs)
    }

    static func normalizedDeliveredText(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            defer { previousWasCR = scalar == "\r" }
            switch scalar {
            case "\r": scalars.append("\n")
            case "\n" where previousWasCR: continue
            case "\u{2018}", "\u{2019}": scalars.append("'")
            case "\u{201C}", "\u{201D}": scalars.append("\"")
            case "\u{00A0}", "\u{202F}": scalars.append(" ")
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// `unverifiable` marks a validated editor that draws its own text and
    /// exposes no caret (`drawsOwnText`): once its one paste is posted, nothing
    /// could confirm it, so it is sent unverified rather than reported as failed.
    /// `unconfirmedIsUnverified` marks such an editor that does publish a caret
    /// (Ghostty 1.3): its field and caret are validated and read back, but text
    /// it draws itself may never appear there, so a missing confirmation is sent
    /// unverified as well. Any other target without confirmation keeps the text
    /// on the clipboard.
    func insertViaPaste(_ text: String, pasteboard: NSPasteboard = .general,
                        postPaste: (() -> Bool)? = nil, confirmation: (() -> Bool)? = nil,
                        unverifiable: Bool = false, unconfirmedIsUnverified: Bool = false,
                        onDelivered: (() -> Void)? = nil) async -> InsertionResult {
        // A previous unverified paste's receiver may read the clipboard late;
        // replacing it now could paste this newer text there instead.
        await waitForUnverifiedReceiver(of: pasteboard)
        guard !Task.isCancelled else { return InsertionResult(method: .clipboardOnly, notice: nil) }
        // A previous confirmed paste may still hold the clipboard. Its text is
        // already in its field, so take over the clipboard it displaced instead
        // of snapshotting that transcript; its delayed restore can never clobber
        // this paste.
        let saved = takeOverRestoration(of: pasteboard) ?? snapshot(pasteboard)

        // Keep the temporary handoff local and out of clipboard-manager history.
        // Without confirmation it remains available for manual recovery.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        guard pasteboard.writeObjects([item]) else {
            // The earlier transcript was already cleared; return what it displaced.
            if !saved.isEmpty { restore(pasteboard, items: saved) }
            Self.log.error("insert: clipboard write failed; paste not posted")
            return InsertionResult(method: .clipboardOnly,
                notice: String(localized: "Couldn't copy or paste. Your text is available in History.", bundle: .module))
        }
        let ourChange = pasteboard.changeCount
        guard pasteboard.string(forType: .string) == text, pasteboard.changeCount == ourChange else {
            return InsertionResult(method: .clipboardOnly,
                notice: String(localized: "Clipboard changed before paste. Your text is available in History.", bundle: .module))
        }

        guard (postPaste ?? Self.postCommandV)() else {
            return InsertionResult(method: .clipboardOnly, notice: String(localized: "Couldn't paste, text copied", bundle: .module))
        }
        // The receiving app handles the posted event asynchronously. Once it is
        // posted, cancellation must not restore the old clipboard before that
        // app reads it. This unstructured task owns confirmation independently
        // of the cancelled dictation; it never posts another key. Restoration
        // is scheduled separately so delivery returns as soon as it is confirmed.
        let delay = restoreDelay
        let unverifiedDelay = unverifiedRestoreDelay
        let timeout = confirmationTimeout
        let started = ContinuousClock.now
        if unverifiable {
            // Nothing readable can confirm this paste, and it is never repeated.
            // The transcript stays in History, so the user's clipboard returns
            // as after a confirmed paste, a little later and only if unchanged.
            Self.log.notice("insert: paste sent to caretless destination; unverifiable")
            onDelivered?()
            scheduleRestoration(of: pasteboard, items: saved, ownedChange: ourChange,
                                at: started.advanced(by: .seconds(max(0, unverifiedRestoreDelay))),
                                waitsForReceiver: true)
            return InsertionResult(method: .paste, notice: nil, isVerified: false)
        }
        return await Task { @MainActor in
            let confirmed: Bool
            if let confirmation { confirmed = await Self.waitForMatch(timeout: timeout, matches: confirmation) }
            else { confirmed = false }
            if !confirmed, unconfirmedIsUnverified {
                Self.log.notice("insert: self-drawing editor did not echo the paste; unverifiable")
                onDelivered?()
                self.scheduleRestoration(of: pasteboard, items: saved, ownedChange: ourChange,
                                         at: started.advanced(by: .seconds(max(0, unverifiedDelay))),
                                         waitsForReceiver: true)
                return InsertionResult(method: .paste, notice: nil, isVerified: false)
            }
            guard confirmed else {
                let kept = pasteboard.changeCount == ourChange
                Self.log.notice("insert: paste unconfirmed; recovery clipboard retained=\(kept, privacy: .public)")
                return InsertionResult(method: .clipboardOnly, notice: kept
                    ? String(localized: "Paste couldn't be confirmed. Text kept on clipboard; check the destination before pasting again.", bundle: .module)
                    : String(localized: "Paste couldn't be confirmed. Clipboard changed; recover your text from History.", bundle: .module))
            }
            Self.log.notice("insert: delivery confirmed by destination text")
            onDelivered?()
            self.scheduleRestoration(of: pasteboard, items: saved, ownedChange: ourChange,
                                     at: started.advanced(by: .seconds(max(0, delay))))
            return InsertionResult(method: .paste, notice: nil)
        }.value
    }

    /// Waits for the delayed restore, or with `immediately` performs it now.
    /// A confirmed paste's text is already in its field, so quitting need not
    /// wait out its delay. An unverified paste may still be read by a busy
    /// receiver, so its restore keeps its (at most `unverifiedRestoreDelay`) wait.
    public func finishClipboardRestoration(immediately: Bool = false) async {
        guard let pending = pendingRestoration else { return }
        if immediately && !pending.waitsForReceiver {
            pending.task.cancel()
            completeRestoration(pending.id)
        } else {
            await pending.task.value
        }
    }

    private func scheduleRestoration(of pasteboard: NSPasteboard, items: ClipboardItems,
                                     ownedChange: Int, at deadline: ContinuousClock.Instant,
                                     waitsForReceiver: Bool = false) {
        pendingRestoration?.task.cancel()
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            try? await ContinuousClock().sleep(until: deadline)
            // A takeover or immediate finish already decided this restore.
            guard !Task.isCancelled else { return }
            self?.completeRestoration(id)
        }
        pendingRestoration = PendingRestoration(id: id, pasteboard: pasteboard, changeCount: ownedChange,
                                                items: items, task: task, waitsForReceiver: waitsForReceiver,
                                                deadline: deadline)
    }

    /// Waits out an earlier unverified paste's receiver window on the inserter's
    /// pasteboard before a delivery writes to it. Returns early on cancellation.
    public func waitForPendingReceiver() async {
        await waitForUnverifiedReceiver(of: environment.pasteboard)
    }

    /// Waits out a pending unverified paste's receiver window (at most
    /// `unverifiedRestoreDelay` from that paste) while its text still owns
    /// `pasteboard`. Nothing confirmed that receiver read it, so a slow
    /// terminal could otherwise paste the next dictation in its place. A
    /// confirmed paste, or a clipboard the user replaced, needs no wait.
    func waitForUnverifiedReceiver(of pasteboard: NSPasteboard) async {
        while let pending = pendingRestoration, pending.pasteboard === pasteboard, pending.waitsForReceiver,
              pasteboard.changeCount == pending.changeCount, ContinuousClock.now < pending.deadline {
            Self.log.notice("insert: waiting for an unverified paste's receiver window")
            do { try await ContinuousClock().sleep(until: pending.deadline) } catch { return }
            // The restore may have run, or another paste may now own the window.
            guard pendingRestoration?.id == pending.id else { continue }
            return
        }
    }

    private func completeRestoration(_ id: UUID) {
        guard let pending = pendingRestoration, pending.id == id else { return }
        pendingRestoration = nil
        // Restore only if nobody replaced the clipboard in the meantime.
        if pending.pasteboard.changeCount == pending.changeCount {
            restore(pending.pasteboard, items: pending.items)
        }
    }

    /// Returns the clipboard a pending restore would bring back while its
    /// transcript still owns the pasteboard; a newer copy keeps its own snapshot.
    private func takeOverRestoration(of pasteboard: NSPasteboard) -> ClipboardItems? {
        guard let pending = pendingRestoration, pending.pasteboard === pasteboard else { return nil }
        pending.task.cancel()
        pendingRestoration = nil
        return pasteboard.changeCount == pending.changeCount ? pending.items : nil
    }

    /// Copies `text` for the user to paste; nothing is posted.
    func copyOnly(_ text: String, notice: String, requiresAttention: Bool = true) -> InsertionResult {
        environment.pasteboard.clearContents()
        guard environment.pasteboard.setString(text, forType: .string),
              environment.pasteboard.string(forType: .string) == text else {
            return InsertionResult(method: .clipboardOnly, notice: String(localized: "Couldn't copy. Your text is available in History.", bundle: .module))
        }
        return InsertionResult(method: .clipboardOnly, notice: notice, noticeRequiresAttention: requiresAttention)
    }

    private func snapshot(_ pb: NSPasteboard) -> ClipboardItems {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private func restore(_ pb: NSPasteboard, items: ClipboardItems) {
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
