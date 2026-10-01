import AirdraftCore
import SwiftUI

struct MenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = container.settings

        Text(MenuTitle.fit(statusLine))
            .help(statusDetail)
        if !container.hotkeys.isActive {
            Button("Shortcut unavailable…") {
                if container.hotkeys.needsAccessibility {
                    container.openAccessibilitySettings()
                } else {
                    container.navigation.page = .configuration
                    container.showMainWindow(openWindow)
                }
            }
            .help(container.hotkeys.statusText)
        }
        Divider()

        Button(container.pipeline.isRecording ? "Stop & Transcribe" : "Start Dictation") {
            container.pipeline.toggle()
        }
        if container.pipeline.state.isBusy {
            Button("Cancel") { container.pipeline.cancel() }
        }
        if let issue = container.pipeline.lastIssue {
            if issue != statusMessage {
                Text(MenuTitle.fit(issue)).help(issue)
            }
            Button("Show Recovery…") { container.navigation.page = .home; container.showMainWindow(openWindow) }
        }
        if container.pipeline.hasRecoverableRecording {
            Button("Retry Transcription") { container.pipeline.retryRecording() }.disabled(container.pipeline.isBusy)
            Button("Discard Recording") { container.pipeline.discardRecording() }.disabled(container.pipeline.isBusy)
        }
        Divider()

        MicrophonePicker(fitsMenu: true)

        Picker("Profile", selection: Binding(
            get: { container.profiles.activeProfileID },
            set: { container.profiles.setActive($0) }
        )) {
            ForEach(container.profiles.profiles) { profile in
                Text(MenuTitle.fit(profile.name)).tag(profile.id)
            }
        }
        Picker("Refinement", selection: Binding(
            get: { container.settings.llm.kind },
            set: { container.settings.llm.select($0) }
        )) {
            ForEach(LLMProviderKind.allCases.filter { !RenderMode.excludesCredentials || !$0.requiresKey }) {
                Text(MenuTitle.fit($0.title)).tag($0)
            }
        }
        // The header names the group, so the rows need no "Speech:" prefixes.
        // The section supplies its own separators.
        Section("Models") {
            Text(MenuTitle.fit("\(speechProviderLabel) · \(speechStateLabel)"))
                .help("Speech: \(settings.asr.engineLabel) · \(fullSpeechStateLabel)")
            Text(MenuTitle.fit(llmSummary))
                .help("Refinement: \(llmDetail)")
            if canUnloadModels {
                Button("Unload Models") {
                    container.models.unloadSpeechModels()
                    container.models.unloadLLM()
                }
            }
        }

        Button("Open Airdraft…") { container.showMainWindow(openWindow) }
        Button("History…") { container.navigation.page = .history; container.showMainWindow(openWindow) }
        Button("Check for Updates…") { container.updates.checkForUpdates() }
            .disabled(!container.updates.canCheckForUpdates)
        Divider()
        Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var speechStateLabel: String {
        if container.settings.asr.kind == .apple { return "Built in" }
        guard container.settings.asr.kind.isLocal else { return "Cloud" }
        switch container.engineStatus.state(for: container.settings.asr.engineID) {
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .ready: return "Loaded"
        case .failed: return "Unavailable"
        }
    }

    private var fullSpeechStateLabel: String {
        if container.settings.asr.kind == .apple { return "Built in" }
        guard container.settings.asr.kind.isLocal else { return "Cloud" }
        return container.engineStatus.state(for: container.settings.asr.engineID).label
    }

    private var canUnloadModels: Bool {
        let asr = container.settings.asr
        let speechLoaded = asr.kind.isLocal && asr.kind != .apple
            && container.engineStatus.state(for: asr.engineID) == .ready
        return speechLoaded || container.models.llmStatus.isLoaded
    }

    private var speechProviderLabel: String {
        switch container.settings.asr.kind {
        case .qwen3: return "Qwen3-ASR"
        case .fireRed: return "FireRedASR2"
        case .cohere: return "Cohere"
        case .senseVoice: return "SenseVoice"
        case .parakeet: return "Parakeet"
        case .whisperKit: return "WhisperKit"
        case .apple: return "Apple Speech"
        case .openAICompatible: return "Custom server"
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox:
            return container.settings.asr.kind.preset?.name ?? "Cloud"
        }
    }

    private var llmStateLabel: String {
        if container.settings.llm.kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason == nil ? "On-device" : "Unavailable"
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
        guard container.settings.llm.kind != .none else { return "Refinement off" }
        return "\(container.settings.llm.kind.shortTitle) · \(llmStateLabel)"
    }

    private var llmDetail: String {
        guard container.settings.llm.kind != .none else { return "Raw transcript without refinement" }
        if container.settings.llm.kind == .appleIntelligence {
            return AppleIntelligenceRefiner.unavailableReason ?? "Apple Intelligence · on-device"
        }
        return "\(container.settings.llm.engineLabel) · \(container.models.llmStatus.label)"
    }

    private var statusMessage: String? {
        switch container.pipeline.state {
        case .failed(let message), .notice(let message, _): return message
        default: return nil
        }
    }

    private var statusDetail: String { statusMessage ?? statusLine }

    private var statusLine: String {
        switch container.pipeline.state {
        case .idle:
            let verb = container.settings.hotkeyBehavior == .hold ? "Hold" : "Press"
            return "\(verb) \(container.settings.hotkey.displayString) to dictate"
        case .recording: return "Listening…"
        case .preparingModel: return "Loading speech model…"
        case .transcribing: return "Transcribing…"
        case .refining: return "Refining…"
        case .inserting: return "Inserting…"
        // The HUD shows a failure only briefly; the tooltip keeps its full reason.
        case .failed(let message): return "Failed: \(message)"
        case .notice(let message, _): return message
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
