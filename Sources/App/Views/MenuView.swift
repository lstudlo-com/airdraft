import AirdraftCore
import SwiftUI

struct MenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if container.pipeline.isMaintainingData {
            Text(String(localized: "Data Cleanup"))
            Button(String(localized: "Open Airdraft…")) { container.showMainWindow(openWindow) }
            Divider()
            Button(String(localized: "Quit Airdraft")) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .disabled(container.cleanup.isRunning)
        } else if container.meeting?.isBusy == true {
            Text(container.meeting?.state == .finishing ? String(localized: "Saving Recording…") : String(localized: "Recording Audio"))
            Button(String(localized: "Stop and Save Recording")) { Task { await container.meeting?.stop() } }
                .disabled(container.meeting?.state != .recording)
            Button(String(localized: "Show Recording…")) { show(.meetings) }
            Divider()
            Button(String(localized: "Quit Airdraft")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } else if container.media?.isBusy == true {
            Text(MenuTitle.fit(container.media?.activity ?? String(localized: "Preparing Media…")))
            Button(String(localized: "Pause Media Job")) { container.media?.cancel() }
            Button(String(localized: "History…")) { show(.history) }
            Divider()
            Button(String(localized: "Quit Airdraft")) { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } else {
            standardMenu
        }
    }

    private var standardMenu: some View {
        Group {
        Button(MenuTitle.fit(dictationTitle)) { container.pipeline.toggle() }
            .badge(container.pipeline.state.isBusy ? nil : Text(container.settings.hotkey.localizedDisplayString))
            .help(shortcutHelp)
            .disabled(container.pipeline.isBusy && !container.pipeline.isRecording)
        if container.pipeline.state.isBusy {
            Button(String(localized: "Cancel Dictation")) { container.pipeline.cancel() }
        }
        recoveryMenu
        if !container.hotkeys.isActive {
            Button(String(localized: "Set Up Shortcut…")) {
                if container.hotkeys.needsAccessibility {
                    container.openAccessibilitySettings()
                } else {
                    container.navigation.page = .configuration
                    container.showMainWindow(openWindow)
                }
            }
            .help(container.hotkeys.statusText)
        }
        Button(String(localized: "Record Audio…")) { show(.meetings); container.meeting?.isPresented = true }
            .disabled(container.pipeline.isBusy || container.meeting == nil)
        Button(String(localized: "History…")) { show(.history) }
        Button(String(localized: "Settings…")) { show(.configuration) }
            .keyboardShortcut(",")
        Divider()

        MicrophonePicker(title: MenuTitle.fit(String(localized: "Microphone: \(microphoneLabel)")), fitsMenu: true)

        Picker(MenuTitle.profile(upcoming.profile.displayName, app: autoProfileApp), selection: Binding(
            get: { container.profiles.activeProfileID },
            set: { container.profiles.setActive($0) }
        )) {
            ForEach(container.profiles.profiles) { profile in
                Text(MenuTitle.fit(profile.displayName)).help(profile.displayName).tag(profile.id)
            }
        }
        .help(profileHelp)

        Menu(MenuTitle.fit(String(localized: "Refinement: \(refinementLabel)"))) {
            if !upcoming.profile.usesLLM {
                Text(String(localized: "Off for this profile"))
                Button(String(localized: "Profile Settings…")) { show(.profiles) }
                Divider()
            } else if refinementUnavailable {
                Text(String(localized: "Refinement unavailable")).help(llmDetail)
                Text(String(localized: "Dictation will use raw text"))
                Divider()
            }
            Picker(String(localized: "Provider"), selection: Binding(
                get: { container.settings.llm.kind },
                set: { container.settings.llm.select($0) }
            )) {
                ForEach(LLMProviderKind.allCases.filter { !RenderMode.excludesCredentials || !$0.requiresKey }) {
                    Text(MenuTitle.fit($0.title)).help($0.title).tag($0)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button(String(localized: "Refinement Settings…")) { show(.models) }
        }
        .help(llmDetail)

        Menu(String(localized: "Models")) {
            Text(MenuTitle.fit(String(localized: "Speech: \(speechProviderLabel) · \(speechStateLabel)")))
                .help(String(localized: "Speech: \(container.speechConfig.engineLabel) · \(fullSpeechStateLabel)"))
            Text(MenuTitle.fit(String(localized: "Refinement: \(llmSummary)")))
                .help(String(localized: "Refinement: \(llmDetail)"))
            Divider()
            Button(String(localized: "Manage Models…")) { show(.models) }
            if canUnloadModels {
                Button(String(localized: "Unload Models")) {
                    container.models.unloadSpeechModels()
                    container.models.unloadLLM()
                }
                .disabled(container.pipeline.isBusy)
            }
        }
        Divider()

        Button(String(localized: "Check for Updates…")) { container.updates.checkForUpdates() }
            .disabled(!container.updates.canCheckForUpdates)
        Button(String(localized: "Quit Airdraft")) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
        }
    }

    private func show(_ page: Page) {
        container.navigation.page = page
        container.showMainWindow(openWindow)
    }

    @ViewBuilder private var recoveryMenu: some View {
        if let pending = container.pipeline.latestPendingDictation {
            // Acts on the newest kept recording; Home lists how many others wait.
            Menu(String(localized: "Recover Last Dictation")) {
                Button(String(localized: "Review Last Dictation…")) { show(.home) }
                    .help(pending.issue)
                Divider()
                Button(String(localized: "Retry Transcription")) { container.pipeline.retryRecording(pending.id) }
                    .disabled(container.pipeline.isBusy)
                Button(String(localized: "Discard Recording")) { container.pipeline.discardRecording(pending.id) }
                    .disabled(container.pipeline.isBusy)
            }
        } else if let issue = container.pipeline.lastIssue {
            Button(String(localized: "Review Last Dictation…")) { show(.home) }.help(issue)
        }
    }

    /// The profile the frontmost app's dictation uses: its app rule, else the chosen one.
    private var upcoming: ProfileSelection { container.upcomingProfile }

    /// The app an automatic profile follows; nil when the chosen profile applies.
    private var autoProfileApp: String? {
        upcoming.isAutomatic ? container.frontmostApp.current?.name : nil
    }

    private var profileHelp: String {
        let name = upcoming.profile.displayName
        guard let app = autoProfileApp else {
            return String(localized: "Profile: \(name). Changes apply to the next dictation.")
        }
        return String(localized: "Profile: \(name), chosen by app for \(app). Other apps use \(container.profiles.activeProfile.displayName).")
    }

    private var microphoneLabel: String {
        let preference = container.settings.microphone
        guard preference.uid != nil else { return String(localized: "Default") }
        return container.microphones.selected(preference) == nil ? String(localized: "Unavailable") : preference.name
    }

    private var refinementLabel: String {
        guard upcoming.profile.usesLLM, container.settings.llm.kind != .none else { return String(localized: "Off") }
        return refinementUnavailable ? String(localized: "Unavailable") : container.settings.llm.kind.shortTitle
    }

    /// Current provider health is independent of an earlier dictation's issue.
    private var refinementUnavailable: Bool {
        let kind = container.settings.llm.kind
        if kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason != nil
        }
        if kind.isCLI {
            if case .ready("CLI not found") = container.models.llmStatus.state { return true }
            return false
        }
        guard kind == .openAICompatible else { return false }
        switch container.models.llmStatus.state {
        case .unreachable, .failed: return true
        default: return false
        }
    }

    private var speechStateLabel: String {
        if container.speechConfig.kind == .apple { return String(localized: "Built in") }
        guard container.speechConfig.kind.isLocal else { return String(localized: "Cloud") }
        switch container.engineStatus.state(for: container.speechConfig.engineID) {
        case .notLoaded: return String(localized: "Not loaded")
        case .loading: return String(localized: "Loading…")
        case .ready: return String(localized: "Loaded")
        case .failed: return String(localized: "Unavailable")
        }
    }

    private var fullSpeechStateLabel: String {
        if container.speechConfig.kind == .apple { return String(localized: "Built in") }
        guard container.speechConfig.kind.isLocal else { return String(localized: "Cloud") }
        return container.engineStatus.state(for: container.speechConfig.engineID).label
    }

    private var canUnloadModels: Bool {
        let asr = container.speechConfig
        let speechLoaded = asr.kind.isLocal && asr.kind != .apple
            && container.engineStatus.state(for: asr.engineID) == .ready
        return speechLoaded || container.models.llmStatus.isLoaded
    }

    private var speechProviderLabel: String {
        switch container.speechConfig.kind {
        case .qwen3: return "Qwen3-ASR"
        case .fireRed: return "FireRedASR2"
        case .cohere: return "Cohere"
        case .senseVoice, .senseVoiceMultilingual: return "SenseVoice"
        case .parakeet: return "Parakeet"
        case .orukeet: return "Orukeet"
        case .fluidAudio: return CoreMLSpeechModelCatalog.model(container.speechConfig.model)?.creator ?? String(localized: "Core ML speech")
        case .transcribeCpp: return GGUFModelCatalog.model(container.speechConfig.model)?.creator ?? String(localized: "Local speech")
        case .whisperKit: return "WhisperKit"
        case .apple: return "Apple Speech"
        case .openAICompatible: return String(localized: "Custom server")
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini:
            return container.speechConfig.kind.preset?.name ?? String(localized: "Cloud")
        }
    }

    private var llmStateLabel: String {
        if container.settings.llm.kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason == nil ? String(localized: "On-device") : String(localized: "Unavailable")
        }
        if container.settings.llm.kind != .openAICompatible && !container.settings.llm.kind.isCLI {
            return String(localized: "Cloud")
        }
        switch container.models.llmStatus.state {
        case .unknown: return String(localized: "Checking…")
        case .remote: return String(localized: "Cloud")
        case .ready(let detail): return detail == "CLI not found" ? String(localized: "CLI missing") : String(localized: "Ready")
        case .unreachable: return String(localized: "Server offline")
        case .notLoaded: return String(localized: "Not loaded")
        case .loading: return String(localized: "Loading…")
        case .loaded: return String(localized: "Loaded")
        case .failed: return String(localized: "Unavailable")
        }
    }

    private var llmSummary: String {
        guard upcoming.profile.usesLLM, container.settings.llm.kind != .none else { return String(localized: "Off") }
        return "\(container.settings.llm.kind.shortTitle) · \(llmStateLabel)"
    }

    private var llmDetail: String {
        guard upcoming.profile.usesLLM else { return String(localized: "Raw transcript; refinement is off for this profile.") }
        guard container.settings.llm.kind != .none else { return String(localized: "Raw transcript without refinement") }
        if container.settings.llm.kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason ?? String(localized: "Apple Intelligence · on-device")
        }
        return "\(container.settings.llm.engineLabel) · \(container.models.llmStatus.label)"
    }

    private var shortcutHelp: String {
        ShortcutCopy.menuHelp(container.settings.hotkeyBehavior.gesture(triggerDelayMilliseconds: container.settings.triggerDelayMilliseconds),
                              shortcut: container.settings.hotkey.localizedDisplayString)
    }

    private var dictationTitle: String {
        switch container.pipeline.state {
        case .idle, .failed, .notice: return String(localized: "Start Dictation")
        case .recording: return String(localized: "Stop & Transcribe")
        case .preparingModel: return String(localized: "Loading Speech Model…")
        case .transcribing: return String(localized: "Transcribing…")
        case .refining: return String(localized: "Refining…")
        case .inserting: return String(localized: "Inserting…")
        }
    }
}

/// Native menu items never wrap, so the widest title sets the whole menu's width.
/// Every dynamic title is fitted to one measured width, keeping the menu about
/// 270 points wide. Tooltips and the main window keep the full text.
@MainActor
enum MenuTitle {
    static let maxWidth: CGFloat = 190
    private static let font = NSFont.menuFont(ofSize: 0)

    /// The Profile submenu title. An automatic profile names the app it follows;
    /// a long title shortens the app name first, then the profile name, so both
    /// stay recognizable within the menu width.
    static func profile(_ name: String, app: String?) -> String {
        guard let app else { return fit(String(localized: "Profile: \(name)")) }
        func title(_ name: String, _ app: String) -> String {
            String(localized: "Profile: \(name) (auto: \(app))", comment: "Menu title; the profile was chosen automatically for the named app")
        }
        let full = title(name, app)
        if fits(full) { return full }
        if let shortApp = shortened(app, keeping: 3, toFit: { fits(title(name, $0)) }) { return title(name, shortApp) }
        let minimalApp = app.count > 3 ? String(app.prefix(3)) + "…" : app
        if let shortName = shortened(name, keeping: 3, toFit: { fits(title($0, minimalApp)) }) { return title(shortName, minimalApp) }
        // The app stays in the tooltip when even short names cannot fit.
        return fit(String(localized: "Profile: \(name) (auto)", comment: "Menu title; the profile was chosen automatically for the frontmost app"))
    }

    /// The longest prefix of `text`, at least `minimum` characters, that fits once
    /// an ellipsis is added; nil when even the minimum does not fit.
    private static func shortened(_ text: String, keeping minimum: Int, toFit fitting: (String) -> Bool) -> String? {
        let characters = Array(text)
        guard characters.count > minimum else { return nil }
        func prefix(_ count: Int) -> String {
            String(characters[..<count]).trimmingCharacters(in: .whitespaces) + "…"
        }
        guard fitting(prefix(minimum)) else { return nil }
        var low = minimum, high = characters.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if fitting(prefix(mid)) { low = mid } else { high = mid - 1 }
        }
        return prefix(low)
    }

    static func fit(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        if fits(line) { return line }
        // The first sentence usually carries the whole reason. The system's
        // sentence breaks cover every script's stops (. 。 । ؟), not only ". ".
        var first: String?
        line.enumerateSubstrings(in: line.startIndex..., options: .bySentences) { sentence, _, _, stop in
            first = sentence?.trimmingCharacters(in: .whitespaces)
            stop = true
        }
        if let sentence = first, !sentence.isEmpty, sentence.count < line.count, fits(sentence) { return sentence }
        let characters = Array(line)
        var low = 0, high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(String(characters[..<mid]) + "…") { low = mid } else { high = mid - 1 }
        }
        var cut = String(characters[..<low])
        // Break at a word unless that would drop most of the remaining text (CJK has no spaces).
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= low * 2 / 3 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    static func fits(_ text: String) -> Bool {
        (text as NSString).size(withAttributes: [.font: font]).width <= maxWidth
    }
}
