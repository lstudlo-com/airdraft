import AppIntents
import Foundation

struct StartDictationIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Start Dictation"
    static var description = IntentDescription("Start recording with your current speech model and refinement profile.")
    static var openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        let app = AppContainer.shared
        try await app.prepareForAutomation()
        try await app.pipeline.startFromAutomation()
        return .result()
    }
}

struct StopDictationIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Stop Dictation"
    static var description = IntentDescription("Stop recording and begin transcription. Processing and text delivery continue after this action returns.")
    static var openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        let app = AppContainer.shared
        try await app.prepareForAutomation()
        try app.pipeline.stopFromAutomation()
        return .result()
    }
}

struct CancelDictationIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Cancel Dictation"
    static var description = IntentDescription("Cancel the current dictation and discard its unsaved audio. Text delivery cannot be cancelled once it begins.")
    static var openAppWhenRun = false
    @available(macOS 26, *)
    static var supportedModes: IntentModes { .background }

    @MainActor
    func perform() async throws -> some IntentResult {
        let app = AppContainer.shared
        try await app.prepareForAutomation()
        try app.pipeline.cancelFromAutomation()
        return .result()
    }
}

struct AirdraftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDictationIntent(),
                    phrases: ["Start dictation in \(.applicationName)"],
                    shortTitle: "Start Dictation", systemImageName: "mic")
        AppShortcut(intent: StopDictationIntent(),
                    phrases: ["Stop dictation in \(.applicationName)"],
                    shortTitle: "Stop Dictation", systemImageName: "stop.circle")
        AppShortcut(intent: CancelDictationIntent(),
                    phrases: ["Cancel dictation in \(.applicationName)"],
                    shortTitle: "Cancel Dictation", systemImageName: "xmark.circle")
    }
}
