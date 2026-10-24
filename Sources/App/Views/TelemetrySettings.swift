import AirdraftCore
import AppKit
import SwiftUI

/// The public description of what official builds may send.
enum TelemetryPrivacy {
    static let url = URL(string: "https://airdraft.app/privacy/#app-telemetry")!

    static func openDetails() {
        guard !RenderMode.isActive else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The one-time question, on Home and the Ready step while undecided. Both
/// answers have equal weight, and nothing is sent before one is chosen.
struct TelemetryConsentCard: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background { NeumorphicSurface(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), inset: true, depth: 1.5) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Help improve Airdraft")
                        .appFont(.body, weight: .medium)
                        .accessibilityAddTraits(.isHeader)
                    Text("Share anonymous usage counts and crash reports with the developer. Nothing is sent until you choose.")
                        .supportingText()
                }
                Spacer(minLength: 0)
            }
            RowDivider()
            HStack(alignment: .top, spacing: 16) {
                list("Shared", symbol: "checkmark", items: [
                    "Which features and engine types you use",
                    "Durations and timings, in ranges",
                    "Crash reports",
                    "App version, macOS version and language",
                ])
                list("Never shared", symbol: "xmark", items: [
                    "Your words, transcripts, audio or vocabulary",
                    "App names, window titles, web addresses or files",
                    "API keys, server addresses or custom model names",
                ])
            }
            RowDivider()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("You can change this anytime in Settings.")
                    .supportingText()
                Button("Privacy Details") { TelemetryPrivacy.openDetails() }
                    .buttonStyle(.link)
                    .appFont(.supporting)
                    .accessibilityHint(Text("Opens the Airdraft privacy page"))
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.controlSpacing) {
                Spacer(minLength: 0)
                Button("Don’t Share") { container.telemetry.choose(.denied) }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("telemetry.deny")
                Button("Share Anonymous Usage Data") { container.telemetry.choose(.granted) }
                    .buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("telemetry.grant")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Anonymous usage data"))
    }

    private func list(_ title: LocalizedStringResource, symbol: String, items: [LocalizedStringResource]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(items[index])
                        .appFont(.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Settings switch, in Behavior beside Read app context. Shown only where
/// telemetry can be offered; it brings its own leading divider.
struct TelemetrySettingRow: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let telemetry = container.telemetry
        if telemetry.showsChoice {
            RowDivider()
            SettingRow(title: "Share anonymous usage data and crash reports",
                       subtitle: "Counts and timings only, never your words or audio") {
                HStack(spacing: Theme.controlSpacing) {
                    Button("Privacy Details") { TelemetryPrivacy.openDetails() }
                        .buttonStyle(.link)
                        .appFont(.supporting)
                        .accessibilityHint(Text("Opens the Airdraft privacy page"))
                    Toggle("Share anonymous usage data and crash reports", isOn: Binding(
                        get: { telemetry.consent == .granted },
                        set: { telemetry.choose($0 ? .granted : .denied) }
                    ))
                    .labelsHidden().toggleStyle(.softSwitch)
                    .accessibilityIdentifier("settings.telemetry")
                }
            }
        }
    }
}
