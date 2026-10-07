import AirdraftCore
import SwiftUI

struct MenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if container.pipeline.isMaintainingData {
            Text("Data Cleanup")
            Button("Open Airdraft…") { container.showMainWindow(openWindow) }
            Divider()
            Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .disabled(container.cleanup.isRunning)
        } else if container.meeting?.isBusy == true {
            Text(container.meeting?.state == .finishing ? "Saving Meeting…" : "Recording Meeting")
            Button("Stop and Save Meeting") { Task { await container.meeting?.stop() } }
                .disabled(container.meeting?.state != .recording)
            Button("Show Meeting…") { show(.meetings) }
            Divider()
            Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } else if container.media?.isBusy == true {
            Text(MenuTitle.fit(container.media?.activity ?? "Preparing Media…"))
            Button("Pause Media Job") { container.media?.cancel() }
            Button("History…") { show(.history) }
            Divider()
            Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } else {
            standardMenu
        }
    }

    private var standardMenu: some View {
        Group {
        Button(MenuTitle.fit(dictationTitle)) { container.pipeline.toggle() }
            .badge(container.pipeline.state.isBusy ? nil : Text(container.settings.hotkey.displayString))
            .help(shortcutHelp)
            .disabled(container.pipeline.isBusy && !container.pipeline.isRecording)
        if container.pipeline.state.isBusy {
            Button("Cancel Dictation") { container.pipeline.cancel() }
        }
        recoveryMenu
        if !container.hotkeys.isActive {
            Button("Set Up Shortcut…") {
                if container.hotkeys.needsAccessibility {
                    container.openAccessibilitySettings()
                } else {
                    container.navigation.page = .configuration
                    container.showMainWindow(openWindow)
                }
            }
            .help(container.hotkeys.statusText)
        }
        Button("Record Meeting…") { show(.meetings); container.meeting?.isPresented = true }
            .disabled(container.pipeline.isBusy || container.meeting == nil)
        Button("History…") { show(.history) }
        Button("Settings…") { show(.configuration) }
            .keyboardShortcut(",")
        Divider()

        MicrophonePicker(title: MenuTitle.fit("Microphone: \(microphoneLabel)"), fitsMenu: true)

        Picker(MenuTitle.fit("Profile: \(container.profiles.activeProfile.name)"), selection: Binding(
            get: { container.profiles.activeProfileID },
            set: { container.profiles.setActive($0) }
        )) {
            ForEach(container.profiles.profiles) { profile in
                Text(MenuTitle.fit(profile.name)).help(profile.name).tag(profile.id)
            }
        }
        .help("Profile: \(container.profiles.activeProfile.name). Changes apply to the next dictation.")

        Menu(MenuTitle.fit("Refinement: \(refinementLabel)")) {
            if !container.profiles.activeProfile.usesLLM {
                Text("Off for this profile")
                Button("Profile Settings…") { show(.profiles) }
                Divider()
            } else if refinementUnavailable {
                Text("Refinement unavailable").help(llmDetail)
                Text("Dictation will use raw text")
                Divider()
            }
            Picker("Provider", selection: Binding(
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
            Button("Refinement Settings…") { show(.models) }
        }
        .help(llmDetail)

        Menu("Models") {
            Text(MenuTitle.fit("Speech: \(speechProviderLabel) · \(speechStateLabel)"))
                .help("Speech: \(container.speechConfig.engineLabel) · \(fullSpeechStateLabel)")
            Text(MenuTitle.fit("Refinement: \(llmSummary)"))
                .help("Refinement: \(llmDetail)")
            Divider()
            Button("Manage Models…") { show(.models) }
            if canUnloadModels {
                Button("Unload Models") {
                    container.models.unloadSpeechModels()
                    container.models.unloadLLM()
                }
                .disabled(container.pipeline.isBusy)
            }
        }
        Divider()

        Button("Check for Updates…") { container.updates.checkForUpdates() }
            .disabled(!container.updates.canCheckForUpdates)
        Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
        }
    }

    private func show(_ page: Page) {
        container.navigation.page = page
        container.showMainWindow(openWindow)
    }

    @ViewBuilder private var recoveryMenu: some View {
        if container.pipeline.hasRecoverableRecording {
            Menu("Recover Last Dictation") {
                Button("Review Last Dictation…") { show(.home) }
                    .help(container.pipeline.lastIssue ?? "Review the saved recording.")
                Divider()
                Button("Retry Transcription") { container.pipeline.retryRecording() }
                    .disabled(container.pipeline.isBusy)
                Button("Discard Recording") { container.pipeline.discardRecording() }
                    .disabled(container.pipeline.isBusy)
            }
        } else if let issue = container.pipeline.lastIssue {
            Button("Review Last Dictation…") { show(.home) }.help(issue)
        }
    }

    private var microphoneLabel: String {
        let preference = container.settings.microphone
        guard preference.uid != nil else { return "Default" }
        return container.microphones.selected(preference) == nil ? "Unavailable" : preference.name
    }

    private var refinementLabel: String {
        guard container.profiles.activeProfile.usesLLM, container.settings.llm.kind != .none else { return "Off" }
        return refinementUnavailable ? "Unavailable" : container.settings.llm.kind.shortTitle
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
        if container.speechConfig.kind == .apple { return "Built in" }
        guard container.speechConfig.kind.isLocal else { return "Cloud" }
        switch container.engineStatus.state(for: container.speechConfig.engineID) {
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .ready: return "Loaded"
        case .failed: return "Unavailable"
        }
    }

    private var fullSpeechStateLabel: String {
        if container.speechConfig.kind == .apple { return "Built in" }
        guard container.speechConfig.kind.isLocal else { return "Cloud" }
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
        case .senseVoice: return "SenseVoice"
        case .parakeet: return "Parakeet"
        case .whisperKit: return "WhisperKit"
        case .apple: return "Apple Speech"
        case .openAICompatible: return "Custom server"
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox,
             .assemblyAI, .cartesia, .speechmatics, .xAI, .mistral, .gemini:
            return container.speechConfig.kind.preset?.name ?? "Cloud"
        }
    }

    private var llmStateLabel: String {
        if container.settings.llm.kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason == nil ? "On-device" : "Unavailable"
        }
        if container.settings.llm.kind != .openAICompatible && !container.settings.llm.kind.isCLI {
            return "Cloud"
        }
        switch container.models.llmStatus.state {
        case .unknown: return "Checking…"
        case .remote: return "Cloud"
        case .ready(let detail): return detail == "CLI not found" ? "CLI missing" : "Ready"
        case .unreachable: return "Server offline"
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .loaded: return "Loaded"
        case .failed: return "Unavailable"
        }
    }

    private var llmSummary: String {
        guard container.profiles.activeProfile.usesLLM, container.settings.llm.kind != .none else { return "Off" }
        return "\(container.settings.llm.kind.shortTitle) · \(llmStateLabel)"
    }

    private var llmDetail: String {
        guard container.profiles.activeProfile.usesLLM else { return "Raw transcript; refinement is off for this profile." }
        guard container.settings.llm.kind != .none else { return "Raw transcript without refinement" }
        if container.settings.llm.kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason ?? "Apple Intelligence · on-device"
        }
        return "\(container.settings.llm.engineLabel) · \(container.models.llmStatus.label)"
    }

    private var shortcutHelp: String {
        let verb = container.settings.hotkeyBehavior == .hold ? "Hold" : "Press"
        return "\(verb) \(container.settings.hotkey.displayString) to dictate."
    }

    private var dictationTitle: String {
        switch container.pipeline.state {
        case .idle, .failed, .notice: return "Start Dictation"
        case .recording: return "Stop & Transcribe"
        case .preparingModel: return "Loading Speech Model…"
        case .transcribing: return "Transcribing…"
        case .refining: return "Refining…"
        case .inserting: return "Inserting…"
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

    static func fit(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        if fits(line) { return line }
        // The first sentence usually carries the whole reason.
        if let end = line.range(of: ". ") {
            let sentence = String(line[..<end.lowerBound]) + "."
            if fits(sentence) { return sentence }
        }
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

    private static func fits(_ text: String) -> Bool {
        (text as NSString).size(withAttributes: [.font: font]).width <= maxWidth
    }
}
