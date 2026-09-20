import SwiftUI

struct UpdateSettings: View {
    let updates: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Updates")
            Card(padding: 16) {
                SettingRow(title: "Airdraft", subtitle: updates.versionLabel) {
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(!updates.canCheckForUpdates)
                }
                RowDivider()
                SettingRow(title: "Check automatically", subtitle: "Check for new versions once a day") {
                    Toggle("Check automatically", isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticChecks($0) }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(!updates.isStarted)
                }
                RowDivider()
                SettingRow(title: "Download updates automatically", subtitle: "Install downloaded updates when you quit Airdraft") {
                    Toggle("Download updates automatically", isOn: Binding(
                        get: { updates.automaticallyDownloadsUpdates },
                        set: { updates.setAutomaticDownloads($0) }
                    ))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(!updates.isStarted || !updates.automaticallyChecksForUpdates)
                }
                if let error = updates.startupError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                } else if let checked = updates.lastCheckedAt {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
