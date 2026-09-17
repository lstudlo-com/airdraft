import AirdraftCore
import SwiftUI

struct MenuView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = container.settings

        Text(statusLine)
        if !container.hotkeys.isActive {
            Button("⚠︎ Hotkey inactive: \(container.hotkeys.statusText)") {
                if container.hotkeys.needsAccessibility { container.openAccessibilitySettings() }
            }
        }
        if let outcome = container.pipeline.lastOutcome {
            Text(String(outcome.final.prefix(60)))
                .font(.caption)
            Text("ASR \(outcome.asrMs) ms · LLM \(outcome.llmMs) ms" + (outcome.llmSkippedReason.map { " · \($0)" } ?? ""))
                .font(.caption)
        }
        Divider()

        Button(container.pipeline.isRecording ? "Stop & Transcribe" : "Start Dictation") {
            container.pipeline.toggle()
        }
        if container.pipeline.state.isBusy {
            Button("Cancel") { container.pipeline.cancel() }
        }
        Divider()

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
        Text("Speech: \(settings.asr.engineLabel) · \(speechStateLabel)")
        Text("LLM: \(settings.llm.engineLabel) · \(container.models.llmStatus.label)")
        Button("Unload models") {
            container.models.unloadSpeechModels()
            container.models.unloadLLM()
        }
        Divider()

        Button("Open Airdraft…") { container.showMainWindow(openWindow) }
        Button("History…") { container.navigation.page = .history; container.showMainWindow(openWindow) }
        Divider()
        Button("Quit Airdraft") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var speechStateLabel: String {
        guard container.settings.asr.kind.isLocal else { return "Cloud" }
        return container.engineStatus.state(for: container.settings.asr.engineID).label
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
        case .failed(let msg): return "Error: \(msg)"
        case .notice(let msg): return msg
        }
    }
}
