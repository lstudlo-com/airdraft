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
        // Expected titles come from the same catalogs, so the fixture passes in
        // every shipped language and fails when a title stays untranslated.
        func L(_ key: String.LocalizationValue) -> String { String(localized: key) }
        let profileName = app.profiles.activeProfile.displayName
        let storedProfileName = app.profiles.activeProfile.name
        // An unrenamed built-in shows its catalog name; its stored name stays English.
        if app.profiles.activeProfile.id == RefinementProfile.cleanID, storedProfileName == "Clean" {
            let english = (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en")
            precondition(english == (profileName == "Clean"), "Built-in profile names must be localized in the menu: \(profileName)")
        }
        // Runtime text passed as `.verbatim` is never looked up as a catalog key,
        // even when it matches one ("Settings…" is translated in zh-Hant).
        precondition(String(localized: LocalizedStringResource.verbatim("Settings…")) == "Settings…",
                     "Verbatim text must not be translated")
        report["language"] = Bundle.main.preferredLocalizations.first ?? "unknown"
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
        // Recording group: dictation, the meeting recorder's entry point, then History and Settings.
        let firstGroup = normal.items.prefix { !$0.isSeparatorItem }.map(\.title)
        let expectedGroup = [L("Start Dictation"), L("Record Meeting…"), L("History…"), L("Settings…")]
        precondition(firstGroup == expectedGroup, "Unexpected recording group: \(firstGroup), expected \(expectedGroup)")
        let lastGroup = Array(normal.items.reversed().prefix { !$0.isSeparatorItem }.map(\.title).reversed())
        precondition(lastGroup == [L("Check for Updates…"), L("Quit Airdraft")], "Unexpected app commands: \(lastGroup)")
        let localRefinement = L("Refinement: \(LLMProviderKind.openAICompatible.shortTitle)")
        precondition(titles(normal).contains(L("Profile: \(profileName)")) && titles(normal).contains(localRefinement),
                     "Current choices belong in root submenu titles. Actual: \(titles(normal))")
        precondition(!titles(normal).contains(where: { $0.contains(L("Loaded")) || $0.contains(settings.hotkey.displayString) }))
        precondition(normal.items.first?.keyEquivalent == "", "The menu must not register a second dictation shortcut")
        precondition(normal.items.first?.badge != nil, "The shortcut hint must stay on the recording row")
        let models = submenu(normal, L("Models"))
        precondition(titles(models).contains(L("Speech: \("Cohere") · \(L("Loaded"))")), "Status must use the profile's speech model. Actual: \(titles(models))")
        precondition(titles(models).contains(L("Unload Models")) && titles(models).contains(L("Manage Models…")))
        let microphoneTitle = titles(normal).first { $0.hasPrefix(L("Microphone: \("")")) } ?? ""
        let microphones = submenu(normal, microphoneTitle)
        precondition(titles(microphones).first == L("System Default"), "Unexpected microphone choices: \(titles(microphones))")
        record("normal", normal)
        record("models", models)

        app.models.llmStatus.set(.unreachable)
        let offline = makeMenu()
        let refinement = submenu(offline, L("Refinement: \(L("Unavailable"))"))
        precondition(titles(refinement).contains(L("Dictation will use raw text")) && titles(refinement).contains(L("Refinement Settings…")),
                     "Unexpected refinement details: \(titles(refinement))")
        precondition(offline.items.first?.isEnabled == true, "Unavailable refinement must not block dictation")
        record("refinement-offline", offline)
        record("refinement-details", refinement)

        settings.llm.select(.groq)
        precondition(titles(makeMenu()).contains(L("Refinement: \("Groq")")), "A stale local failure must not label a cloud provider unavailable")
        settings.llm.select(.openAICompatible)

        profile.usesLLM = false
        app.profiles.update(profile)
        let verbatim = makeMenu()
        let refinementOff = L("Refinement: \(L("Off"))")
        precondition(titles(verbatim).contains(refinementOff), "The profile's opt-out overrides provider health")
        precondition(titles(submenu(verbatim, L("Models"))).contains(refinementOff))
        precondition(titles(submenu(verbatim, refinementOff)).contains(L("Off for this profile")))
        record("profile-refinement-off", verbatim, capture: false)
        profile.usesLLM = true
        profile.name = String(repeating: "Long profile name ", count: 12)
        app.profiles.update(profile)
        settings.microphone = MicrophonePreference(uid: "missing-menu-fixture", name: String(repeating: "Studio microphone ", count: 12))
        let long = makeMenu()
        precondition(titles(long).contains(L("Microphone: \(L("Unavailable"))")))
        precondition(titles(long).first(where: { $0.hasPrefix(L("Profile: \("")")) })?.hasSuffix("…") == true)
        record("long-and-missing", long)
        profile.name = storedProfileName
        app.profiles.update(profile)
        settings.microphone = .systemDefault

        app.models.llmStatus.set(.remote)
        app.engineStatus.setPreviewState(app.speechConfig.engineID, .notLoaded)
        precondition(!titles(submenu(makeMenu(), L("Models"))).contains(L("Unload Models")))
        app.hotkeys.suspended = true
        let shortcut = makeMenu()
        precondition(titles(shortcut).contains(L("Set Up Shortcut…")))
        record("shortcut-unavailable", shortcut, capture: false)

        // Missing local model files produce a real retained recording without
        // microphone, credential, model-download or text-insertion access.
        app.pipeline.insertionEnabled = false
        app.pipeline.processSamples([Float](repeating: 0.01, count: 1_600))
        let busy = makeMenu()
        precondition(busy.items.first?.isEnabled == false)
        precondition(titles(busy).contains(L("Cancel Dictation")))
        record("processing", busy, capture: false)
        let deadline = Date().addingTimeInterval(5)
        while app.pipeline.isBusy && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(app.pipeline.hasRecoverableRecording && app.pipeline.lastIssue != nil,
                     "Missing local files must retain a recovery recording")
        let recovery = makeMenu()
        let actions = submenu(recovery, L("Recover Last Dictation"))
        precondition(titles(actions) == [L("Review Last Dictation…"), L("Retry Transcription"), L("Discard Recording")],
                     "Unexpected recovery actions: \(titles(actions))")
        record("recovery", recovery)
        record("recovery-actions", actions)
        guard let discard = actions.items.firstIndex(where: { $0.title == L("Discard Recording") }) else {
            preconditionFailure("Missing discard action")
        }
        actions.performActionForItem(at: discard)
        precondition(!app.pipeline.hasRecoverableRecording, "Native discard must reach the real pipeline")
        precondition(!titles(makeMenu()).contains(L("Recover Last Dictation")))

        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: directory.appendingPathComponent("menu-verification.json"))
        print("PASS (\(report["language"] ?? "")): native menu groups, localized titles, shortcut badge, provider/profile states, long names, missing device, busy/recovery and discard")
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
