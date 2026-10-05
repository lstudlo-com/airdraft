import AirdraftCore
import SwiftUI

struct DataCleanupSettings: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: DataCleanupScope?
    @State private var preview: CleanupPreview?
    @State private var loading = false
    @State private var error: String?
    @State private var confirming = false

    var body: some View {
        PageSection("Data & reset") {
            SettingsCard {
                ForEach(Array(DataCleanupScope.allCases.enumerated()), id: \.element.id) { index, scope in
                    if index > 0 { RowDivider() }
                    SettingRow(title: scope == .reset ? "Start fresh" : shortTitle(scope), subtitle: subtitle(scope)) {
                        Button(scope.title + "…") { prepare(scope) }
                            .buttonStyle(SoftButtonStyle())
                            .disabled(loading || container.cleanup.blocksWork || container.pipeline.isBusy || container.pipeline.isSavingHistory || container.downloads.isBusy)
                            .accessibilityIdentifier("cleanup.\(scope.rawValue)")
                    }
                }
                if loading {
                    RowDivider()
                    ProgressView("Checking stored data…").controlSize(.small)
                }
                if let message = error ?? container.cleanup.error {
                    RowDivider()
                    InlineNotice(message) {
                        Button("Retry") {
                            if let selection { prepare(selection) }
                        }.buttonStyle(SoftButtonStyle())
                    }
                } else if let scope = container.cleanup.finishedScope, scope != .reset {
                    RowDivider()
                    Text("\(scope.title) completed.").supportingText()
                }
            }
        }
        .alert((selection?.title ?? "Remove Data") + "?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { selection = nil }
            Button(selection?.title ?? "Remove", role: .destructive) {
                if let selection { Task { await container.performCleanup(selection) } }
            }
        } message: { Text(confirmationMessage) }
    }

    private func shortTitle(_ scope: DataCleanupScope) -> String {
        switch scope {
        case .history: "History"
        case .audio: "Audio files"
        case .historyAndAudio: "History and audio"
        case .reset: "App reset"
        }
    }
    private func subtitle(_ scope: DataCleanupScope) -> String {
        switch scope {
        case .history: "Keep recordings, settings and models"
        case .audio: "Keep saved text, settings and models"
        case .historyAndAudio: "Keep settings, models and permissions"
        case .reset: "Clear app data and setup; keep license and trial records"
        }
    }
    private var confirmationMessage: String {
        guard let selection, let preview else { return "" }
        let bytes = selection == .reset ? preview.managedBytes : preview.audioBytes
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        var parts = [selection.explanation]
        if preview.countsAvailable && selection.removesHistory { parts.append("\(preview.historyCount) saved \(preview.historyCount == 1 ? "dictation" : "dictations").") }
        if preview.countsAvailable && selection.removesAudio { parts.append("\(preview.recordingCount) \(preview.recordingCount == 1 ? "recording" : "recordings"); approximately \(size) of managed files.") }
        if !preview.countsAvailable { parts.append("History counts are unavailable. Approximately \(size) of managed files will be removed.") }
        if selection == .reset {
            parts.append("Airdraft and Debug share local data and provider keys. Preferences for Airdraft, Debug and legacy Transcribar will be reset. Permission target: \(Bundle.main.bundleIdentifier ?? "Airdraft"). Old Accessibility entries may need removal in System Settings.")
        }
        parts.append("External original media and exported copies stay. This cannot be undone.")
        return parts.joined(separator: "\n\n")
    }
    private func prepare(_ scope: DataCleanupScope) {
        selection = scope; loading = true; error = nil
        Task {
            defer { loading = false }
            do { preview = try await container.cleanupPreview(allowUnavailable: scope == .reset); confirming = true }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct DataCleanupProgress: View {
    @Environment(AppContainer.self) private var container
    private var completedDescription: String {
        let labels = ["pending": "recovery data", "history": "saved data", "models": "model unload",
                      "files": "app files", "caches": "caches", "keys": "provider keys",
                      "settings": "preferences", "permissions": "permissions"]
        return container.cleanup.completedSteps.compactMap { labels[$0] }.joined(separator: ", ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            Text(container.cleanup.finishedScope == .reset ? "App Reset Complete" : container.cleanup.pendingScope?.title ?? "Removing Data")
                .font(.system(size: 18, weight: .semibold))
            if let issue = container.dataAccessIssue {
                Text(issue).textSelection(.enabled)
            } else if container.cleanup.isRunning {
                ProgressView(container.cleanup.currentStep ?? "Preparing…").controlSize(.small)
                Text("Keep Airdraft open until this finishes.").supportingText()
            } else if container.cleanup.finishedScope == .reset {
                Text("App data and setup are cleared. Reopen Airdraft to start again. Your license and trial records are unchanged.")
                Text("macOS may retain old Accessibility entries. Remove obsolete Airdraft entries with the minus button in System Settings.").supportingText()
            } else {
                Text(container.cleanup.error ?? "An interrupted cleanup needs to finish before new work can start.")
                    .textSelection(.enabled)
                if !container.cleanup.completedSteps.isEmpty {
                    Text("Completed: " + completedDescription + ". Retry continues the same cleanup.").supportingText()
                }
            }
            HStack {
                if container.cleanup.pendingScope == .reset || container.cleanup.finishedScope == .reset {
                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(SoftButtonStyle())
                }
                Spacer()
                if !container.cleanup.isRunning {
                    Button("Quit Airdraft") { NSApp.terminate(nil) }.buttonStyle(SoftButtonStyle())
                    if let scope = container.cleanup.pendingScope {
                        Button("Retry") { Task { await container.performCleanup(scope) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(Theme.pagePadding)
        .frame(width: 510)
    }
}
