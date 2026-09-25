import AirdraftCore
import AppKit
import SwiftUI

struct StorageNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        SettingsCard {
            Text(message).font(.system(size: 12.5)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Retry Saving", action: retry).buttonStyle(SoftButtonStyle())
            }
        }
    }
}

struct DictationRecovery: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        if let message = container.pipeline.lastIssue {
            SettingsCard {
                Text(message).font(.system(size: 12.5)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.controlSpacing) {
                    if container.pipeline.hasRecoverableRecording {
                        Button("Retry Transcription") { container.pipeline.retryRecording() }
                        Button("Change Provider") { container.navigation.page = .models }
                        Spacer(minLength: 0)
                        Button("Discard Recording", role: .destructive) { container.pipeline.discardRecording() }
                    } else {
                        Spacer()
                        Button("Dismiss") { container.pipeline.dismissIssue() }
                    }
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(container.pipeline.isBusy)
            }
        }
        if let message = container.pipeline.historyStorageError {
            StorageNotice(message: message) { Task { await container.pipeline.retryHistorySave() } }
                .disabled(container.pipeline.isSavingHistory)
            if let outcome = container.pipeline.lastOutcome {
                Button("Copy Last Dictation") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outcome.final, forType: .string)
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }
}
