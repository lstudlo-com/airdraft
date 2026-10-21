import AirdraftCore
import AppKit
import SwiftUI

/// Keep the message and its action together, including when a long diagnostic wraps.
struct NoticeRow<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: Actions

    init(_ message: LocalizedStringResource, @ViewBuilder actions: () -> Actions) {
        self.message = String(localized: message)
        self.actions = actions()
    }

    /// Runtime text, such as an error message, that is already localized.
    @_disfavoredOverload
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

    init(_ message: LocalizedStringResource, @ViewBuilder actions: () -> Actions) {
        self.message = String(localized: message)
        self.actions = actions()
    }

    /// Runtime text, such as an error message, that is already localized.
    @_disfavoredOverload
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
    var actionTitle: LocalizedStringResource = "Retry Saving"
    let retry: () -> Void

    var body: some View {
        InlineNotice(message) {
            Button(String(localized: actionTitle), action: retry)
        }
    }
}

struct DictationRecovery: View {
    @Environment(AppContainer.self) private var container

    private struct RecoveryCard {
        let id: UUID?
        let issue: String
        let others: Int
    }

    /// The newest kept dictation; older ones surface after it is retried or discarded.
    private var recoveryCard: RecoveryCard? {
        if let pending = container.pipeline.latestPendingDictation {
            let others = container.pipeline.pendingRecordings.filter { !$0.isReview }.count - 1
            return RecoveryCard(id: pending.id, issue: pending.issue, others: others)
        }
        // Debug renders: AIRDRAFT_RENDER_PENDING_RECORDINGS=<count> uses NOTICE as the failure.
        if let count = RenderMode.value("PENDING_RECORDINGS").flatMap(Int.init), count > 0,
           let issue = RenderMode.value("NOTICE") {
            return RecoveryCard(id: nil, issue: issue, others: count - 1)
        }
        return nil
    }

    private func message(for card: RecoveryCard) -> String {
        switch card.others {
        case ..<1: return card.issue
        case 1: return card.issue + " " + String(localized: "Another recording is also waiting for retry.")
        default: return card.issue + " " + String(localized: "\(card.others) other recordings are also waiting for retry.")
        }
    }

    var body: some View {
        let card = recoveryCard
        if let card {
            // The kept recording keeps its own failure text after later dictations.
            InlineNotice(message(for: card)) {
                HStack(spacing: Theme.controlSpacing) {
                    Button("Retry") { container.pipeline.retryRecording(card.id) }
                        .help("Retry transcription")
                    Menu {
                        Button("Change Provider") { container.navigation.page = .models }
                        Button("Discard Recording", role: .destructive) { container.pipeline.discardRecording(card.id) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Recording recovery options")
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(container.pipeline.isBusy)
            }
        }
        if let message = RenderMode.value("NOTICE") ?? container.pipeline.lastIssue, message != card?.issue {
            InlineNotice(message) {
                Button("Dismiss") { container.pipeline.dismissIssue() }
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
