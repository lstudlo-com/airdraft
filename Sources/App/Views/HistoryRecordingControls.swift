import AirdraftCore
import SwiftUI

struct HistoryRecordingControls: View {
    let asset: RecordingAsset
    let playback: RecordingPlayback
    let busy: Bool
    let exporting: Bool
    let play: @MainActor () -> Void
    let save: @MainActor () -> Void
    let reveal: @MainActor () -> Void
    let retranscribe: (@MainActor () -> Void)?
    let delete: (@MainActor () -> Void)?
    var accessibilityOnly = false

    var body: some View {
        let active = playback.recordingID == asset.id
        let playing = active && playback.isPlaying
        if asset.source == .meeting {
            Text("Meeting audio").supportingText()
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
                SoftSlider(title: "Playback position", value: .constant(0), range: 0...max(0.01, asset.duration), step: 0.1,
                           valueDescription: { Self.position($0, of: asset.duration) })
                    .disabled(true)
                    .help("Play the recording to seek")
                Text("0:00 / \(Self.time(asset.duration))")
                    .appFont(.caption2).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    // The slider's value already reads the position.
                    .accessibilityHidden(true)
            }
            Button(exporting ? "Saving…" : "Save Audio…", action: save)
                .appFont(.supporting)
                .buttonStyle(SoftButtonStyle())
                .disabled(exporting)
                .accessibilityIdentifier("recording.save.\(asset.id)")
            if accessibilityOnly { fileActions }
            else {
                Menu { fileActions } label: { Image(systemName: "ellipsis").accessibilityLabel("Recording Actions") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Recording actions")
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

    /// Spoken playback position: "0:12 of 1:05".
    nonisolated static func position(_ seconds: Double, of duration: Double) -> String {
        String(localized: "\(time(seconds)) of \(time(duration))", comment: "Playback position for VoiceOver")
    }

    nonisolated static func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 359_999))) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
                            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Only the selected recording observes the 5 Hz clock. Other lazy cards do not
/// read currentTime or recompute transcript layout on playback ticks.
struct HistoryPlaybackProgress: View {
    let playback: RecordingPlayback
    var body: some View {
        SoftSlider(title: "Playback position", value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                   range: 0...max(0.01, playback.duration), step: 0.1, keyboardStep: 5,
                   valueDescription: { HistoryRecordingControls.position($0, of: playback.duration) })
        Text("\(HistoryRecordingControls.time(playback.currentTime)) / \(HistoryRecordingControls.time(playback.duration))")
            .appFont(.caption2).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            .accessibilityHidden(true)
    }
}
