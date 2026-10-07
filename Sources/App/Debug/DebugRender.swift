#if DEBUG
// Offscreen renders and self-tests use the app's permissions, so they never ship in Release.
import AppKit
import AirdraftCore
import CoreAudio
import SwiftUI

/// Offscreen rendering of UI pieces for verification.
@MainActor
enum DebugRender {
    /// Renders the main window for one page in dark and light appearance.
    static func renderWindow(pageName: String, toDirectory dir: URL, height: CGFloat = 660) {
        if pageName == "settings-search" {
            SettingsSearchVerification.run(to: dir)
            return
        }
        if pageName == "hud-styles" {
            SpatialHUDVerification.run(to: dir)
            return
        }
        if pageName == "menu" {
            MenuVerification.run(to: dir)
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Verify CLI settings without changing the user's persisted configuration.
        let suite = "airdraft.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let container: AppContainer
        let env = ProcessInfo.processInfo.environment
        let fixtureDirectory = env["AIRDRAFT_RENDER_HISTORY_COUNT"] == nil ? nil :
            FileManager.default.temporaryDirectory.appendingPathComponent("airdraft-history-perf-\(UUID().uuidString)")
        defer { if let fixtureDirectory { try? FileManager.default.removeItem(at: fixtureDirectory) } }
        if pageName.hasPrefix("license-") {
            container = LicensePreview.container(String(pageName.dropFirst("license-".count)))
        } else if pageName.hasPrefix("onboarding-") {
            container = PreviewData.container
            if pageName == "onboarding-cloud" { container.settings.asr.select(.groq) }
            container.settings.onboarding.move(to: pageName == "onboarding-permissions" ? .permissions :
                pageName.hasPrefix("onboarding-practice") ? .practice : .speech)
            if pageName == "onboarding-practice-ready" {
                container.engineStatus.setPreviewState(container.settings.asr.engineID, .ready)
            } else if pageName == "onboarding-practice-failed" {
                container.engineStatus.setPreviewState(container.settings.asr.engineID, .failed("The speech model could not be loaded. Check the downloaded files in Models."))
            }
            container.settings.onboarding.present()
        } else if let fixtureDirectory {
            do { try HistoryVerification.run() }
            catch { preconditionFailure("History verification failed: \(error)") }
            container = AppContainer(settings: AppSettings(defaults: defaults), dataDirectory: fixtureDirectory)
            let count = min(10_000, max(1, Int(env["AIRDRAFT_RENDER_HISTORY_COUNT"] ?? "") ?? 200))
            let now = Date()
            for index in 0..<count {
                let phrase = index % 2 == 0 ? "A long dictation should scroll without blocking the interface. " :
                    "這是一段用來驗證歷史記錄捲動效能的文字，包含中文、English 與 emoji 🎙️。"
                let text = index == 0
                    ? String(repeating: "長篇逐字稿包含中文、English 與 emoji 🎙️。收合後只顯示前六行，文字不能蓋住 Show More、版本切換或下方的操作按鈕。\n\n", count: 40)
                    : String(repeating: phrase, count: [1, 4, 20, 160][index % 4])
                _ = try? container.history?.save(DictationRecord(createdAt: now.addingTimeInterval(-Double(index) * 3600),
                    appName: "Notes", mode: "Clean", family: "general", rawTranscript: "um " + text,
                    refinedText: text, finalText: text, asrEngine: "fixture", audioSeconds: 60,
                    asrMs: 100, llmMs: 100, inserted: true))
            }
        } else if env["AIRDRAFT_RENDER_AUDIO_HISTORY"] == "1" {
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
            if env["AIRDRAFT_RENDER_DETACHED_AUDIO"] == "1" {
                try? container.history?.deleteHistoryKeepingAudio()
            }
        } else if env["AIRDRAFT_RENDER_SAMPLE_DATA"] == "1" {
            container = PreviewData.container
        } else if env["AIRDRAFT_RENDER_LLM"] != nil || env["AIRDRAFT_RENDER_ASR"] != nil {
            let settings = AppSettings(defaults: defaults)
            if let name = env["AIRDRAFT_RENDER_LLM"], let kind = LLMProviderKind(rawValue: name) { settings.llm.select(kind) }
            if let name = env["AIRDRAFT_RENDER_ASR"], let kind = ASRProviderKind(rawValue: name) { settings.asr.select(kind) }
            if let model = env["AIRDRAFT_RENDER_ASR_MODEL"] { settings.asr.selectModel(model) }
            if let language = env["AIRDRAFT_RENDER_LANGUAGE"] { settings.asr.language = language }
            if let model = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_MODEL"] { settings.llm.model = model }
            if let provider = env["AIRDRAFT_RENDER_OPENROUTER_PROVIDER"] {
                settings.llm.openRouterRouting = OpenRouterRouting(providerID: provider,
                    allowFallbacks: env["AIRDRAFT_RENDER_OPENROUTER_FALLBACK"] == "1")
            }
            if let effort = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_EFFORT"].flatMap(ThinkingEffort.init(rawValue:)) {
                settings.llm.thinkingEffort = effort
            }
            container = AppContainer(settings: settings, dataDirectory: LocalE2E.isActive ? LocalE2E.directory : nil)
        } else {
            container = AppContainer.shared
        }
        container.navigation.sidebarCollapsed = env["AIRDRAFT_RENDER_SIDEBAR_COLLAPSED"] == "1"
        if let position = env["AIRDRAFT_RENDER_HUD_TIMER"].flatMap(HUDTimerOptions.Position.init(rawValue:)) {
            container.settings.hudTimer = HUDTimerOptions(isEnabled: true, position: position)
        }
        if let stage = env["AIRDRAFT_RENDER_DOWNLOAD"] {
            let progress: ModelDownloader.Progress
            switch stage {
            case "preparing": progress = .init(fraction: nil, currentFile: "Preparing download…")
            case "unknown": progress = .init(fraction: nil, currentFile: "model.safetensors", receivedBytes: 12_345_678)
            case "unpacking": progress = .init(fraction: nil, currentFile: "Unpacking…")
            default: progress = .init(fraction: 0.123, currentFile: "AudioEncoder.mlmodelc/weights/weight.bin",
                                      receivedBytes: 123_000_000, totalBytes: 1_000_000_000)
            }
            for entry in ModelCatalogue.entries where entry.isDownloadable {
                container.downloads.setPreviewProgress(progress, for: entry.config(from: container.settings.asr))
            }
        }
        // `many` overflows the list with long names, `missing` saves a device that is gone.
        if let fixture = env["AIRDRAFT_RENDER_MIC_DEVICES"] {
            let names = fixture == "many"
                ? ["MacBook Pro Microphone", "Studio Display Microphone", "Scarlett 2i2 4th Gen USB",
                   "AirPods Pro de Light", "Logitech BRIO Ultra HD Webcam", "Loopback Audio (Virtual)",
                   "Elgato Wave:3 Microphone"]
                : ["MacBook Pro Microphone"]
            container.microphones.useRenderDevices(
                names.enumerated().map { Microphone(id: AudioDeviceID(100 + $0.offset), uid: "render-\($0.offset)", name: $0.element) },
                systemDefaultID: 100)
            if fixture == "many" {
                container.settings.microphone = MicrophonePreference(uid: "render-2", name: names[2])
            } else if fixture == "missing" {
                container.settings.microphone = MicrophonePreference(uid: "render-gone", name: "Yeti Nano")
            }
        }
        let previewEndpoints = env["AIRDRAFT_RENDER_OPENROUTER_DATA"].flatMap {
            try? OpenRouterCatalog.decode(Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        if env["AIRDRAFT_RENDER_BLOCKED"] == "1" {
            container.pipeline.startRecording()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        if let state = env["AIRDRAFT_RENDER_CLEANUP"] {
            var ready = false
            Task { @MainActor in
                await container.cleanup.execute(.reset, prepare: {}, steps: [
                    .init("files", title: "Files") {},
                    .init("permissions", title: "Permissions") {
                        if state == "failed" { throw PermissionResetError(message: "macOS could not reset this app’s permissions. Unlock System Settings and retry.") }
                    }
                ])
                ready = true
            }
            while !ready { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        if env["AIRDRAFT_RENDER_VERIFY_CLEANUP"] == "1" {
            var result: Bool?
            Task { @MainActor in result = await DataCleanupVerification.run() }
            while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            if result != true { exit(1) }
        }
        if env["AIRDRAFT_RENDER_VERIFY_MEETING"] == "1" {
            var result: Bool?
            Task { @MainActor in result = await MeetingVerification.run() }
            while result == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            if result != true { exit(1) }
        }
        if pageName == "meeting-recording" { container.meeting?.previewRecording() }
        if env["AIRDRAFT_RENDER_MEDIA"] == "1", let history = container.history {
            if pageName == "meetings" { try? MediaPreview.seedMeetings(history) }
            else { try? MediaPreview.seed(history) }
        }
        let pages: [Page] = pageName == "all" ? Page.allCases : [Page(rawValue: pageName) ?? .home]
        for page in pages {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", NSAppearance.Name.aqua)] {
                container.navigation.page = page
                let root = Group {
                    if pageName.hasPrefix("license-") {
                        // A sheet has no titlebar inset, and its window is active.
                        LicenseView().ignoresSafeArea()
                            .environment(\.controlActiveState, .key)
                            .background(Color(nsColor: .windowBackgroundColor))
                    } else if pageName == "meeting-recording", let meeting = container.meeting {
                        MeetingRecordingStatus(meeting: meeting).padding(Theme.pagePadding)
                    } else if pageName.hasPrefix("meeting-") {
                        MeetingSheet().ignoresSafeArea()
                    } else if pageName == "media-import" {
                        MediaImportSheet(request: .file(URL(fileURLWithPath: "/tmp/Interview.m4a"))).ignoresSafeArea()
                    } else if pageName == "media-editor" {
                        MediaDocumentEditor(initial: MediaPreview.document).ignoresSafeArea()
                    } else if pageName == "cleanup" {
                        DataCleanupProgress().ignoresSafeArea()
                            .environment(\.controlActiveState, .key)
                            .background(Color(nsColor: .windowBackgroundColor))
                    } else if pageName == "permissions" {
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
                var frame = NSRect(x: 0, y: 0, width: width, height: Double(env["AIRDRAFT_RENDER_HEIGHT"] ?? "") ?? height)
                if pageName.hasPrefix("license-") || ["cleanup", "media-import", "media-editor", "meeting-setup", "meeting-recording"].contains(pageName) {
                    // The sheet sizes to its content; render exactly that size.
                    frame.size = host.fittingSize
                    print("LICENSE_SIZE \(pageName) \(suffix) \(Int(frame.width)) x \(Int(frame.height))")
                }
                host.frame = frame
                let window = NSWindow(contentRect: frame, styleMask: (pageName.hasPrefix("media-") || pageName.hasPrefix("meeting-")) ? [.borderless] : [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.titlebarAppearsTransparent = true
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.layoutIfNeeded()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(container.settings.llm.kind.isCLI && page == .models ? 3 : 0.3))
                if env["AIRDRAFT_RENDER_SCROLL_BOTTOM"] == "1" {
                    func descendants(_ view: NSView) -> [NSScrollView] {
                        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(descendants)
                    }
                    if let scroll = descendants(host).max(by: { $0.frame.width < $1.frame.width }),
                       let document = scroll.documentView {
                        let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                        scroll.reflectScrolledClipView(scroll.contentView)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                    }
                }
                if env["AIRDRAFT_RENDER_LIVE"] == suffix {
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                    let liveSeconds = min(300, max(1, Double(env["AIRDRAFT_RENDER_LIVE_SECONDS"] ?? "") ?? 45))
                    RunLoop.main.run(until: Date().addingTimeInterval(liveSeconds))
                    window.orderOut(nil)
                }
                if env["AIRDRAFT_RENDER_VERIFY_NAVIGATION"] == "1", page == .history {
                    // Visibility callbacks require an onscreen window.
                    window.makeKeyAndOrderFront(nil)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                    verifyHistoryScrolling(in: host)
                    if env["AIRDRAFT_RENDER_HISTORY_COUNT"] != nil { verifyHistoryPerformance(in: host) }
                    verifyPointerFocus()
                    window.orderOut(nil)
                }
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                if let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    let name = pageName.hasPrefix("license-") || pageName.hasPrefix("onboarding-") || ["permissions", "refinement", "speech-preview", "automation", "cleanup", "media-import", "media-editor", "meeting-setup", "meeting-recording"].contains(pageName) ? pageName : page.rawValue
                    try? png.write(to: dir.appendingPathComponent("\(name)-\(suffix).png"))
                }
            }
        }
    }

    private static func verifyHistoryPerformance(in host: NSView) {
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        let cards = scrollViews(host).max { $0.frame.width < $1.frame.width }!
        HistoryRenderMetrics.reset()
        var times: [Double] = []
        for step in 0..<180 {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: step < 120 ? -60 : 60, wheel2: 0, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            let start = CFAbsoluteTimeGetCurrent()
            cards.scrollWheel(with: NSEvent(cgEvent: event)!)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))
            times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        precondition(HistoryRenderMetrics.currentRecordID.map(HistoryRenderMetrics.timelineVisibleIDs.contains) == true,
                     "The timeline must keep the current record visible")
        let sorted = times.sorted()
        precondition(HistoryRenderMetrics.groupingPasses == 0, "Scrolling must not rebuild the history snapshot")
        precondition(HistoryRenderMetrics.cardBodies < 180, "Timeline tracking invalidated unrelated cards")
        precondition(HistoryRenderMetrics.timelineScrolls <= max(3, HistoryRenderMetrics.recordChanges / 4),
                     "The timeline must not scroll for every current-record change")
        let work = times.reduce(0, +) / Double(times.count) - 1000.0 / 120
        print("HISTORY_PERF mean_work_ms=\(String(format: "%.2f", work)) slow=\(times.filter { $0 > 1000.0 / 60 }.count) samples=\(times.count) p50_ms=\(sorted[sorted.count / 2]) p95_ms=\(sorted[sorted.count * 95 / 100]) max_ms=\(sorted.last!) grouping_passes=\(HistoryRenderMetrics.groupingPasses) grouped_records=\(HistoryRenderMetrics.groupedRecords) card_bodies=\(HistoryRenderMetrics.cardBodies) record_changes=\(HistoryRenderMetrics.recordChanges) timeline_scrolls=\(HistoryRenderMetrics.timelineScrolls)")
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
        let initialTimelineIDs = HistoryRenderMetrics.timelineVisibleIDs
        precondition(!initialTimelineIDs.isEmpty, "History must expose its visible timestamps")
        func verifyReturnedTimeline() {
            let visible = HistoryRenderMetrics.timelineVisibleIDs
            precondition(!visible.isEmpty && visible.isSubset(of: initialTimelineIDs),
                         "Returning to the top must remove offscreen timestamps from accessibility")
        }
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
        precondition(HistoryRenderMetrics.currentRecordID.map(HistoryRenderMetrics.timelineVisibleIDs.contains) == true,
                     "The timeline must reveal the current lower record")
        precondition(HistoryRenderMetrics.timelineVisibleIDs.isDisjoint(with: initialTimelineIDs),
                     "Lower timeline accessibility must exclude the initial timestamps")
        scroll(cards, toBottom: false)
        precondition(cards.contentView.bounds.minY <= 1 && timeline.contentView.bounds.minY <= 1,
                     "Returning cards to the top must restore the timeline day heading")
        verifyReturnedTimeline()

        // The first card remains visible across this small movement. Its ID does not change.
        wheel(cards, delta: -10)
        scroll(timeline, toBottom: true)
        precondition(timeline.contentView.bounds.minY > 0, "Timeline must overflow for the edge regression")
        scroll(cards, toBottom: false)
        precondition(timeline.contentView.bounds.minY <= 1,
                     "Top-edge synchronization must work when the first record is already active")
        verifyReturnedTimeline()
        print("PASS: History bottom-to-top and unchanged-first-record synchronization")
        print("PASS: History accessibility removes evicted timeline timestamps")
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
        WindowChromeView.BackingView.dismissFocus(in: window, at: editor.convert(NSPoint(x: 30, y: 30), to: nil))
        precondition(window.firstResponder === editor && editor.selectedRange() == NSRange(location: 5, length: 4),
                     "Clicking within the editor must preserve focus and selection")
        WindowChromeView.BackingView.dismissFocus(in: window, at: NSPoint(x: 350, y: 250))
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
            ("refining", HUDSnapshot(state: .refining, levels: samples, elapsed: 7.4)),
            ("inserting", HUDSnapshot(state: .inserting, levels: samples, elapsed: 7.4)),
            ("failed", HUDSnapshot(state: .failed("Microphone access denied"), levels: [], elapsed: 0)),
            ("failed-long", HUDSnapshot(state: .failed("Transcription failed: the server returned HTTP 429.\nThe selected speech model has reached its request limit. Please retry after 30 seconds.\nRequest ID: fixture-request-END"), levels: [], elapsed: 0)),
            ("failed-cjk", HUDSnapshot(state: .failed("聽寫失敗：無法連線至伺服器。請檢查網路後重試。\n完整原因：連線逾時，沒有收到辨識結果。"), levels: [], elapsed: 0)),
            ("notice", HUDSnapshot(state: .notice("Text copied: the original destination is no longer focused. Return to the intended text field and paste the recovered transcript."), levels: [], elapsed: 0)),
        ]
        var images: [NSImage] = []
        var miniWidths: [String: CGFloat] = [:]
        for style in [HUDStyle.mini, .cube, .sonic] {
            for (name, snap) in states {
                let measured = NSHostingView(rootView: IndicatorView(snapshot: snap, style: style)).fittingSize
                if snap.state.hudMessage == nil {
                    precondition(abs(measured.height - (style == .mini ? 32 : 34)) < 0.5,
                                 "HUD waveform must retain equal six-point outer insets")
                }
                if style == .mini { miniWidths[name] = measured.width }
                print("HUD \(style.rawValue) \(name): \(measured.width) x \(measured.height)")
                let content = IndicatorView(snapshot: snap, style: style)
                    .padding(12)
                    .background(Color(white: 0.93))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let img = renderer.nsImage { images.append(img) }
            }
        }
        precondition(miniWidths["recording"]! < miniWidths["transcribing"]! &&
                     miniWidths["refining"]! < miniWidths["transcribing"]! &&
                     miniWidths["inserting"]! < miniWidths["transcribing"]!,
                     "HUD width must fit its current status, not reserve the longest label")
        for style in [HUDStyle.mini, .cube, .sonic] {
            func size(_ elapsed: Double, timer: HUDTimerOptions = HUDTimerOptions()) -> CGSize {
                NSHostingView(rootView: IndicatorView(snapshot:
                    HUDSnapshot(state: .recording, levels: samples, elapsed: elapsed),
                    style: style, timer: timer)).fittingSize
            }
            precondition(size(7.4) == size(600), "Disabled timers must not reserve layout space")
            for position in HUDTimerOptions.Position.allCases {
                let timer = HUDTimerOptions(isEnabled: true, position: position)
                precondition(size(7.4, timer: timer).width > size(7.4).width)
                precondition(size(600, timer: timer).width > size(7.4, timer: timer).width,
                             "A longer timer must grow instead of clipping")
                precondition(size(7.4, timer: timer).height == size(7.4).height)
            }
        }
        print("PASS: all presets fit their optional timer with unchanged capsule height")
        let preview = RecordingHUDView(snapshot: HUDSnapshot(state: .recording, levels: samples, elapsed: 7.4),
            style: .mini, showPreview: true,
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

@MainActor
enum HistoryRenderMetrics {
    static var timelineVisibleIDs: Set<String> = []
    static var currentRecordID: String?
    static var recordChanges = 0
    static var timelineScrolls = 0
    static var groupingPasses = 0
    static var groupedRecords = 0
    static var cardBodies = 0
    static func reset() { groupingPasses = 0; groupedRecords = 0; cardBodies = 0; recordChanges = 0; timelineScrolls = 0 }
}
#endif
