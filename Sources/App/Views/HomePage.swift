import AirdraftCore
import AppKit
import AVFoundation
import SwiftUI

struct HomePage: View {
    @Environment(AppContainer.self) private var container
    @State private var period: Period = .all
    @State private var overview: HistoryStore.Overview = .empty
    @State private var hasLoadedOverview = false
    @State private var recent: [DictationRecord] = []
    @State private var speechKeyPresent = false
    @State private var refinementKeyPresent = false
    @State private var showsStatus = false
    @State private var historyReadError: String?

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
        PageScaffold(.home) {
            // The hero is Home's identity and always leads; a setup problem still
            // opens the readiness card directly beneath it.
            HomeHero(overview: overview, periodTitle: period.title, hotkey: container.settings.hotkey,
                     behavior: container.settings.hotkeyBehavior, isReady: hasLoadedOverview, canDictate: setupIssues == 0)

            DictationRecovery()
            if let historyReadError { StorageNotice(message: historyReadError) { Task { await reload() } } }
            readinessCard

            if !overview.topApps.isEmpty {
                PageSection("Summary") { summaryCard }
            }

            PageSection("Recent") {
                Button("View All") { container.navigation.page = .history }
                    .buttonStyle(.link)
            } content: {
                recentCard
            }
        } accessory: {
            PageFilter(title: "Statistics period", selection: $period,
                       options: Period.allCases.map { ($0, $0.title) })
        }
        .task(id: period) { await reload() }
        .task(id: container.settings.asr.keyRef) { await refreshSpeechKey() }
        .task(id: container.settings.llm.keyRef) { await refreshRefinementKey() }
        .onReceive(NotificationCenter.default.publisher(for: Keychain.didChange).receive(on: DispatchQueue.main)) { _ in
            Task {
                await refreshSpeechKey()
                await refreshRefinementKey()
            }
        }
        .onChange(of: container.pipeline.lastOutcome) { _, _ in Task { await reload() } }
    }

    // MARK: Readiness

    private var setupIssues: Int {
        [container.hotkeys.isActive, container.permissions.accessibilityGranted, microphoneReady, speechReady, refinementTone != .attention]
            .filter { !$0 }.count
    }

    private var pipelineSummary: String {
        let llm = container.settings.llm
        let speech = container.settings.asr.engineLabel
        guard llm.kind != .none else { return "\(speech) · no refinement" }
        return "\(speech) → \(llm.engineLabel) · \(container.profiles.activeProfile.name)"
    }

    private var readinessCard: some View {
        let issues = setupIssues
        let expanded = showsStatus || issues > 0 || (hasLoadedOverview && overview.stats.dictations == 0)
        return Card(spacing: Theme.controlSpacing) {
            Button {
                withAnimation(.snappy) { showsStatus.toggle() }
            } label: {
                HStack(spacing: Theme.controlSpacing) {
                    StatusDot(ok: issues == 0)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(issues == 0 ? "Ready to dictate" : issues == 1 ? "1 setup step needs attention" : "\(issues) setup steps need attention")
                            .font(.system(size: 13, weight: .medium))
                        Text(pipelineSummary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: Theme.controlSpacing)
                    if issues == 0 {
                        HStack(spacing: 6) {
                            Text(container.settings.hotkeyBehavior.instructionVerb).font(.system(size: 12)).foregroundStyle(.secondary)
                            KeyCaps(hotkey: container.settings.hotkey)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(issues == 0)
            .accessibilityHint(issues == 0 ? (expanded ? "Hide setup details" : "Show setup details") : "")

            if expanded {
                RowDivider()
                healthRows
                if hasLoadedOverview && overview.stats.dictations == 0 {
                    Text("After setup, place the cursor in a text field and use your shortcut to dictate a short sentence. Your first result will appear in History.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var healthRows: some View {
        HealthRow(ok: container.hotkeys.isActive, title: "Shortcut", detail: container.hotkeys.statusText) {
            if container.hotkeys.needsAccessibility {
                Button("Grant Accessibility…") { container.openAccessibilitySettings() }.buttonStyle(SoftButtonStyle())
            } else {
                Button("Change") { container.navigation.page = .configuration }.buttonStyle(SoftButtonStyle())
            }
        }
        HealthRow(
            ok: container.permissions.accessibilityGranted,
            title: "Accessibility",
            detail: container.permissions.accessibilityGranted ? "Granted" : "macOS has not granted this copy access to insert text"
        ) {
            if !container.permissions.accessibilityGranted {
                AccessibilityPermissionActions()
            }
        }
        HealthRow(ok: microphoneReady, title: "Microphone", detail: microphoneDetail) {
            if !microphoneReady {
                Button(container.permissions.microphone == .notDetermined ? "Allow Microphone" : "Microphone Settings") {
                    if container.permissions.microphone == .notDetermined {
                        Task { await container.permissions.requestMicrophone() }
                    } else { container.navigation.page = .configuration }
                }.buttonStyle(SoftButtonStyle())
            }
        }
        HealthRow(ok: speechReady, title: "Speech", detail: speechDetail) {
            if !speechReady {
                if container.settings.asr.kind.isLocal, LocalModels.isInstalled(container.settings.asr) {
                    Button("Load Model") { container.models.loadSpeechModel() }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(container.pipeline.isBusy || container.engineStatus.state(for: container.settings.asr.engineID) == .loading)
                } else {
                    Button(container.settings.asr.kind.isLocal ? "Get Model" : "API Key Settings") {
                        container.navigation.page = .models
                    }.buttonStyle(SoftButtonStyle())
                }
            }
        }
        HealthRow(tone: refinementTone, title: "Refinement", detail: refinementDetail) {
            if refinementTone == .attention {
                Button(refinementNeedsKey ? "Add API Key" : "Models") { container.navigation.page = .models }
                    .buttonStyle(SoftButtonStyle())
            } else {
                Button("Profiles") { container.navigation.page = .profiles }.buttonStyle(SoftButtonStyle())
            }
        }
    }

    private var refinementNeedsKey: Bool {
        container.profiles.activeProfile.usesLLM && container.settings.llm.kind.requiresKey && !refinementKeyPresent
    }

    /// Off is a valid choice, not a problem; a missing key, CLI or server is.
    private var refinementTone: StatusDot.Tone {
        let llm = container.settings.llm
        if llm.kind == .none || !container.profiles.activeProfile.usesLLM { return .inactive }
        if refinementNeedsKey || (llm.kind.isCLI && llm.cliExecutable == nil) { return .attention }
        switch container.models.llmStatus.state {
        case .unreachable, .failed: return .attention
        case .loading, .unknown: return .busy
        default: return .ok
        }
    }

    private var refinementDetail: String {
        let llm = container.settings.llm
        guard llm.kind != .none, container.profiles.activeProfile.usesLLM else { return "Off · the transcript is inserted as spoken" }
        let state = refinementNeedsKey ? "API key needed" : container.models.llmStatus.label
        return "\(llm.engineLabel) · \(state) · profile \(container.profiles.activeProfile.name)"
    }

    private func refreshRefinementKey() async {
        guard !RenderMode.isActive else { return }
        let account = container.settings.llm.keyRef
        let present = await Task.detached { Keychain.presence(account) == .saved }.value
        guard account == container.settings.llm.keyRef, !Task.isCancelled else { return }
        refinementKeyPresent = present
    }

    private var microphoneReady: Bool {
        guard container.permissions.microphone == .authorized,
              let device = container.microphones.selected(container.settings.microphone) else { return false }
        let channel = container.settings.microphone.channelIndex ?? 0
        return channel >= 0 && channel < device.inputChannelCount
    }

    private var microphoneDetail: String {
        if container.permissions.microphone != .authorized { return "Microphone permission needed" }
        guard let device = container.microphones.selected(container.settings.microphone) else { return "Selected microphone is unavailable" }
        return microphoneReady ? device.name : "Selected input channel is unavailable"
    }

    private var speechDetail: String {
        let asr = container.settings.asr
        if !asr.kind.isLocal { return asr.engineLabel + ((asr.kind.preset != nil) && !speechKeyPresent ? " · API key needed or locked" : " · cloud connection checked when used") }
        if !LocalModels.isInstalled(asr) { return asr.engineLabel + " · model not installed" }
        return asr.engineLabel + " · " + container.engineStatus.state(for: asr.engineID).label
    }

    private var speechReady: Bool {
        let asr = container.settings.asr
        if !asr.kind.isLocal { return !(asr.kind.preset != nil) || speechKeyPresent }
        return LocalModels.isInstalled(asr) && container.engineStatus.state(for: asr.engineID) == .ready
    }

    private func refreshSpeechKey() async {
        guard !RenderMode.isActive else { return }
        let account = container.settings.asr.keyRef
        let present = await Task.detached { Keychain.presence(account) == .saved }.value
        guard account == container.settings.asr.keyRef, !Task.isCancelled else { return }
        speechKeyPresent = present
    }

    // MARK: Summary

    private var summaryCard: some View {
        Card(spacing: Theme.controlSpacing) {
            ForEach(overview.topApps, id: \.name) { share in
                AppShareRow(share: share, fraction: overview.stats.words > 0 ? Double(share.words) / Double(overview.stats.words) : 0)
            }
            RowDivider()
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                SummaryFact(value: "\(overview.streakDays.formatted()) \(overview.streakDays == 1 ? "day" : "days")", label: "Streak")
                SummaryFact(value: overview.stats.dictations.formatted(), label: "Dictations")
                SummaryFact(value: overview.activeDays.formatted(), label: "Active days")
                SummaryFact(value: "\(overview.longestWords.formatted()) words", label: "Longest dictation")
            }
        }
    }

    // MARK: Recent

    private var recentCard: some View {
        Card(spacing: Theme.controlSpacing) {
            if recent.isEmpty {
                EmptyNote("No dictations yet.")
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { RowDivider() }
                    RecentRow(record: record)
                }
            }
        }
    }

    private func reload() async {
        // Renders can show the first-run state without touching the user's history.
        if RenderMode.isActive {
            let empty = RenderMode.value("EMPTY_HISTORY") != nil
            overview = empty ? .empty : (try? container.history?.overview(days: period.days, calendarDay: period == .today)) ?? .empty
            recent = empty ? [] : (try? container.history?.recent(limit: 3)) ?? []
            hasLoadedOverview = true
            return
        }
        guard let history = container.history else {
            hasLoadedOverview = true
            return
        }
        let days = period.days
        let calendarDay = period == .today
        // Off the main actor: the overview reads every row.
        let result = await Task.detached {
            Result { (try history.overview(days: days, calendarDay: calendarDay), try history.recent(limit: 3)) }
        }.value
        guard !Task.isCancelled else { return }
        let next: HistoryStore.Overview
        let latest: [DictationRecord]
        switch result {
        case .success(let values):
            (next, latest) = values
            historyReadError = nil
        case .failure(let error):
            historyReadError = "History could not be read. " + error.localizedDescription
            hasLoadedOverview = true
            return
        }
        if hasLoadedOverview {
            recent = latest
            withAnimation(.snappy(duration: 0.6)) { overview = next }
        } else {
            // Commit real bars before their entrance. Animating the replacement
            // of the five placeholder bars raced the hero's startup animation.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                recent = latest
                overview = next
                hasLoadedOverview = true
            }
        }
    }
}

struct HealthRow<Trailing: View>: View {
    let tone: StatusDot.Tone
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    init(ok: Bool, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(tone: ok ? .ok : .attention, title: title, detail: detail, trailing: trailing)
    }

    init(tone: StatusDot.Tone, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.tone = tone
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.controlSpacing) {
            StatusDot(tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.controlSpacing)
            trailing
        }
    }
}

/// An app's share of the words dictated in the period.
struct AppShareRow: View {
    let share: HistoryStore.Overview.AppShare
    let fraction: Double

    var body: some View {
        HStack(spacing: Theme.controlSpacing) {
            AppIcon(bundleId: share.bundleId, size: 20)
            Text(share.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(width: 116, alignment: .leading)
            NeumorphicUsageTrack(fraction: fraction)
            Text("\(share.words.formatted()) words")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(share.name), \(share.words) words, \(Int((fraction * 100).rounded())) percent")
    }
}

struct SummaryFact: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct RecentRow: View {
    let record: DictationRecord

    var body: some View {
        HStack(alignment: .top, spacing: Theme.controlSpacing) {
            AppIcon(bundleId: record.appBundleId, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.finalText).font(.system(size: 13)).lineLimit(2)
                HStack(spacing: 6) {
                    if let app = record.appName { Text(app) }
                    Text("· \(record.mode)")
                    Text("· \(record.asrMs + record.llmMs) ms")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.controlSpacing)
            Text(timeLabel)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var timeLabel: String {
        Calendar.current.isDateInToday(record.createdAt)
            ? record.createdAt.formatted(date: .omitted, time: .shortened)
            : record.createdAt.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The icon of the app a dictation went into, or a neutral tile when it is unknown.
struct AppIcon: View {
    let bundleId: String?
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image = Self.icon(for: bundleId) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Image(systemName: "text.cursor")
                            .font(.system(size: size * 0.45, weight: .medium))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor private static func icon(for bundleId: String?) -> NSImage? {
        guard let bundleId else { return nil }
        if let cached = cache[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleId] = image
        return image
    }
}

#if DEBUG
#Preview("Home") {
    HomePage()
        .environment(PreviewData.container)
        .frame(width: 760, height: 1000)
}
#endif
