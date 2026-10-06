import AirdraftCore
import SwiftUI

struct HistoryRecordingControls: View {
    let asset: RecordingAsset
    let playback: RecordingPlayback
    let busy: Bool
    let exporting: Bool
    let play: () -> Void
    let save: () -> Void
    let reveal: () -> Void
    let retranscribe: (() -> Void)?
    let delete: (() -> Void)?
    var accessibilityOnly = false

    var body: some View {
        let active = playback.recordingID == asset.id
        let playing = active && playback.isPlaying
        if asset.source == .meeting {
            Text("Meeting · microphone left, app audio right").supportingText()
        }
        if let issue = asset.captureIssue {
            DisclosureGroup("Recording Details") { Text(issue).supportingText().textSelection(.enabled) }.settingsDisclosure()
        }
        HStack(spacing: 8) {
            Button(action: play) { Image(systemName: playing ? "pause.fill" : "play.fill") }
                .buttonStyle(SoftIconButtonStyle())
                .help(playing ? "Pause recording" : "Play recording")
                .accessibilityLabel(playing ? "Pause Recording" : "Play Recording")
                .accessibilityIdentifier("recording.play.\(asset.id)")
                .disabled(busy)
            if active {
                HistoryPlaybackProgress(playback: playback)
            } else {
                SoftSlider(title: "Playback position", value: .constant(0), range: 0...max(0.01, asset.duration), step: 0.1)
                    .disabled(true)
                    .help("Play the recording to seek")
                Text("0:00 / \(Self.time(asset.duration))")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            Button(exporting ? "Saving…" : "Save Audio…", action: save)
                .font(.system(size: 11))
                .buttonStyle(SoftButtonStyle())
                .disabled(exporting)
                .accessibilityIdentifier("recording.save.\(asset.id)")
            if accessibilityOnly { fileActions }
            else {
                Menu { fileActions } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Recording actions").accessibilityLabel("Recording Actions")
            }
        }
    }

    @ViewBuilder private var fileActions: some View {
        Button("Show in Finder", action: reveal).accessibilityIdentifier("recording.reveal.\(asset.id)")
        if let retranscribe { Button("Retranscribe", action: retranscribe) }
        if let delete {
            Divider()
            Button("Delete Recording Only…", role: .destructive, action: delete)
        }
    }

    static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 359_999))) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
                            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Only the selected recording observes the 5 Hz clock. Other lazy cards do not
/// read currentTime or recompute transcript layout on playback ticks.
private struct HistoryPlaybackProgress: View {
    let playback: RecordingPlayback
    var body: some View {
        SoftSlider(title: "Playback position", value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                   range: 0...max(0.01, playback.duration), step: 0.1, keyboardStep: 5)
            .accessibilityValue("\(HistoryRecordingControls.time(playback.currentTime)) of \(HistoryRecordingControls.time(playback.duration))")
        Text("\(HistoryRecordingControls.time(playback.currentTime)) / \(HistoryRecordingControls.time(playback.duration))")
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
    }
}
