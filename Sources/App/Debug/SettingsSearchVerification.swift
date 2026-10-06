#if DEBUG
import AirdraftCore
import AppKit
import SwiftUI

/// Runs production Configuration controls in a live window with disposable settings.
/// No hotkeys, microphone capture, credential reads, updater or cleanup actions start.
@MainActor
enum SettingsSearchVerification {
    static func run(to directory: URL) {
        setbuf(stdout, nil)
        precondition(LocalE2E.isActive, "Use --e2e-local <disposable directory>")
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "airdraft.settings-search.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = AppContainer(settings: AppSettings(defaults: defaults), dataDirectory: LocalE2E.directory)
        container.microphones.useRenderDevices([
            Microphone(id: 100, uid: "search-fixture", name: "Fixture Microphone")
        ], systemDefaultID: 100)
        container.navigation.page = .configuration
        let originalSettings = defaults.persistentDomain(forName: suite) ?? [:]

        for (name, appearance, height, reduced) in [
            ("light-minimum", NSAppearance.Name.aqua, CGFloat(600), false),
            ("dark-tall-no-motion", NSAppearance.Name.darkAqua, CGFloat(900), true)
        ] {
            let search = SettingsSearchState()
            // The page gets precisely the same width as the expanded main window.
            let root = ConfigurationPage(search: search)
                .environment(container)
                .transaction { $0.disablesAnimations = reduced }
                .contentIsland()
                .background(Theme.chromeBackground)
            let host = NSHostingView(rootView: root)
            let frame = NSRect(x: 200, y: 100, width: Theme.windowWidth - Theme.sidebarWidth, height: height)
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Configuration Search Verification"
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
            let scroll = scrollViews(host).first!
            precondition(search.matches.isEmpty && search.selectedID == nil)
            capture(window, to: directory.appendingPathComponent("\(name)-empty.png"))
            let find = key("f", code: 3, modifiers: .command, window: window)
            precondition(window.performKeyEquivalent(with: find), "Command-F must focus settings search")
            settle()
            guard let editor = window.firstResponder as? NSTextView else {
                preconditionFailure("Search must keep native text editing focus")
            }
            editor.insertText("trigger delay", replacementRange: editor.selectedRange())
            settle()
            precondition(search.query == "trigger delay" && search.matches.first?.title == "Trigger Delay")
            window.sendEvent(key(String(UnicodeScalar(NSDownArrowFunctionKey)!), code: 125, window: window))
            settle()
            precondition(search.matches[search.selectedIndex!].title == "Accessibility", "Down must navigate results")
            window.sendEvent(key("\r", code: 36, window: window))
            settle()
            precondition(search.matches[search.selectedIndex!].title == "Trigger Delay", "Return must wrap results")
            window.sendEvent(key("\u{1b}", code: 53, window: window))
            settle()
            precondition(search.query.isEmpty && search.matches.isEmpty, "Escape must clear search")

            func query(_ text: String, title: String, file: String) {
                search.query = text
                settle()
                precondition(search.matches.first?.title == title, "\(text) must find \(title): \(search.matches)")
                capture(window, to: directory.appendingPathComponent("\(name)-\(file).png"))
                verifyVisible(search, in: host, scroll: scroll)
            }

            query("when you quit", title: "Download updates automatically", file: "description")
            let bottom = scroll.contentView.bounds.origin.y
            precondition(bottom > 500, "A lower setting must actually scroll into view")
            query("appearance", title: "Theme", file: "section")
            precondition(search.matches.count >= 2, "Section search must include its settings")
            precondition(scroll.contentView.bounds.origin.y < bottom, "An earlier result must scroll upward")
            let first = search.selectedID
            search.move(by: -1)
            settle()
            precondition(search.selectedID == search.matches.last?.id)
            search.move(by: 1)
            settle()
            precondition(search.selectedID == first, "Navigation must wrap in both directions")
            query("trigger delay", title: "Trigger Delay", file: "exact-title")
            precondition(search.matches.count == 2, "Title and description matches must both be navigable")
            search.move(by: 1)
            settle()
            verifyVisible(search, in: host, scroll: scroll)
            precondition(search.matches[search.selectedIndex!].title == "Accessibility")

            query("stdin", title: "Executable script", file: "conditional-script")
            precondition(container.settings.outputDestination != .script)
            query("preview language", title: "Preview language", file: "conditional-preview")
            precondition(!container.settings.livePreviewEnabled)
            query("timer position", title: "Timer position", file: "conditional-timer")
            precondition(!container.settings.hudTimer.isEnabled)
            query("light app icon", title: "Light app icon", file: "app-icon")
            query("physical inputs", title: "Input channel", file: "conditional-channel")

            search.query = "not-a-setting-🎙️"
            settle()
            precondition(search.matches.isEmpty && search.matchedIDs.isEmpty && search.selectedID == nil)
            capture(window, to: directory.appendingPathComponent("\(name)-no-results.png"))

            // Rapid typing must apply only the final value after the debounce.
            let passes = search.queryPasses
            search.query = "history"
            pump(0.03)
            search.query = "permissions"
            pump(0.03)
            search.query = "maximum recording"
            settle()
            precondition(search.queryPasses == passes + 1, "Rapid typing must cancel stale searches")
            precondition(search.matches.first?.title == "Maximum recording")

            let builds = search.indexBuilds, searches = search.queryPasses
            for step in 0..<30 {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(step * 20)))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                pump(0.01)
            }
            precondition(search.indexBuilds == builds && search.queryPasses == searches,
                         "Scrolling must not rebuild the index or rerun search")
            search.clear()
            settle()
            precondition(search.matches.isEmpty && search.selectedID == nil)
            window.orderOut(nil)
            print("SETTINGS_SEARCH_PASS \(name) title-section-description conditional-settings navigation debounce scroll-no-index-work")
        }
        let finalSettings = defaults.persistentDomain(forName: suite) ?? [:]
        let changedKeys = Set(originalSettings.keys).union(finalSettings.keys).filter {
            !NSDictionary(dictionary: [$0: originalSettings[$0] ?? NSNull()])
                .isEqual(to: [$0: finalSettings[$0] ?? NSNull()])
        }
        precondition(changedKeys.isEmpty,
                     "Searching must not mutate settings: \(changedKeys.sorted())")
        print("SETTINGS_SEARCH_PASS settings-unchanged")
    }

    private static func verifyVisible(_ search: SettingsSearchState, in host: NSView, scroll: NSScrollView) {
        guard let id = search.selectedID else { preconditionFailure("No selected result") }
        let identifier = "settings.row.\(id.section).\(id.title)"
        let elements = descendants(host.window!)
        guard let row = elements.first(where: { value($0, "accessibilityIdentifier") as? String == identifier }) else {
            print("AX_ROWS", elements.map { "\(type(of: $0)): \(value($0, "accessibilityIdentifier") ?? "nil") \(value($0, "accessibilityLabel") ?? "")" })
            preconditionFailure("Result must be accessible: \(identifier)")
        }
        let viewport = scroll.accessibilityFrame()
        let frame = (value(row, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
        precondition(frame.height > 0 && viewport.intersection(frame).height >= min(frame.height, viewport.height) - 1,
                     "Selected row must be visible below the header: \(frame) within \(viewport)")
    }

    private static func value(_ element: NSObject, _ key: String) -> Any? {
        element.responds(to: NSSelectorFromString(key)) ? element.value(forKey: key) : nil
    }

    private static func descendants(_ element: Any) -> [NSObject] {
        guard let accessible = element as? NSObject else { return [] }
        return [accessible] + ((value(accessible, "accessibilityChildren") as? [Any]) ?? []).flatMap(descendants)
    }

    private static func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }

    private static func settle() { pump(0.55) }
    private static func pump(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }

    private static func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private static func capture(_ window: NSWindow, to path: URL) {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage"),
              let image = unsafeBitCast(symbol, to: Capture.self)(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            preconditionFailure("Own-window compositor capture failed")
        }
        try! data.write(to: path)
    }
}
#endif
