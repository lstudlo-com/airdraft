import AirdraftCore
import SwiftUI

struct MenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = container.settings

        Text(statusLine)
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
        Divider()

        MicrophonePicker()

        Picker("Profile", selection: Binding(
            get: { container.profiles.activeProfileID },
            set: { container.profiles.setActive($0) }
        )) {
            ForEach(container.profiles.profiles) { profile in
                Label(profile.name, systemImage: profile.symbol).tag(profile.id)
            }
        }
        Picker("Refinement", selection: Binding(
            get: { container.settings.llm.kind },
            set: { container.settings.llm.select($0) }
        )) {
            ForEach(LLMProviderKind.allCases) { Text($0.title).tag($0) }
        }
        Text("Speech: \(speechProviderLabel) · \(speechStateLabel)")
            .help("\(settings.asr.engineLabel) · \(fullSpeechStateLabel)")
        Text(llmSummary)
            .help(llmDetail)
        Button("Unload models") {
            container.models.unloadSpeechModels()
            container.models.unloadLLM()
        }
        Divider()

        Button("Open Airdraft…") { container.showMainWindow(openWindow) }
        Button("History…") { container.navigation.page = .history; container.showMainWindow(openWindow) }
        Button("Check for Updates…") { container.updates.checkForUpdates() }
            .disabled(!container.updates.canCheckForUpdates)
        Divider()
        Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var speechStateLabel: String {
        guard container.settings.asr.kind.isLocal else { return "Cloud" }
        switch container.engineStatus.state(for: container.settings.asr.engineID) {
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading…"
        case .ready: return "Loaded"
        case .failed: return "Unavailable"
        }
    }

    private var fullSpeechStateLabel: String {
        guard container.settings.asr.kind.isLocal else { return "Cloud" }
        return container.engineStatus.state(for: container.settings.asr.engineID).label
    }

    private var speechProviderLabel: String {
        switch container.settings.asr.kind {
        case .qwen3: return "Qwen3-ASR"
        case .fireRed: return "FireRedASR2"
        case .cohere: return "Cohere"
        case .senseVoice: return "SenseVoice"
        case .whisperKit: return "WhisperKit"
        case .apple: return "Apple Speech"
        case .openAICompatible: return "Custom server"
        case .openAI, .openRouter, .groq, .elevenLabs, .deepgram, .soniox:
            return container.settings.asr.kind.preset?.name ?? "Cloud"
        }
    }

    private var llmStateLabel: String {
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
        guard container.settings.llm.kind != .none else { return "Refinement: Off" }
        return "LLM: \(container.settings.llm.kind.shortTitle) · \(llmStateLabel)"
    }

    private var llmDetail: String {
        guard container.settings.llm.kind != .none else { return "Raw transcript without refinement" }
        return "\(container.settings.llm.engineLabel) · \(container.models.llmStatus.label)"
    }

    private var statusDetail: String {
        switch container.pipeline.state {
        case .failed(let message), .notice(let message): return message
        default: return statusLine
        }
    }

    private var statusLine: String {
        switch container.pipeline.state {
        case .idle:
            let verb = container.settings.hotkeyBehavior == .hold ? "hold" : "press"
            return "Ready · \(verb) \(container.settings.hotkey.displayString) to dictate"
        case .recording: return "Listening…"
        case .preparingModel: return "Loading speech model…"
        case .transcribing: return "Transcribing…"
        case .refining: return "Refining…"
        case .inserting: return "Inserting…"
        case .failed: return "Dictation failed"
        case .notice(let message): return message
        }
    }
}
