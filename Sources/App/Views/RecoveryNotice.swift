import AirdraftCore
import AppKit
import SwiftUI

/// Keep the message and its action together, including when a long diagnostic wraps.
struct NoticeRow<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: Actions

    init(_ message: String, @ViewBuilder actions: () -> Actions) {
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: Theme.controlSpacing) {
            Text(message).supportingText().textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions.fixedSize()
        }
        .buttonStyle(SoftButtonStyle())
    }
}

/// Standalone notices own a card; rows embedded in an existing card do not.
struct InlineNotice<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: Actions

    init(_ message: String, @ViewBuilder actions: () -> Actions) {
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        SettingsCard { NoticeRow(message) { actions } }
    }
}

struct StorageNotice: View {
    let message: String
    var actionTitle = "Retry Saving"
    let retry: () -> Void

    var body: some View {
        InlineNotice(message) {
            Button(actionTitle, action: retry)
        }
    }
}

struct DictationRecovery: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        if let message = RenderMode.value("NOTICE") ?? container.pipeline.lastIssue {
            InlineNotice(message) {
                HStack(spacing: Theme.controlSpacing) {
                    if container.pipeline.hasRecoverableRecording {
                        Button("Retry") { container.pipeline.retryRecording() }
                            .help("Retry transcription")
                        Menu {
                            Button("Change Provider") { container.navigation.page = .models }
                            Button("Discard Recording", role: .destructive) { container.pipeline.discardRecording() }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("Recording recovery options")
                    } else {
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
