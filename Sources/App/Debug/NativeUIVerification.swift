#if DEBUG
import AirdraftCore
import AppKit
import CoreAudio
import SwiftUI

/// Production views with disposable stores and fake capture. Never starts the app,
/// a microphone, provider, model load, credential operation or audio playback.
@MainActor
enum NativeUIVerification {
    private final class Monitor: MicrophoneLevelMonitoring, @unchecked Sendable {
        var levelHandler: (@Sendable (Float) -> Void)?
        var interruptionHandler: (@Sendable (AudioRecorderError) -> Void)?
        private(set) var selection: MicrophonePreference?
        private(set) var cancelled = false
        func startLevelMonitoring(microphone: MicrophonePreference) throws { selection = microphone }
        func cancel() { cancelled = true }
    }
    private final class AccessGate {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }
    private final class SilentWindow: NSWindow {
        override func noResponder(for eventSelector: Selector) {}
    }

    static func run(to directory: URL) {
        setbuf(stdout, nil)
        precondition(LocalE2E.isActive && RenderMode.isActive, "Use --e2e-local with --render-window native-ui")
        precondition(ProcessInfo.processInfo.environment["AIRDRAFT_E2E_MODEL_ROOT"]?.hasPrefix("/") == true,
                     "Use an absolute disposable model root")
        precondition(LocalModels.root.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(
            LocalE2E.directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"),
            "The UI model fixture must stay inside its disposable E2E directory")
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "airdraft.native-ui.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.asr = ASRConfig(kind: .senseVoice, language: "en")
        settings.llm.select(.none)
        settings.useAppContext = false
        let gate = AccessGate()
        let container = AppContainer(settings: settings,
            dataDirectory: LocalE2E.directory.appendingPathComponent("native-ui-\(UUID())"),
            recordingAccessCheck: { await gate.wait() },
            permissions: SystemPermissions(checkAccessibility: { true }, checkMicrophone: { .authorized },
                                           promptAccessibility: { preconditionFailure("Unexpected permission prompt") }))
        container.microphones.useRenderDevices([
            Microphone(id: 100, uid: "fixture-main", name: "Fixture Main", inputChannelCount: 2),
            Microphone(id: 101, uid: "fixture-secondary", name: "Fixture Secondary"),
            Microphone(id: 102, uid: "fixture-phone", name: "Fixture Phone",
                       transportType: kAudioDeviceTransportTypeContinuityCaptureWireless)
        ], systemDefaultID: 100)
        settings.microphone = MicrophonePreference(uid: "fixture-main", name: "Fixture Main", channelIndex: 1)
        verifyMicrophones(container, gate: gate, directory: directory)
        verifyReadiness(container, directory: directory)
        verifyPractice(container, directory: directory)
        verifyNotices(directory: directory)
        verifyCleanupRecovery(directory: directory)
        container.dictionary.add(DictionaryEntry(term: "Airdraft", aliases: ["air draft", "air draught"]))
        container.dictionary.add(DictionaryEntry(term: "SwiftUI", aliases: ["swift you eye"]))
        container.navigation.page = .vocabulary
        container.navigation.sidebarCollapsed = true
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = show(MainWindowView().environment(container), appearance: appearance, width: Theme.windowWidth, height: 720)
            capture(window, to: directory.appendingPathComponent("vocabulary-collapsed-\(appearance == .aqua ? "light" : "dark").png"))
            close(window)
        }
        print("NATIVE_UI_PASS populated-vocabulary collapsed-shell light-dark")
    }

    private static func verifyMicrophones(_ container: AppContainer, gate: AccessGate, directory: URL) {
        var monitors: [Monitor] = []
        let previews = MicrophoneLevelPreviews { let monitor = Monitor(); monitors.append(monitor); return monitor }
        // OverlayPanel intentionally hides sibling AX content while modal.
        // Each real surface gets its own window so settings remain inspectable.
        let settingsWindow = show(MicrophoneSettings().padding(24).environment(container), width: 590, height: 240)
        let window = show(MicrophoneSelectionOverlay(onClose: {}, previews: previews)
            .padding(24).environment(container), width: 390, height: 340)
        precondition(monitors.count == 2 && monitors.allSatisfy { !$0.cancelled }, "One monitor per eligible device; no unselected Continuity input")
        precondition(monitors.first?.selection?.channelIndex == 1)
        monitors.first?.levelHandler?(0.4); pump()
        precondition(previews.levels["fixture-main"] == 0.4, "An active fake level must reach the actual preview")
        precondition(text(find(label: "System Default", in: window)).contains("Input level 4 of 10"),
                     "System Default must share the physical device's level")
        precondition(press(label: "System Default", in: window))
        pump()
        precondition(container.settings.microphone.uid == nil && container.settings.microphone.channelIndex == 1,
                     "System Default alias must retain the selected physical channel")
        let saved = container.settings.microphone
        let stale = monitors.first!.levelHandler

        @MainActor func blocked(_ name: String, begin: () -> Void, end: () -> Void) {
            begin(); pump()
            precondition(container.pipeline.state == .idle && container.pipeline.isBusy, "Exercise aggregate \(name) state")
            precondition(monitors.allSatisfy(\.cancelled), "\(name) must stop every preview")
            precondition(previews.levels.isEmpty)
            stale?(0.9); pump()
            precondition(previews.levels.isEmpty, "Stopped callbacks cannot restore levels")
            precondition(!enabled(find(id: "microphone.device-picker", in: settingsWindow)))
            precondition(!enabled(find(id: "microphone.channel-picker", in: settingsWindow)))
            precondition(!press(label: "Fixture Secondary", in: window), "Busy overlay must reject selection")
            precondition(container.settings.microphone == saved)
            end(); pump()
            precondition(!container.pipeline.isBusy && monitors.suffix(2).allSatisfy { !$0.cancelled })
            precondition(enabled(find(id: "microphone.device-picker", in: settingsWindow)))
            print("NATIVE_UI_PASS microphone-\(name) inactive-preview guarded-controls stale-callback")
        }
        blocked("meeting", begin: { container.pipeline.isCapturingMeeting = true }, end: { container.pipeline.isCapturingMeeting = false })
        blocked("media", begin: { container.pipeline.isProcessingMedia = true }, end: { container.pipeline.isProcessingMedia = false })
        blocked("maintenance", begin: { try! container.pipeline.beginDataMaintenance() }, end: { container.pipeline.endDataMaintenance() })
        blocked("pending-startup", begin: {
            container.pipeline.startRecording()
            pump()
            precondition(gate.continuation != nil, "Startup must be held before preflight or capture")
        }, end: {
            container.pipeline.cancel()
            gate.release()
        })
        precondition(press(label: "Fixture Phone", in: window))
        precondition(container.settings.microphone.uid == "fixture-phone" && container.settings.microphone.channelIndex == nil)
        precondition(monitors.filter { !$0.cancelled }.count == 3, "Only selected Continuity adds one monitor")
        precondition(press(label: "System Default", in: window))
        precondition(monitors.filter { !$0.cancelled }.count == 2 &&
                     monitors.filter { $0.selection?.uid == "fixture-phone" }.allSatisfy(\.cancelled),
                     "Deselecting Continuity must stop its preview")
        container.settings.microphone = MicrophonePreference(uid: "fixture-unavailable", name: "Disconnected Fixture", channelIndex: 3)
        pump()
        let unavailable = find(label: "Disconnected Fixture", in: window)
        precondition(!enabled(unavailable) && text(unavailable).contains("Unavailable"))
        precondition(container.settings.microphone.channelIndex == 3, "Keep unavailable selection recoverable")
        capture(window, to: directory.appendingPathComponent("microphone-unavailable.png"))
        close(window)
        precondition(monitors.allSatisfy(\.cancelled), "Closing the overlay must stop previews")
        close(settingsWindow)
        container.settings.microphone = saved
        container.navigation.page = .configuration
        let shell = show(MainWindowView().environment(container), width: Theme.windowWidth, height: 720)
        for operation in ["meeting", "media", "maintenance"] {
            if operation == "meeting" { container.pipeline.isCapturingMeeting = true }
            if operation == "media" { container.pipeline.isProcessingMedia = true }
            if operation == "maintenance" { try! container.pipeline.beginDataMaintenance() }
            pump()
            precondition(!enabled(find(id: "sidebar.microphone", in: shell)), "Sidebar must use aggregate \(operation) state")
            container.pipeline.isCapturingMeeting = false
            container.pipeline.isProcessingMedia = false
            container.pipeline.endDataMaintenance()
            pump()
            precondition(enabled(find(id: "sidebar.microphone", in: shell)))
        }
        close(shell)
        print("NATIVE_UI_PASS microphone-unavailable-channel sidebar-operation-gates")
    }

    private static func verifyReadiness(_ container: AppContainer, directory: URL) {
        var profile = container.profiles.activeProfile
        profile.speechModel = nil
        profile.usesLLM = false
        container.profiles.update(profile)
        container.settings.llm.select(.openAICompatible)
        for (name, config) in [("parakeet-zh", ASRConfig(kind: .parakeet, language: "zh")),
                               ("cohere-auto", ASRConfig(kind: .cohere, language: ""))] {
            container.settings.asr = config
            container.engineStatus.setPreviewState(config.engineID, .ready)
            container.navigation.page = .home
            let window = show(HomePage().environment(container).contentIsland(), width: 604, height: 900)
            let row = find(id: "readiness.speech", in: window)
            precondition(text(row).contains("Needs attention"), "Unsupported language must never be ready")
            let expected: String
            do { _ = try SpeechLanguagePolicy.resolve(config); preconditionFailure("Fixture must be unsupported") }
            catch { expected = error.localizedDescription }
            precondition(text(row).contains(expected), "Show the same actionable policy error used by preflight")
            precondition(text(find(id: "readiness.refinement", in: window)).contains("Off · original transcript"))
            precondition(text(window).contains("no refinement"), "Summary must respect profile refinement opt-out")
            precondition(press(id: "home.speech-language-action", in: window))
            precondition(container.navigation.page == .models, "Language action must reach Models")
            capture(window, to: directory.appendingPathComponent("home-\(name).png"))
            close(window)
        }
        verifyLocalReadiness(container, directory: directory)
        container.settings.asr = ASRConfig(kind: .openAICompatible, language: "en")
        let ready = show(HomePage().environment(container).contentIsland(), width: 604, height: 900)
        let row = text(find(id: "readiness.speech", in: ready))
        precondition(row.contains("Ready") && row.contains("Custom endpoint") && !row.contains("Needs attention"))
        close(ready)
        print("NATIVE_UI_PASS home-language-label-tone-repair profile-refinement-opt-out valid-config")
    }

    private static func verifyLocalReadiness(_ container: AppContainer, directory: URL) {
        let config = ASRConfig(kind: .senseVoice, language: "en")
        let folder = LocalModels.folder(for: config)!
        precondition(!FileManager.default.fileExists(atPath: folder.path), "Use a fresh model root; existing files are never changed")
        container.settings.asr = config
        container.engineStatus.setPreviewState(config.engineID, .notLoaded)
        let missing = show(HomePage().environment(container).contentIsland(), width: 604, height: 900)
        let missingText = text(find(id: "readiness.speech", in: missing))
        precondition(missingText.contains("Needs attention") && missingText.contains("Model not installed"))
        precondition(press(label: "Get Model", in: missing) && container.navigation.page == .models)
        close(missing)

        // Presence markers exercise UI readiness only. No model loader is invoked,
        // and the native Load Model button is inspected but never pressed.
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["tokens.txt", "model.onnx"] {
            try! Data("UI presence fixture; never load".utf8).write(to: folder.appendingPathComponent(name))
        }
        precondition(LocalModels.isInstalled(config))
        let unloaded = show(HomePage().environment(container).contentIsland(), width: 604, height: 900)
        precondition(text(find(id: "readiness.speech", in: unloaded)).contains("Needs attention"))
        precondition(enabled(find(label: "Load Model", in: unloaded)))
        capture(unloaded, to: directory.appendingPathComponent("home-installed-unloaded.png"))
        container.engineStatus.setPreviewState(config.engineID, .ready); pump()
        let readyText = text(find(id: "readiness.speech", in: unloaded))
        precondition(readyText.contains("Ready") && !readyText.contains("Needs attention") && !readyText.contains("Load Model"))
        capture(unloaded, to: directory.appendingPathComponent("home-installed-ready.png"))
        close(unloaded)

        var profile = container.profiles.activeProfile
        let saved = profile
        var retired = ASRConfig(kind: .groq)
        retired.model = "retired-fixture-model"
        profile.speechModel = ProfileSpeechModel(config: retired)
        container.profiles.update(profile)
        let invalid = show(HomePage().environment(container).contentIsland(), width: 604, height: 900)
        let row = find(id: "readiness.speech", in: invalid)
        precondition(text(row).contains("Needs attention") && text(row).contains(profile.speechModel!.unavailableReason!))
        guard let action = descendants(row).first(where: { value($0, "accessibilityLabel") as? String == "Profiles" }) else {
            preconditionFailure("Invalid binding must offer the Profiles repair route")
        }
        precondition(press(action) && container.navigation.page == .profiles)
        close(invalid)
        container.profiles.update(saved)
        print("NATIVE_UI_PASS home-missing-get-model installed-unloaded-load installed-ready retired-binding-profiles")
    }

    private static func verifyPractice(_ container: AppContainer, directory: URL) {
        var retired = ASRConfig(kind: .groq)
        retired.model = "retired-fixture-model"
        var profile = container.profiles.activeProfile
        profile.speechModel = ProfileSpeechModel(config: retired)
        profile.usesLLM = true
        container.profiles.update(profile)
        let savedProfile = container.profiles.activeProfile
        let settings = container.settings
        settings.asr = ASRConfig(kind: .senseVoice, language: "en")
        settings.onboarding.present()
        settings.onboarding.move(to: .practice)
        container.engineStatus.setPreviewState(settings.asr.engineID, .notLoaded)
        container.engineStatus.setPreviewState(retired.engineID, .ready)
        let practice = show(OnboardingView().environment(container), width: Theme.windowWidth, height: 760)
        precondition(settings.isOnboardingPractice && container.speechConfig.kind == .senseVoice)
        precondition(text(practice).contains("Load the speech model to start speaking."), "Readiness must follow selected practice engine")
        precondition(!text(practice).contains("Model is ready"), "Bound profile status must not masquerade as practice readiness")
        container.engineStatus.setPreviewState(settings.asr.engineID, .ready); pump()
        precondition(text(practice).contains("Model is ready"))
        capture(practice, to: directory.appendingPathComponent("practice-selected-engine-ready.png"))
        precondition(press(id: "onboarding.back", in: practice)); pump()
        precondition(!settings.isOnboardingPractice && settings.onboarding.step == .speech)
        precondition(container.speechConfig.kind == .groq && container.profiles.activeProfile == savedProfile)
        close(practice)

        settings.asr = ASRConfig(kind: .parakeet, language: "zh")
        let parakeetFolder = LocalModels.folder(for: settings.asr)!
        precondition(!FileManager.default.fileExists(atPath: parakeetFolder.path), "Use fresh disposable model fixtures")
        try! FileManager.default.createDirectory(at: parakeetFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parakeetFolder) }
        for name in ["tokens.txt", "encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx"] {
            try! Data("UI presence fixture; never load".utf8).write(to: parakeetFolder.appendingPathComponent(name))
        }
        precondition(LocalModels.isInstalled(settings.asr), "Distinguish unsupported language from a missing model")
        settings.onboarding.move(to: .practice)
        let invalid = show(OnboardingView().environment(container), width: Theme.windowWidth, height: 900)
        precondition(settings.isOnboardingPractice && container.speechConfig.kind == .parakeet)
        precondition(press(id: "onboarding.change-language", in: invalid)); pump()
        precondition(settings.onboarding.step == .speech && !settings.isOnboardingPractice)
        precondition(settings.asr.language == "zh", "Recovery must preserve explicit shared language")
        precondition(!enabled(find(id: "onboarding.continue", in: invalid)))
        precondition(!text(find(id: "speech-language-issue", in: invalid)).isEmpty,
                     "Speech choice must validate selected Parakeet, not the active cloud binding")
        capture(invalid, to: directory.appendingPathComponent("practice-language-recovery.png"))
        settings.asr.language = "en"; pump()
        precondition(enabled(find(id: "onboarding.continue", in: invalid)),
                     "With the same installed model, a supported explicit language must enable Continue")
        // Never press Continue: presence markers are not loadable model files.
        close(invalid)
        settings.onboarding.dismiss()
        settings.endOnboardingPractice()
        precondition(container.profiles.activeProfile == savedProfile)
        print("NATIVE_UI_PASS onboarding-selected-readiness retired-binding back installed-language-guard profile-preserved")
    }

    private static func verifyNotices(directory: URL) {
        var loaded = 0, saved = 0
        var frames: [String: CGRect] = [:]
        let message = "A disposable operation could not finish. The diagnostic wraps beside its action, while the outer card keeps the same inset on every side."
        let root = VStack(spacing: Theme.sectionSpacing) {
            SettingsCard {
                NoticeRow(message) { Button("Retry") {} }
                    .background(measurement("row"))
            }
            .background(measurement("card"))
            StorageNotice(message: message, actionTitle: "Reload History") { loaded += 1 }
            StorageNotice(message: message) { saved += 1 }
        }.padding(Theme.pagePadding).background(Theme.islandBackground)
            .coordinateSpace(name: "notice-fixture")
            .onPreferenceChange(NoticeFrames.self) { frames = $0 }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = show(root, appearance: appearance, width: 540, height: 370)
            capture(window, to: directory.appendingPathComponent("notices-\(appearance == .aqua ? "light" : "dark").png"))
            guard let card = frames["card"], let row = frames["row"] else { preconditionFailure("Missing rendered notice geometry") }
            precondition([row.minX - card.minX, card.maxX - row.maxX, row.minY - card.minY, card.maxY - row.maxY]
                .allSatisfy { abs($0 - 16) < 0.5 }, "Embedded notice must have one equal 16-point inset: \(frames)")
            guard let diagnostic = descendants(window).first(where: {
                value($0, "accessibilityLabel") as? String == message || value($0, "accessibilityValue") as? String == message
            }), let textFrame = (value(diagnostic, "accessibilityFrame") as? NSValue)?.rectValue,
               let actionFrame = (value(find(label: "Retry", in: window), "accessibilityFrame") as? NSValue)?.rectValue else {
                preconditionFailure("Rendered diagnostic and action must expose their actual frames")
            }
            let font = NSFont.systemFont(ofSize: 11)
            let singleLine = ceil(font.ascender - font.descender + font.leading)
            print("NOTICE_GEOMETRY", "card", card, "row", row, "text", textFrame, "action", actionFrame)
            precondition(textFrame.height > singleLine * 1.5 && textFrame.maxX <= actionFrame.minX &&
                         abs(textFrame.midY - actionFrame.midY) <= 2,
                         "Diagnostic must wrap beside its vertically centered action")
            precondition(press(label: "Reload History", in: window))
            precondition(press(label: "Retry Saving", in: window))
            close(window)
        }
        precondition(loaded == 2 && saved == 2)
        print("NATIVE_UI_PASS notice-single-16-inset load-save-actions wrapping light-dark")
    }

    private struct NoticeFrames: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
    private static func measurement(_ name: String) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: NoticeFrames.self, value: [name: geometry.frame(in: .named("notice-fixture"))])
        }
    }

    private static func verifyCleanupRecovery(directory: URL) {
        precondition(RenderMode.excludesCredentials)
        var finished = false
        Task { @MainActor in
            do {
                try await ArchitectureVerification.withFailedLegacyCleanup { container in
                    let references = container.cleanupRecoveryKeyReferences
                    precondition(!references.isEmpty && container.cleanup.blocksWork)
                    let window = show(DataCleanupProgress().environment(container), width: 510, height: 510)
                    @MainActor func editors() -> [NSObject] {
                        descendants(window).filter {
                            (value($0, "accessibilityIdentifier") as? String)?.hasPrefix("cleanup.provider-access.") == true
                        }
                    }
                    precondition(editors().isEmpty, "A failed journal must not mount a credential editor automatically")
                    precondition(press(id: "cleanup.repair-provider-access", in: window))
                    for reference in references {
                        let editor = find(id: "cleanup.provider-access.\(reference)", in: window)
                        let controls = descendants(editor).filter {
                            ["AXTextField", "AXButton"].contains(value($0, "accessibilityRole") as? String ?? "")
                        }
                        precondition(!controls.isEmpty && controls.allSatisfy { !enabled($0) },
                                     "Fixture may inspect disabled provider recovery UI only")
                    }
                    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                        window.appearance = NSAppearance(named: appearance); pump()
                        capture(window, to: directory.appendingPathComponent("cleanup-provider-recovery-\(appearance == .aqua ? "light" : "dark").png"))
                    }
                    precondition(container.cleanup.blocksWork, "Repair UI cannot open ordinary work during pending cleanup")
                    precondition(press(id: "cleanup.repair-provider-access", in: window))
                    precondition(editors().isEmpty)
                    close(window)
                }
                print("NATIVE_UI_PASS cleanup-recovery-explicit-open correct-references credential-controls-disabled fence-preserved")
                finished = true
            } catch { preconditionFailure("Cleanup UI fixture failed: \(error)") }
        }
        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline { pump() }
        precondition(finished, "Cleanup UI fixture timed out")
    }

    private static func show<V: View>(_ root: V, appearance: NSAppearance.Name = .aqua,
                                      width: CGFloat, height: CGFloat) -> NSWindow {
        let window = SilentWindow(contentRect: NSRect(x: 150, y: 70, width: width, height: height),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Airdraft silent UI verification"
        window.appearance = NSAppearance(named: appearance)
        // Keep intrinsic hosting-size negotiation from enlarging measurement
        // fixtures, and include the native window background in bitmap evidence.
        window.contentView = NSHostingView(rootView: root.frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor)))
        window.makeKeyAndOrderFront(nil)
        pump()
        return window
    }
    private static func close(_ window: NSWindow) { window.orderOut(nil); window.contentView = nil; pump() }
    private static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
    private static func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    private static func descendants(_ object: Any) -> [NSObject] {
        guard let item = object as? NSObject else { return [] }
        return [item] + ((value(item, "accessibilityChildren") as? [Any]) ?? []).flatMap(descendants)
    }
    private static func find(id: String, in window: NSWindow) -> NSObject {
        guard let item = descendants(window).first(where: { value($0, "accessibilityIdentifier") as? String == id }) else {
            preconditionFailure("Missing actual control \(id); accessible content: \(text(window))")
        }
        return item
    }
    private static func find(label: String, in window: NSWindow) -> NSObject {
        guard let item = descendants(window).first(where: { value($0, "accessibilityLabel") as? String == label }) else {
            preconditionFailure("Missing actual control \(label); accessible content: \(text(window))")
        }
        return item
    }
    private static func enabled(_ object: NSObject) -> Bool { value(object, "isAccessibilityEnabled") as? Bool ?? true }
    private static func text(_ object: NSObject) -> String {
        descendants(object).flatMap { item in
            [value(item, "accessibilityLabel"), value(item, "accessibilityValue")].compactMap { $0 as? String }
        }.joined(separator: "\n")
    }
    private static func press(id: String, in window: NSWindow) -> Bool { press(find(id: id, in: window)) }
    private static func press(label: String, in window: NSWindow) -> Bool { press(find(label: label, in: window)) }
    private static func press(_ object: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard object.responds(to: selector) else { return false }
        let call = unsafeBitCast(object.method(for: selector), to: (@convention(c) (NSObject, Selector) -> Bool).self)
        let result = call(object, selector)
        pump()
        return result
    }
    private static func capture(_ window: NSWindow, to url: URL) {
        let view = window.contentView!
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
#endif
