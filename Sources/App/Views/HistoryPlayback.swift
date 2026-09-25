import AVFoundation
import AirdraftCore
import Observation
import SwiftUI

@MainActor
@Observable
final class HistoryPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var recordID: Int64?
    private var player: AVAudioPlayer?

    func toggle(_ record: DictationRecord, store: HistoryStore) throws {
        if recordID == record.id { stop(); return }
        stop()
        guard let url = store.audioURL(for: record) else { throw CocoaError(.fileNoSuchFile) }
        let candidate = try AVAudioPlayer(contentsOf: url)
        candidate.delegate = self
        guard candidate.play() else { throw CocoaError(.fileReadCorruptFile) }
        player = candidate
        recordID = record.id
    }

    func stop() {
        player?.stop()
        player = nil
        recordID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.stop()
        }
    }
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
            Text("Uses your current speech model and profile. The original history entry stays unchanged.")
                .font(.callout).foregroundStyle(.secondary)
            if container.pipeline.reviewOutcome != nil {
                Picker("Version", selection: $showRaw) {
                    Text("Refined").tag(false)
                    Text("Raw").tag(true)
                }.pickerStyle(.segmented).fixedSize()
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
