import AppKit
import AirdraftCore
import SwiftUI

/// Offscreen rendering of UI pieces for verification.
@MainActor
enum DebugRender {
    /// Renders the main window for one page in dark and light appearance.
    static func renderWindow(pageName: String, toDirectory dir: URL, height: CGFloat = 660) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Verify CLI settings without changing the user's persisted configuration.
        let suite = "airdraft.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let container: AppContainer
        if let name = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_LLM"], let kind = LLMProviderKind(rawValue: name) {
            let settings = AppSettings(defaults: defaults)
            settings.llm.select(kind)
            if let model = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_MODEL"] { settings.llm.model = model }
            if let effort = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_EFFORT"].flatMap(ThinkingEffort.init(rawValue:)) {
                settings.llm.thinkingEffort = effort
            }
            container = AppContainer(settings: settings)
        } else {
            container = AppContainer.shared
        }
        let pages: [Page] = pageName == "all" ? Page.allCases : [Page(rawValue: pageName) ?? .home]
        for page in pages {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
                container.navigation.page = page
                let root = MainWindowView().environment(container)
                let host = NSHostingView(rootView: root)
                let frame = NSRect(x: 0, y: 0, width: 980, height: height)
                host.frame = frame
                let window = NSWindow(contentRect: frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(container.settings.llm.kind.isCLI && page == .models ? 3 : 0.3))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                if let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(page.rawValue)-\(suffix).png"))
                }
            }
        }
    }

    static func renderHUD(to url: URL) {
        var samples: [Float] = []
        for i in 0..<DictationPipeline.levelHistoryLength {
            let wave = abs(sin(Double(i) * 0.9))
            let dip: Double = (i % 5 == 0) ? 0.4 : 1.0
            // Quiet input (system input volume low): peaks around 0.25.
            samples.append(Float(0.04 + 0.21 * wave * dip))
        }
        let states: [(String, HUDSnapshot)] = [
            ("recording", HUDSnapshot(state: .recording, levels: samples, elapsed: 7.4)),
            ("transcribing", HUDSnapshot(state: .transcribing, levels: samples, elapsed: 7.4)),
            ("failed", HUDSnapshot(state: .failed("Microphone access denied"), levels: [], elapsed: 0)),
        ]
        var images: [NSImage] = []
        for (_, snap) in states {
            let content = IndicatorView(snapshot: snap)
                .padding(12)
                .background(Color(white: 0.93))
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let img = renderer.nsImage { images.append(img) }
        }
        let width = images.map(\.size.width).max() ?? 0
        let height = images.reduce(0) { $0 + $1.size.height }
        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()
        var y = height
        for img in images {
            y -= img.size.height
            img.draw(at: NSPoint(x: 0, y: y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
