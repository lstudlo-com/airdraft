import AirdraftCore
import AppKit
import SwiftUI

struct AutomationSettings: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.revealSearchSettings) private var revealSearchSettings
    @State private var selectionError: String?

    var body: some View {
        @Bindable var settings = container.settings
        PageSection("Output and automation") {
            SettingsCard {
                SettingRow(title: "Final text") {
                    SoftPicker("Final text", selection: $settings.outputDestination, width: 180) {
                        ForEach(TextOutputDestination.allCases) { Text($0.title).tag($0) }
                    }
                }
                if settings.outputDestination == .script || revealSearchSettings {
                    RowDivider()
                    SettingRow(title: "Executable script",
                               subtitle: settings.outputDestination != .script ? "Choose Send to script in Final text to send text via stdin" : selectionError ?? ScriptDelivery.unavailableReason(path: settings.outputScriptPath)
                                ?? "Final text via stdin · one run · 10 s limit") {
                        VStack(alignment: .trailing, spacing: 6) {
                            if !settings.outputScriptPath.isEmpty {
                                Text(URL(fileURLWithPath: settings.outputScriptPath).lastPathComponent)
                                    .font(.caption).lineLimit(1).truncationMode(.middle)
                                    .help(settings.outputScriptPath)
                            }
                            Button("Choose Script…", action: chooseScript).buttonStyle(SoftButtonStyle())
                                .disabled(settings.outputDestination != .script)
                        }
                    }
                }
                RowDivider()
                SettingRow(title: "Shortcuts", subtitle: "Start, stop or cancel from Apple Shortcuts") {
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }.buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Executable Script"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let reason = ScriptDelivery.unavailableReason(path: url.path) {
                selectionError = reason
                return
            }
            container.settings.outputScriptPath = url.path
            selectionError = nil
        }
    }
}
