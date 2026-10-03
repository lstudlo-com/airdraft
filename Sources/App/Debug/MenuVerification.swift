#if DEBUG
import AppKit
import AirdraftCore
import SwiftUI

/// Exercises the production SwiftUI menu as NSMenu, with disposable E2E data.
/// Captures only this fixture process's native menu windows.
@MainActor
enum MenuVerification {
    static func run(to directory: URL) {
        precondition(LocalE2E.isActive, "Menu verification requires --e2e-local")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = AppContainer.shared
        let settings = app.settings
        settings.hotkey = Hotkey(keyCode: 61, isModifierOnly: true)
        // Reserve an unused combination, without posting events or opening audio.
        app.hotkeys.apply(Hotkey(keyCode: 80, modifiers: Hotkey.maskCommand | Hotkey.maskAlternate
            | Hotkey.maskControl | Hotkey.maskShift))
        defer { app.hotkeys.suspended = true }
        precondition(app.hotkeys.isActive, "Fixture shortcut could not register")
        settings.asr.select(.whisperKit)
        settings.llm.select(.openAICompatible)
        var profile = app.profiles.activeProfile
        profile.speechModel = ProfileSpeechModel(config: ASRConfig(kind: .cohere))
        app.profiles.update(profile)
        app.engineStatus.setPreviewState(app.speechConfig.engineID, .ready)
        app.models.llmStatus.set(.loaded(instance: "menu-fixture"))

        var report: [String: Any] = [:]
        func makeMenu() -> NSMenu {
            let menu = NSHostingMenu(rootView: MenuView().environment(app))
            menu.update()
            return menu
        }
        func titles(_ menu: NSMenu) -> [String] { menu.items.filter { !$0.isSeparatorItem }.map(\.title) }
        func submenu(_ menu: NSMenu, _ title: String) -> NSMenu {
            guard let child = menu.items.first(where: { $0.title == title })?.submenu else {
                preconditionFailure("Missing submenu: \(title). Actual: \(titles(menu))")
            }
            child.update()
            return child
        }
        func record(_ name: String, _ menu: NSMenu, capture: Bool = true) {
            report[name] = titles(menu)
            if capture {
                for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    NSApp.appearance = NSAppearance(named: appearance)
                    captureMenu(menu, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
                }
            }
        }

        let normal = makeMenu()
        precondition(normal.items.filter(\.isSeparatorItem).count == 2, "Exactly three root groups")
        precondition(Array(titles(normal).prefix(3)) == ["Start Dictation", "History…", "Settings…"])
        precondition(titles(normal).contains("Profile: Clean") && titles(normal).contains("Refinement: Local"))
        precondition(!titles(normal).contains(where: { $0.contains("Loaded") || $0.contains("dictate") }))
        precondition(normal.items.first?.keyEquivalent == "", "The menu must not register a second dictation shortcut")
        precondition(normal.items.first?.badge != nil, "The shortcut hint must stay on the recording row")
        let models = submenu(normal, "Models")
        precondition(titles(models).contains("Speech: Cohere · Loaded"), "Status must use the profile's speech model")
        precondition(titles(models).contains("Unload Models") && titles(models).contains("Manage Models…"))
        record("normal", normal)
        record("models", models)

        app.models.llmStatus.set(.unreachable)
        let offline = makeMenu()
        let refinement = submenu(offline, "Refinement: Unavailable")
        precondition(titles(refinement).contains("Dictation will use raw text"))
        precondition(offline.items.first?.isEnabled == true, "Unavailable refinement must not block dictation")
        record("refinement-offline", offline)
        record("refinement-details", refinement)

        settings.llm.select(.groq)
        precondition(titles(makeMenu()).contains("Refinement: Groq"), "A stale local failure must not label a cloud provider unavailable")
        settings.llm.select(.openAICompatible)

        profile.usesLLM = false
        app.profiles.update(profile)
        let verbatim = makeMenu()
        precondition(titles(verbatim).contains("Refinement: Off"), "The profile's opt-out overrides provider health")
        precondition(titles(submenu(verbatim, "Models")).contains("Refinement: Off"))
        record("profile-refinement-off", verbatim, capture: false)
        profile.usesLLM = true
        profile.name = String(repeating: "Long profile name ", count: 12)
        app.profiles.update(profile)
        settings.microphone = MicrophonePreference(uid: "missing-menu-fixture", name: String(repeating: "Studio microphone ", count: 12))
        let long = makeMenu()
        precondition(titles(long).contains("Microphone: Unavailable"))
        precondition(titles(long).first(where: { $0.hasPrefix("Profile:") })?.hasSuffix("…") == true)
        record("long-and-missing", long)
        profile.name = "Clean"
        app.profiles.update(profile)
        settings.microphone = .systemDefault

        app.models.llmStatus.set(.remote)
        app.engineStatus.setPreviewState(app.speechConfig.engineID, .notLoaded)
        precondition(!titles(submenu(makeMenu(), "Models")).contains("Unload Models"))
        app.hotkeys.suspended = true
        let shortcut = makeMenu()
        precondition(titles(shortcut).contains("Set Up Shortcut…"))
        record("shortcut-unavailable", shortcut, capture: false)

        // Missing local model files produce a real retained recording without
        // microphone, credential, model-download or text-insertion access.
        app.pipeline.insertionEnabled = false
        app.pipeline.processSamples([Float](repeating: 0.01, count: 1_600))
        let busy = makeMenu()
        precondition(busy.items.first?.isEnabled == false)
        precondition(titles(busy).contains("Cancel Dictation"))
        record("processing", busy, capture: false)
        let deadline = Date().addingTimeInterval(5)
        while app.pipeline.isBusy && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(app.pipeline.hasRecoverableRecording && app.pipeline.lastIssue != nil,
                     "Missing local files must retain a recovery recording")
        let recovery = makeMenu()
        let actions = submenu(recovery, "Recover Last Dictation")
        precondition(titles(actions) == ["Review Last Dictation…", "Retry Transcription", "Discard Recording"])
        record("recovery", recovery)
        record("recovery-actions", actions)
        guard let discard = actions.items.firstIndex(where: { $0.title == "Discard Recording" }) else {
            preconditionFailure("Missing discard action")
        }
        actions.performActionForItem(at: discard)
        precondition(!app.pipeline.hasRecoverableRecording, "Native discard must reach the real pipeline")
        precondition(!titles(makeMenu()).contains("Recover Last Dictation"))

        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: directory.appendingPathComponent("menu-verification.json"))
        print("PASS: native menu groups, shortcut badge, provider/profile states, long names, missing device, busy/recovery and discard")
    }

    private static func captureMenu(_ menu: NSMenu, to url: URL) {
        let request = CaptureRequest(menu: menu, url: url)
        let timer = Timer(timeInterval: 0.25, repeats: false) { _ in
            MainActor.assumeIsolated { request.capture() }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: 350, y: 650), in: nil)
        timer.invalidate()
        precondition(request.captured, "Could not capture the fixture's native menu: \(url.lastPathComponent)")
    }

    @MainActor private final class CaptureRequest {
        let menu: NSMenu
        let url: URL
        var captured = false

        init(menu: NSMenu, url: URL) { self.menu = menu; self.url = url }

        func capture() {
            defer { menu.cancelTracking() }
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            guard let info = windows.first(where: {
                ($0[kCGWindowOwnerPID as String] as? Int32) == ProcessInfo.processInfo.processIdentifier
                    && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
            }), let number = info[kCGWindowNumber as String] as? UInt32 else { return }
            typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return }
            let capture = unsafeBitCast(symbol, to: Capture.self)
            guard let image = capture(.null, 1 << 3, number, 1 << 0)?.takeRetainedValue(),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
            try! png.write(to: url)
            captured = true
        }
    }
}
#endif
