import AirdraftCore
import SwiftUI

struct HomePage: View {
    @Environment(AppContainer.self) private var container
    @State private var period: Period = .all
    @State private var stats: HistoryStore.Stats?
    @State private var recent: [DictationRecord] = []

    enum Period: String, CaseIterable, Identifiable {
        case all, week, today
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All time"
            case .week: return "Last 7 days"
            case .today: return "Today"
            }
        }
        var days: Int? {
            switch self {
            case .all: return nil
            case .week: return 7
            case .today: return 1
            }
        }
    }

    var body: some View {
        PageScaffold {
            Menu {
                ForEach(Period.allCases) { p in
                    Button(p.title) { period = p }
                }
            } label: {
                Text(period.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Card(padding: 14) {
                HStack(alignment: .top, spacing: 0) {
                    StatCell(value: "\(stats?.wordsPerMinute ?? 0) WPM", label: "Average speed")
                    StatCell(value: (stats?.words ?? 0).formatted(), label: "Words")
                    StatCell(value: "\(stats?.apps ?? 0)", label: "Apps used")
                    StatCell(value: minutesLabel(stats?.minutesSaved ?? 0), label: "Saved \(period.title.lowercased())")
                }
            }

            healthCard

            SectionTitle("Get started")
            Card(padding: 0) {
                ActionRow(symbol: "record.circle", title: "Start recording", subtitle: "Hold the shortcut, speak, release.") {
                    KeyCaps(hotkey: container.settings.hotkey)
                } action: { container.pipeline.toggle() }
                RowDivider().padding(.leading, 46)
                ActionRow(symbol: "keyboard", title: "Shortcut", subtitle: "Change the key that starts dictation.") {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                } action: { container.navigation.page = .configuration }
                RowDivider().padding(.leading, 46)
                ActionRow(symbol: "sparkles", title: "Profiles", subtitle: "How the LLM rewrites what you say.") {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                } action: { container.navigation.page = .profiles }
                RowDivider().padding(.leading, 46)
                ActionRow(symbol: "book.closed", title: "Vocabulary", subtitle: "Names, products, jargon.") {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                } action: { container.navigation.page = .vocabulary }
            }

            SectionTitle("Recent") {
                Button("View all") { container.navigation.page = .history }
                    .buttonStyle(.link)
            }
            Card(padding: 0) {
                if recent.isEmpty {
                    Text("No dictations yet.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { RowDivider().padding(.leading, 16) }
                        HStack(alignment: .top, spacing: 12) {
                            Text(record.createdAt, style: .time)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.finalText).font(.system(size: 13)).lineLimit(2)
                                HStack(spacing: 6) {
                                    if let app = record.appName { Text(app) }
                                    Text("· \(record.mode)")
                                    Text("· \(record.asrMs + record.llmMs) ms")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .task(id: period) { reload() }
        .onChange(of: container.pipeline.lastOutcome) { _, _ in reload() }
    }

    private var healthCard: some View {
        Card(padding: 0) {
            HealthRow(
                ok: container.hotkeys.isActive,
                title: "Shortcut",
                detail: container.hotkeys.statusText
            ) {
                if container.hotkeys.needsAccessibility {
                    Button("Grant Accessibility…") { container.openAccessibilitySettings() }.buttonStyle(SoftButtonStyle())
                }
            }
            RowDivider().padding(.leading, 32)
            HealthRow(
                ok: AppContextReader.isAccessibilityTrusted,
                title: "Accessibility",
                detail: AppContextReader.isAccessibilityTrusted ? "Granted" : "Not granted, text cannot be inserted yet"
            ) {
                if !AppContextReader.isAccessibilityTrusted {
                    Button("Grant…") { AppContextReader.requestAccessibility(); container.openAccessibilitySettings() }.buttonStyle(SoftButtonStyle())
                }
            }
            RowDivider().padding(.leading, 32)
            HealthRow(
                ok: speechReady,
                title: "Speech recognition",
                detail: container.settings.asr.engineLabel + (speechReady ? " · " + speechLoadLabel : " · model not installed")
            ) {
                if !speechReady {
                    Button("Get model…") { container.navigation.page = .models }.buttonStyle(SoftButtonStyle())
                }
            }
            RowDivider().padding(.leading, 32)
            HealthRow(
                ok: container.settings.llm.kind != .none,
                title: "Refinement",
                detail: container.settings.llm.engineLabel + " · " + container.models.llmStatus.label + " · profile \(container.profiles.activeProfile.name)"
            ) { EmptyView() }
        }
    }

    private var speechLoadLabel: String {
        guard container.settings.asr.kind.isLocal else { return "cloud" }
        if container.settings.asr.kind == .apple { return "built in" }
        return container.engineStatus.state(for: container.settings.asr.engineID).label.lowercased()
    }

    private var speechReady: Bool {
        let asr = container.settings.asr
        if asr.kind == .elevenLabs { return !(Keychain.get(EndpointPreset.elevenLabsKeyRef) ?? "").isEmpty }
        return LocalModels.isInstalled(asr)
    }

    private func reload() {
        stats = try? container.history?.stats(days: period.days)
        recent = (try? container.history?.recent(limit: 3)) ?? []
    }

    private func minutesLabel(_ minutes: Int) -> String {
        if minutes >= 60 { return String(format: "%.1f hours", Double(minutes) / 60) }
        return "\(minutes) minutes"
    }
}

struct StatCell: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

struct HealthRow<Trailing: View>: View {
    let ok: Bool
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
