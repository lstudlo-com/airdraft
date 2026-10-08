#if DEBUG
import AppKit
import AirdraftCore
import SwiftUI

/// Opens the production sheet and popover. No capture, playback, permissions or providers.
@MainActor
enum MeetingControlsVerification {
    private final class Sources {
        var pending: [CheckedContinuation<[MeetingAudioSource], Error>] = []
        func request() async throws -> [MeetingAudioSource] {
            try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func complete(_ count: Int) {
            precondition(!pending.isEmpty)
            pending.removeFirst().resume(returning: (0..<count).map {
                .init(id: Int32($0 + 1), name: String(format: "Fixture App %02d", $0 + 1))
            })
        }
    }
    private struct FixtureError: LocalizedError {
        var errorDescription: String? {
            "The app list could not be loaded. Check Screen & System Audio Recording access in System Settings, then return here and refresh the list. Your selected app has been kept."
        }
    }
    private static var evidence: [[String: Any]] = []

    static func run(to directory: URL) {
        precondition(LocalE2E.isActive && RenderMode.isActive)
        setbuf(stdout, nil)
        NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "airdraft.meeting-controls.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let container = AppContainer(settings: AppSettings(defaults: defaults),
                                     dataDirectory: LocalE2E.directory.appendingPathComponent("controls"))
        container.navigation.page = .meetings
        let sources = Sources()
        container.meeting!.sourceProvider = { try await sources.request() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let window = NSWindow(contentRect: NSRect(x: 150, y: 100, width: 784, height: 600),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = NSHostingView(rootView: MainWindowView().environment(container))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            pump()
            press(find(label: "Record Meeting", in: window))
            let sheet = window.attachedSheet!
            press(find(id: "meeting.source", in: sheet))
            wait { !sources.pending.isEmpty }
            var popup = popupWindow()
            capture(popup, name: "loading-\(suffix)", directory: directory)
            sources.complete(8); pump()
            inspect(popup, count: 8, name: "eight-\(suffix)", directory: directory)
            refresh(popup, sources: sources, count: 40)
            inspect(popup, count: 40, name: "many-\(suffix)", directory: directory)
            let scroll = scrollView(in: popup.contentView!)!
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.bounds.height - scroll.contentSize.height))
            scroll.reflectScrolledClipView(scroll.contentView); pump()
            let last = find(id: "meeting.source.40", in: popup)
            assertVisible(last, inside: find(id: "meeting.sources.list", in: popup))
            capture(popup, name: "last-\(suffix)", directory: directory)
            press(last)
            precondition(!popup.isVisible)
            precondition(value(find(id: "meeting.source", in: sheet), "accessibilityValue") as? String == "Fixture App 40")
            press(find(id: "meeting.source", in: sheet))
            wait { !sources.pending.isEmpty }
            popup = popupWindow()
            sources.complete(0); pump()
            precondition(findOptional(id: "meeting.sources.list", in: popup) == nil)
            precondition(text(popup).contains("No apps available"))
            precondition(text(sheet).contains("no longer available"))
            capture(popup, name: "empty-\(suffix)", directory: directory)
            refresh(popup, sources: sources, count: 1)
            inspect(popup, count: 1, name: "one-\(suffix)", directory: directory)
            press(find(label: "Refresh", in: popup))
            wait { !sources.pending.isEmpty }
            sources.pending.removeFirst().resume(throwing: FixtureError()); pump()
            precondition(text(popup).contains("Your selected app has been kept."))
            assertVisible(find(label: "Open Recording Permissions", in: popup), inside: popup)
            capture(popup, name: "error-\(suffix)", directory: directory)
            refresh(popup, sources: sources, count: 40)
            inspect(popup, count: 40, name: "recovered-\(suffix)", directory: directory)
            press(find(id: "meeting.source.1", in: popup))
            precondition(!popup.isVisible)
            precondition(value(find(id: "meeting.source", in: sheet), "accessibilityValue") as? String == "Fixture App 01")
            capture(sheet, name: "selected-\(suffix)", directory: directory)
            press(find(label: "Cancel", in: sheet))
            window.orderOut(nil); window.contentView = nil; pump()
        }
        verifyOutOfOrder()
        verifyMetersAndButtons(meeting: container.meeting!, directory: directory)
        try! JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("geometry.json"))
        print("MEETING_CONTROLS_PASS open-popover loading one eight forty refresh empty error selection scroll light-dark")
    }

    private static func verifyOutOfOrder() {
        let selection = MeetingSourceSelection()
        let sources = Sources()
        selection.provider = { try await sources.request() }
        let old = Task { await selection.load() }
        wait { sources.pending.count == 1 }
        old.cancel()
        Task { await selection.load() }
        wait { sources.pending.count == 2 }
        let stale = sources.pending.removeFirst()
        sources.complete(1); pump()
        stale.resume(returning: [.init(id: 99, name: "Stale app")]); pump()
        precondition(selection.sources.map(\.id) == [1] && !selection.loading)
        print("MEETING_CONTROLS_PASS cancelled-out-of-order-load")
    }

    private static func verifyMetersAndButtons(meeting: MeetingController, directory: URL) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let root = VStack(spacing: 24) {
                MeetingRecordingStatus(meeting: meeting)
                HStack {
                    Button("Record Meeting") {}.buttonStyle(SoftButtonStyle(prominent: true))
                    Button("Disabled") {}.buttonStyle(SoftButtonStyle(prominent: true)).disabled(true)
                    Text("Pressed").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white)
                        .softControlSurface(pressed: true, tint: Color(red: 0.05, green: 0.36, blue: 0.73))
                }
            }.padding(24).frame(width: 550).background(Theme.islandBackground)
            meeting.previewRecording()
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host; window.makeKeyAndOrderFront(nil); pump()
            let cases: [(Float, Bool)] = [(0, false), (0.2, true), (0.5, true), (1, true), (0, true), (0, false)]
            for (level, received) in cases {
                meeting.previewRecording(microphone: level, system: level, receiving: received)
                pump()
                let steps = MicrophoneLevelMeter.steps(for: level)
                for title in ["All Apps", "Microphone"] {
                    _ = find(label: "\(title) level, \(steps) of 10", in: window)
                }
                precondition(text(window).contains(received ? "Receiving" : "Waiting for audio"))
                capture(window, name: "meters-buttons-\(steps)-\(received)-\(suffix)", directory: directory)
            }
            window.orderOut(nil); window.contentView = nil
        }
    }

    private static func refresh(_ popup: NSWindow, sources: Sources, count: Int) {
        press(find(label: "Refresh", in: popup)); wait { !sources.pending.isEmpty }
        sources.complete(count); pump()
    }
    private static func inspect(_ popup: NSWindow, count: Int, name: String, directory: URL) {
        let list = find(id: "meeting.sources.list", in: popup)
        let viewport = frame(list)
        precondition(viewport.height >= 31 && viewport.height <= 260)
        let content = popup.convertToScreen(popup.contentView!.convert(popup.contentView!.bounds, to: nil))
        precondition(content.insetBy(dx: -1, dy: -1).contains(viewport), "List extends beyond actual popup content")
        precondition(popup.screen!.visibleFrame.contains(popup.frame), "Popup extends beyond visible screen")
        for row in 1...min(count, 7) { assertVisible(find(id: "meeting.source.\(row)", in: popup), inside: list) }
        precondition(popup.frame.height < 550 && popup.frame.width >= 320)
        evidence.append(["case": name, "popup": NSStringFromRect(popup.frame), "viewport": NSStringFromRect(viewport),
                         "firstRow": NSStringFromRect(frame(find(id: "meeting.source.1", in: popup)))])
        capture(popup, name: name, directory: directory)
    }
    private static func assertVisible(_ object: NSObject, inside parent: NSObject) {
        let bounds = frame(parent).insetBy(dx: -1, dy: -1)
        let row = frame(object)
        precondition(row.height >= 26 && bounds.contains(row), "Clipped row \(row) in \(bounds)")
    }
    private static func popupWindow() -> NSWindow {
        NSApp.windows.first { $0.isVisible && findOptional(label: "Refresh", in: $0) != nil }!
    }
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.compactMap { scrollView(in: $0) }.first
    }
    private static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { pump() }
        precondition(condition(), "Timed out waiting for meeting fixture")
    }
    private static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
    private static func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    private static func descendants(_ object: Any) -> [NSObject] {
        guard let item = object as? NSObject else { return [] }
        return [item] + ((value(item, "accessibilityChildren") as? [Any]) ?? []).flatMap(descendants)
    }
    private static func findOptional(id: String? = nil, label: String? = nil, in object: NSObject) -> NSObject? {
        descendants(object).first {
            if let id { return value($0, "accessibilityIdentifier") as? String == id }
            return value($0, "accessibilityLabel") as? String == label
        }
    }
    private static func find(id: String? = nil, label: String? = nil, in object: NSObject) -> NSObject {
        guard let found = findOptional(id: id, label: label, in: object) else {
            preconditionFailure("Missing \(id ?? label ?? "control"): \(text(object))")
        }
        return found
    }
    private static func frame(_ object: NSObject) -> NSRect {
        (value(object, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
    }
    private static func text(_ object: NSObject) -> String {
        descendants(object).flatMap { [value($0, "accessibilityLabel"), value($0, "accessibilityValue")].compactMap { $0 as? String } }.joined(separator: "\n")
    }
    private static func press(_ object: NSObject) {
        perform(object, selector: "accessibilityPerformPress")
    }
    private static func perform(_ object: NSObject, selector name: String) {
        let selector = NSSelectorFromString(name)
        precondition(object.responds(to: selector))
        let action = unsafeBitCast(object.method(for: selector), to: (@convention(c) (NSObject, Selector) -> Bool).self)
        precondition(action(object, selector)); pump()
    }
    private static func capture(_ window: NSWindow, name: String, directory: URL) {
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
#endif
