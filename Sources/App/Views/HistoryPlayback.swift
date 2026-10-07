import AVFoundation
import AirdraftCore
import Observation
import SwiftUI

@MainActor
func makeHistoryPlayback() -> RecordingPlayback {
    #if DEBUG
    if RenderMode.isActive || LocalE2E.isActive {
        return RecordingPlayback(automaticUpdates: false) { url in try SilentHistoryTransport(url: url) }
    }
    #endif
    return RecordingPlayback { url in try HistoryAudioTransport(url: url) }
}

#if DEBUG
/// Render fixtures can exercise every button without opening an output device.
@MainActor
private final class SilentHistoryTransport: RecordingPlaybackTransport {
    let duration: TimeInterval
    var currentTime: TimeInterval = 0
    var isPlaying = false
    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        duration = Double(file.length) / file.processingFormat.sampleRate
    }
    func play() -> Bool { isPlaying = true; return true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
}
#endif

@MainActor
private final class HistoryAudioTransport: RecordingPlaybackTransport {
    private let player: AVAudioPlayer
    init(url: URL) throws { player = try AVAudioPlayer(contentsOf: url) }
    var duration: TimeInterval { player.duration }
    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }
    var isPlaying: Bool { player.isPlaying }
    func play() -> Bool { player.play() }
    func pause() { player.pause() }
    func stop() { player.stop() }
}

struct HistoryTranscriptionReview: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var showRaw = false
    @State private var copied = false

    private var text: String {
        let result = container.pipeline.reviewOutcome
        return (showRaw ? result?.raw : result?.final) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            HStack {
                Text("Retranscription").font(.title2.weight(.semibold))
                Spacer()
                if container.pipeline.isBusy { ProgressView().controlSize(.small) }
            }
            Text("Current model and profile · original unchanged")
                .supportingText()
            if container.pipeline.reviewOutcome != nil {
                SoftSegmentedPicker("Version", selection: $showRaw, options: [(false, "Refined"), (true, "Raw")])
                ScrollView {
                    Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 120, maxHeight: .infinity)
            } else if !container.pipeline.isBusy && container.pipeline.lastIssue == nil {
                EmptyNote("No speech detected.")
            }
            if let issue = container.pipeline.lastIssue {
                Text(issue).font(.callout).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack {
                if container.pipeline.hasRecoverableRecording {
                    Button("Retry") { container.pipeline.retryRecording() }.disabled(container.pipeline.isBusy)
                }
                Spacer()
                Button(container.pipeline.isBusy ? "Cancel" : "Close") { dismiss() }
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }.disabled(text.isEmpty)
            }.buttonStyle(SoftButtonStyle())
        }
        .padding(Theme.pagePadding)
        .frame(width: 520, height: 400)
    }
}
