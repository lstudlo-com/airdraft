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
    @State private var showsStatus = false
    @State private var historyReadError: String?
    /// False when History failed to read or could not be opened.
    @State private var historyAvailable = true

    enum Period: String, CaseIterable, Identifiable {
        case all, week, today
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All time")
            case .week: return String(localized: "Last 7 days")
            case .today: return String(localized: "Today")
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
                     behavior: container.settings.hotkeyBehavior, triggerDelayMilliseconds: container.settings.triggerDelayMilliseconds,
                     canDictate: setupIssues == 0, content: historyContent)

            DictationRecovery()
            if let historyReadError { StorageNotice(message: historyReadError, actionTitle: "Reload History") { Task { await reload() } } }
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
        .refreshesSetupCredentials(container)
        .onChange(of: container.pipeline.lastOutcome) { _, _ in Task { await reload() } }
    }

    private var historyContent: HomeHistoryContent {
        HomeHistoryContent(loaded: hasLoadedOverview, available: historyAvailable,
                           hasDictations: !recent.isEmpty || !overview.pulses.isEmpty)
    }

    private var isFirstRun: Bool { historyContent == .firstDictation }

    // MARK: Readiness

    private var readiness: SetupReadiness { container.readiness }
    private var setupIssues: Int { readiness.issueCount }
    private var outputReady: Bool { readiness.outputReady }
    private var microphoneReady: Bool { readiness.microphoneReady }
    private var speechTone: StatusDot.Tone { readiness.speechTone }
    private var refinementTone: StatusDot.Tone { readiness.refinementTone }
    private var speechLanguageIssue: String? { readiness.speechLanguageIssue }

    private var pipelineSummary: String {
        let llm = container.settings.llm
        let speech = container.speechConfig.displayName
        guard llm.kind != .none, container.effectiveProfile.usesLLM else { return String(localized: "\(speech) · no refinement") }
        return "\(speech) → \(llm.displayName) · \(container.effectiveProfile.displayName)"
    }

    /// Exact identifiers stay available on hover for diagnosis.
    private var pipelineHelp: String {
        let llm = container.settings.llm
        let speech = String(localized: "Speech: \(container.speechConfig.engineLabel)")
        guard llm.kind != .none, container.effectiveProfile.usesLLM else { return speech }
        return speech + "\n" + String(localized: "Refinement: \(llm.engineLabel)")
    }

    private var readinessCard: some View {
        let issues = setupIssues
        let expanded = showsStatus || issues > 0 || isFirstRun
        return Card(spacing: Theme.controlSpacing) {
            Button {
                withAnimation(.snappy) { showsStatus.toggle() }
            } label: {
                HStack(spacing: Theme.controlSpacing) {
                    StatusDot(ok: issues == 0)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(readiness.summary)
                            .font(.system(size: 13, weight: .medium))
                        Text(pipelineSummary)
                            .supportingText()
                            .accessibilityIdentifier("home.pipeline-summary")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(pipelineHelp)
                    }
                    Spacer(minLength: Theme.controlSpacing)
                    if issues == 0 {
                        HStack(spacing: 6) {
                            Text(container.settings.hotkeyBehavior.instructionVerb(triggerDelayMilliseconds: container.settings.triggerDelayMilliseconds))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
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
                if isFirstRun {
                    Text(container.settings.outputDestination == .script
                         ? "Use your shortcut. Results go to your script and History."
                         : "Place your cursor, then use your shortcut to dictate.")
                        .supportingText()
                }
            }
        }
    }

    @ViewBuilder private var healthRows: some View {
        // Pipeline blockers lead: they refuse the shortcut even when setup is complete.
        if readiness.licenseBlocker != nil {
            HealthRow(ok: false, title: "License", detail: readiness.licenseDetail) {
                Button("Trial & License…") { container.showLicense() }.buttonStyle(SoftButtonStyle())
            }
            RowDivider()
        }
        if readiness.recordingsBlocked {
            HealthRow(ok: false, title: "Waiting recordings", detail: readiness.recordingsDetail) {}
            RowDivider()
        }
        HealthRow(ok: container.hotkeys.isActive, title: "Shortcut", detail: container.hotkeys.statusText) {
            if container.hotkeys.needsAccessibility {
                Button("Grant Accessibility…") { container.openAccessibilitySettings() }.buttonStyle(SoftButtonStyle())
            } else {
                Button("Change") { container.navigation.page = .configuration }.buttonStyle(SoftButtonStyle())
            }
        }
        RowDivider()
        if container.settings.outputDestination == .script {
            HealthRow(ok: outputReady, title: "Script output", detail: readiness.scriptDetail) {
                Button("Configure") { container.navigation.page = .configuration }.buttonStyle(SoftButtonStyle())
            }
        } else {
            HealthRow(
                ok: container.permissions.accessibilityGranted,
                title: "Accessibility",
                detail: container.permissions.accessibilityGranted ? String(localized: "Granted") : String(localized: "Allow text insertion in System Settings")
            ) {
                if !container.permissions.accessibilityGranted {
                    AccessibilityPermissionActions()
                }
            }
        }
        RowDivider()
        HealthRow(ok: microphoneReady, title: "Microphone", detail: readiness.microphoneDetail) {
            if !microphoneReady {
                Button(container.permissions.microphone == .notDetermined ? "Allow Microphone" : "Microphone Settings") {
                    if container.permissions.microphone == .notDetermined {
                        Task { await container.permissions.requestMicrophone() }
                    } else { container.navigation.page = .configuration }
                }.buttonStyle(SoftButtonStyle())
            }
        }
        RowDivider()
        HealthRow(tone: speechTone, title: "Speech", detail: readiness.speechDetail) {
            if speechTone == .attention {
                if container.effectiveProfile.speechModel?.unavailableReason != nil {
                    Button("Profiles") { container.navigation.page = .profiles }
                        .buttonStyle(SoftButtonStyle())
                } else if speechLanguageIssue != nil {
                    Button("Language Settings") { container.navigation.page = .models }
                        .buttonStyle(SoftButtonStyle())
                        .accessibilityIdentifier("home.speech-language-action")
                } else if container.speechConfig.kind.isLocal, readiness.speechInstalled {
                    Button("Load Model") { container.models.loadSpeechModel() }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(container.pipeline.isBusy || container.engineStatus.state(for: container.speechConfig.engineID) == .loading)
                } else {
                    Button(container.speechConfig.kind.isLocal ? "Get Model" : "API Key Settings") {
                        container.navigation.page = .models
                    }.buttonStyle(SoftButtonStyle())
                }
            } else if readiness.speechLoadsOnDemand {
                // Optional: dictation loads it anyway; this only saves the first wait.
                Button("Load Model") { container.models.loadSpeechModel() }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(container.pipeline.isBusy)
                    .help("Load now instead of when you start dictating")
            }
        }
        RowDivider()
        HealthRow(tone: refinementTone, title: "Refinement", detail: readiness.refinementDetail) {
            if refinementTone == .attention {
                Button(readiness.refinementNeedsKey ? "Add API Key" : "Models") { container.navigation.page = .models }
                    .buttonStyle(SoftButtonStyle())
            } else {
                Button("Profiles") { container.navigation.page = .profiles }.buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        Card(spacing: Theme.controlSpacing) {
            ForEach(overview.topApps, id: \.name) { share in
                AppShareRow(share: share, fraction: overview.stats.words > 0 ? Double(share.words) / Double(overview.stats.words) : 0)
            }
            RowDivider()
            HStack(alignment: .top, spacing: Theme.controlSpacing) {
                SummaryFact(value: overview.streakDays == 1 ? String(localized: "1 day") : String(localized: "\(overview.streakDays.formatted()) days"), label: "Streak")
                SummaryFact(value: overview.stats.dictations.formatted(), label: "Dictations")
                SummaryFact(value: overview.activeDays.formatted(), label: "Active days")
                SummaryFact(value: String(localized: "\(overview.longestWords.formatted()) words"), label: "Longest dictation")
            }
        }
    }

    // MARK: Recent

    private var recentCard: some View {
        Card(spacing: Theme.controlSpacing) {
            if !historyAvailable {
                // An unreadable History is not an empty one.
                EmptyNote("History could not be read.")
            } else if recent.isEmpty {
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
            // `HISTORY_ERROR=<message>` shows an unreadable History.
            if let message = RenderMode.value("HISTORY_ERROR") {
                historyReadError = String(localized: "History could not be read.") + " " + message
                historyAvailable = false
                hasLoadedOverview = true
                return
            }
            let empty = RenderMode.value("EMPTY_HISTORY") != nil
            overview = empty ? .empty : (try? container.history?.overview(days: period.days, calendarDay: period == .today)) ?? .empty
            recent = empty ? [] : (try? container.history?.recent(limit: 3)) ?? []
            hasLoadedOverview = true
            return
        }
        guard let history = container.history else {
            historyAvailable = false
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
            historyAvailable = true
        case .failure(let error):
            historyReadError = String(localized: "History could not be read.") + " " + error.localizedDescription
            historyAvailable = false
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
    let title: LocalizedStringResource
    let detail: String
    @ViewBuilder var trailing: Trailing

    init(ok: Bool, title: LocalizedStringResource, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(tone: ok ? .ok : .attention, title: title, detail: detail, trailing: trailing)
    }

    init(tone: StatusDot.Tone, title: LocalizedStringResource, detail: String, @ViewBuilder trailing: () -> Trailing) {
        self.tone = tone
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.controlSpacing) {
            StatusDot(tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).supportingText()
            }
            Spacer(minLength: Theme.controlSpacing)
            trailing
        }
        .accessibilityElement(children: .contain)
        // Identifiers stay English so fixtures work in every language.
        .accessibilityIdentifier("readiness.\(title.key.lowercased())")
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
    let label: LocalizedStringResource
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
                // One run of text, so every separator has the same spacing in each language.
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.controlSpacing)
            Text(timeLabel)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// App, profile and processing time, joined as in History.
    private var metadata: String {
        var parts = record.appName.map { [$0] } ?? []
        parts.append(RefinementProfile.displayName(forSavedName: record.mode))
        parts.append(DurationLabel.milliseconds(record.asrMs + record.llmMs))
        return parts.joined(separator: " · ")
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
