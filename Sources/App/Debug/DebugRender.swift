#if DEBUG
// Offscreen renders and self-tests use the app's permissions, so they never ship in Release.
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
        let env = ProcessInfo.processInfo.environment
        if env["AIRDRAFT_RENDER_LLM"] != nil || env["AIRDRAFT_RENDER_ASR"] != nil {
            let settings = AppSettings(defaults: defaults)
            if let name = env["AIRDRAFT_RENDER_LLM"], let kind = LLMProviderKind(rawValue: name) { settings.llm.select(kind) }
            if let name = env["AIRDRAFT_RENDER_ASR"], let kind = ASRProviderKind(rawValue: name) { settings.asr.select(kind) }
            if let model = env["AIRDRAFT_RENDER_ASR_MODEL"] { settings.asr.selectModel(model) }
            if let model = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_MODEL"] { settings.llm.model = model }
            if let provider = env["AIRDRAFT_RENDER_OPENROUTER_PROVIDER"] {
                settings.llm.openRouterRouting = OpenRouterRouting(providerID: provider,
                    allowFallbacks: env["AIRDRAFT_RENDER_OPENROUTER_FALLBACK"] == "1")
            }
            if let effort = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_EFFORT"].flatMap(ThinkingEffort.init(rawValue:)) {
                settings.llm.thinkingEffort = effort
            }
            container = AppContainer(settings: settings)
        } else {
            container = AppContainer.shared
        }
        container.navigation.sidebarCollapsed = env["AIRDRAFT_RENDER_SIDEBAR_COLLAPSED"] == "1"
        let previewEndpoints = env["AIRDRAFT_RENDER_OPENROUTER_DATA"].flatMap {
            try? OpenRouterCatalog.decode(Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        if env["AIRDRAFT_RENDER_BLOCKED"] == "1" {
            container.pipeline.startRecording()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        let pages: [Page] = pageName == "all" ? Page.allCases : [Page(rawValue: pageName) ?? .home]
        for page in pages {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
                container.navigation.page = page
                let root = Group {
                    if pageName == "permissions" {
                        AccessibilityPermissionHelp()
                    } else if pageName == "refinement" {
                        ScrollView {
                            PageSection("Refinement") { RefinementSettings() }
                                .padding(Theme.pagePadding)
                        }
                        .background(Color(nsColor: .windowBackgroundColor))
                    } else {
                        MainWindowView(previewOverlay: env["AIRDRAFT_RENDER_OVERLAY"] == "microphone" ? .microphone :
                                       ["account", "settings"].contains(env["AIRDRAFT_RENDER_OVERLAY"] ?? "") ? .account : nil,
                                       microphoneRenderLevel: env["AIRDRAFT_RENDER_OVERLAY"] == "microphone"
                                           ? Float(env["AIRDRAFT_RENDER_MIC_LEVEL"] ?? "") ?? 0.42 : nil)
                    }
                }.environment(container).environment(\.openRouterPreviewEndpoints, previewEndpoints)
                let host = NSHostingView(rootView: root)
                let width = Double(env["AIRDRAFT_RENDER_WIDTH"] ?? "") ?? Double(Theme.windowWidth)
                let frame = NSRect(x: 0, y: 0, width: width, height: Double(env["AIRDRAFT_RENDER_HEIGHT"] ?? "") ?? height)
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
                    let name = ["permissions", "refinement"].contains(pageName) ? pageName : page.rawValue
                    try? png.write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
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
        for style in [HUDStyle.classic, .mini] {
            for (_, snap) in states {
                let content = IndicatorView(snapshot: snap, style: style)
                    .padding(12)
                    .background(Color(white: 0.93))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let img = renderer.nsImage { images.append(img) }
            }
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
#endif
