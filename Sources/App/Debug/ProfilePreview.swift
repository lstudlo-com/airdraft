import AppKit
import AirdraftCore
import SwiftUI

/// Exercise profile editing with isolated data and no hotkeys, model loading or updater.
@MainActor
enum ProfilePreview {
    private static var window: NSWindow?

    private static func container(directory: URL) -> AppContainer {
        let suite = "airdraft.profile-preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        defaults.removePersistentDomain(forName: suite)
        let container = AppContainer(settings: settings, dataDirectory: directory)
        container.navigation.page = .profiles
        return container
    }

    static func open(directory: URL) {
        let container = container(directory: directory)
        container.startAppearanceUpdates()
        let host = NSHostingView(rootView: MainWindowView().environment(container))
        let frame = NSRect(x: 0, y: 0, width: 980, height: 660)
        let preview = NSWindow(contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        preview.title = "Airdraft · Profile preview"
        preview.titlebarAppearsTransparent = true
        preview.titleVisibility = .hidden
        preview.contentView = host
        preview.minSize = NSSize(width: 900, height: 600)
        window = preview
        NSApp.setActivationPolicy(.regular)
        preview.center()
        preview.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-profile-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: data) }
        let container = container(directory: data)
        let custom = container.profiles.add(RefinementProfile(
            name: "A longer custom profile name for meeting notes",
            symbol: "doc.text", task: "Turn the transcript into meeting notes.",
            instructions: "Keep the decisions, names, dates, and next steps. Use short paragraphs."
        ))
        let cases: [(String, UUID, CGFloat, CGFloat)] = [
            ("clean", RefinementProfile.cleanID, 980, 660),
            ("compact", RefinementProfile.cleanID, 900, 600),
            ("wide", RefinementProfile.cleanID, 1280, 800),
            ("summary", RefinementProfile.summaryID, 980, 660),
            ("verbatim", RefinementProfile.verbatimID, 900, 600),
            ("custom", custom.id, 900, 600)
        ]
        for (name, id, width, height) in cases {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let root = MainWindowView(profileSelection: id).environment(container)
                let host = NSHostingView(rootView: root)
                let frame = NSRect(x: 0, y: 0, width: width, height: height)
                host.frame = frame
                let preview = NSWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                preview.titlebarAppearsTransparent = true
                preview.appearance = NSAppearance(named: appearance)
                preview.contentView = host
                preview.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }
}
