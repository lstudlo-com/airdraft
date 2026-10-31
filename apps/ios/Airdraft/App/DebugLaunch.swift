#if DEBUG
import AirdraftCore
import Foundation

/// Debug-only launch arguments for simulator screenshots, which cannot tap:
/// `-AirdraftScreen <home|history|settings|speech|refinement|keyboard-setup|onboarding|keyboard>`
/// opens that screen and `-AirdraftSampleData` fills History and the last
/// result with sample dictations. Release builds contain none of this.
enum DebugLaunch {
    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AirdraftScreen"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var sampleData: Bool { ProcessInfo.processInfo.arguments.contains("-AirdraftSampleData") }

    @MainActor
    static func loadSampleData(into container: MobileContainer) {
        guard sampleData else { return }
        defer {
            container.controller.debugShow(MobileDictationResult(
                transcript: Transcript(text: sampleText, language: "en", engine: "apple-speech:en-US", latencyMs: 420),
                refined: sampleText, final: sampleText, audioSeconds: 5.2, profileName: "Clean"))
        }
        guard let history = container.history, (try? history.count()) == 0 else { return }
        let samples = [
            (sampleText, 5.2),
            ("Remember to buy oat milk, coffee beans and a birthday card for Mia.", 4.1),
            ("The keyboard session keeps the microphone ready, so dictation starts at once.", 6.8),
        ]
        for (index, sample) in samples.enumerated() {
            let record = DictationRecord(createdAt: Date().addingTimeInterval(TimeInterval(-3_600 * index * 9)),
                                         mode: "Clean", family: "other", rawTranscript: sample.0,
                                         refinedText: sample.0, finalText: sample.0, language: "en",
                                         asrEngine: "apple-speech:en-US", audioSeconds: sample.1, asrMs: 420, llmMs: 0,
                                         inserted: index == 0, outputDestination: index == 0 ? "cursor" : "copy",
                                         outputSucceeded: true)
            _ = try? history.save(record)
        }
    }

    private static let sampleText = "Let's move the design review to Thursday afternoon and invite the iOS team."
}
import SwiftUI

/// The keyboard as it appears in another app, for `-AirdraftScreen keyboard`.
/// `-AirdraftKeyboardPhase ready|recording|off` sets the shared session state first.
struct KeyboardPreviewScreen: View {
    @State private var model = KeyboardModel(proxy: { nil }, hasFullAccess: { true }, nextKeyboard: {})

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Notes").font(.largeTitle.bold())
                Text(verbatim: "Pick up the dry cleaning before six.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            KeyboardView(model: model, showsGlobe: true)
                .background(Color(uiColor: .secondarySystemBackground))
        }
        .task {
            // After the app's own launch publish, which resets the shared state.
            try? await Task.sleep(for: .seconds(1))
            let arguments = ProcessInfo.processInfo.arguments
            let phase = arguments.firstIndex(of: "-AirdraftKeyboardPhase").flatMap {
                $0 + 1 < arguments.count ? KeyboardBridge.State.Phase(rawValue: arguments[$0 + 1]) : nil
            } ?? .ready
            let now = Date()
            KeyboardBridge.Store()?.state = KeyboardBridge.State(
                phase: phase, endsAt: phase == .off ? nil : now.addingTimeInterval(300),
                recordingStartedAt: phase == .recording ? now.addingTimeInterval(-7) : nil,
                message: nil, updatedAt: now)
            model.refresh()
        }
    }
}
#endif
