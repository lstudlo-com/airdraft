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
        if env["AIRDRAFT_RENDER_AUDIO_HISTORY"] == "1" {
            container = PreviewData.container
            container.settings.audioRetention = .week
            container.settings.livePreviewEnabled = env["AIRDRAFT_RENDER_PREVIEW"] == "1"
            if env["AIRDRAFT_RENDER_SCRIPT"] == "1" {
                container.settings.outputDestination = .script
                container.settings.outputScriptPath = "/usr/bin/true"
            }
            _ = try? container.history?.save(DictationRecord(mode: "Clean", family: "general",
                rawTranscript: "um please send the report tomorrow", refinedText: "Please send the report tomorrow.",
                finalText: "Please send the report tomorrow.", asrEngine: "preview", audioSeconds: 2,
                asrMs: 100, llmMs: 100, inserted: true), samples: [Float](repeating: 0, count: 32_000))
        } else if env["AIRDRAFT_RENDER_SAMPLE_DATA"] == "1" {
            container = PreviewData.container
        } else if env["AIRDRAFT_RENDER_LLM"] != nil || env["AIRDRAFT_RENDER_ASR"] != nil {
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
                    } else if pageName == "automation" {
                        ScrollView { AutomationSettings().padding(Theme.pagePadding) }
                            .background(Color(nsColor: .windowBackgroundColor))
                    } else if pageName == "speech-preview" {
                        ScrollView { SpeechPreviewSettings().padding(Theme.pagePadding) }
                            .background(Color(nsColor: .windowBackgroundColor))
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
                if env["AIRDRAFT_RENDER_VERIFY_NAVIGATION"] == "1", page == .history {
                    // Visibility callbacks require an onscreen window.
                    window.makeKeyAndOrderFront(nil)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    verifyHistoryScrolling(in: host)
                    verifyPointerFocus()
                    window.orderOut(nil)
                }
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                if let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    let name = ["permissions", "refinement", "speech-preview", "automation"].contains(pageName) ? pageName : page.rawValue
                    try? png.write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
                }
            }
        }
    }

    /// Exercise the real SwiftUI scroll views without synthetic global input or user-data writes.
    private static func verifyHistoryScrolling(in host: NSView) {
        setbuf(stdout, nil)
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let views = scrollViews(in: host).sorted {
            $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX
        }
        precondition(views.count == 2, "History verification needs populated history and both scroll columns")
        let timeline = views[0], cards = views[1]
        func wheel(_ view: NSScrollView, delta: Int32) {
            // Deliver directly to the view. No global event posting or Accessibility grant.
            let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: delta, wheel2: 0, wheel3: 0)!
            cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            view.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        func scroll(_ view: NSScrollView, toBottom: Bool) {
            let distance = Int32(min(1_000_000, view.documentView?.bounds.height ?? 0))
            wheel(view, delta: toBottom ? -distance : distance)
        }
        // Lazy rows refine their estimated heights after the first jump.
        scroll(cards, toBottom: true)
        scroll(cards, toBottom: true)
        precondition(cards.contentView.bounds.minY > 100, "History did not scroll down")
        precondition(timeline.contentView.bounds.minY > 0, "Timeline did not follow the lower cards")
        scroll(cards, toBottom: false)
        precondition(cards.contentView.bounds.minY <= 1 && timeline.contentView.bounds.minY <= 1,
                     "Returning cards to the top must restore the timeline day heading")

        // The first card remains visible across this small movement. Its ID does not change.
        wheel(cards, delta: -10)
        scroll(timeline, toBottom: true)
        precondition(timeline.contentView.bounds.minY > 0, "Timeline must overflow for the edge regression")
        scroll(cards, toBottom: false)
        precondition(timeline.contentView.bounds.minY <= 1,
                     "Top-edge synchronization must work when the first record is already active")
        print("PASS: History bottom-to-top and unchanged-first-record synchronization")
    }

    private static func verifyPointerFocus() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let editor = NSTextView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
        window.contentView?.addSubview(editor)
        editor.string = "Keep this selection"
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        precondition(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: 5, length: 4))
        TranslucentWindowView.BackingView.dismissFocus(in: window, at: editor.convert(NSPoint(x: 30, y: 30), to: nil))
        precondition(window.firstResponder === editor && editor.selectedRange() == NSRange(location: 5, length: 4),
                     "Clicking within the editor must preserve focus and selection")
        TranslucentWindowView.BackingView.dismissFocus(in: window, at: NSPoint(x: 350, y: 250))
        precondition(window.firstResponder !== editor, "Clicking elsewhere must clear editor focus")
        print("PASS: Pointer focus dismissal preserves active-editor selection")
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
        let preview = RecordingHUDView(snapshot: HUDSnapshot(state: .recording, levels: samples, elapsed: 7.4),
            style: .classic, showPreview: true,
            sampleText: "Please send the report tomorrow morning, after the team has reviewed the final numbers.")
            .padding(12).background(Color(white: 0.93))
        let previewRenderer = ImageRenderer(content: preview)
        previewRenderer.scale = 2
        if let rendered = previewRenderer.nsImage { images.append(rendered) }
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
