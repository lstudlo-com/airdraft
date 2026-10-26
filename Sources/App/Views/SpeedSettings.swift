import AirdraftCore
import AppKit
import SwiftUI

/// Profile and Edit shortcuts (AD-104), inside the Keyboard shortcuts card.
struct ExtraShortcutRows: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.revealSearchSettings) private var revealSearchSettings

    private var settings: AppSettings { container.settings }

    var body: some View {
        ForEach(0..<ProfileHotkey.maximumCount, id: \.self) { slot in
            RowDivider()
            profileRow(slot: slot)
        }
        RowDivider()
        SettingRow(title: "Edit selection",
                   detail: container.hotkeys.extraIssues[.edit]
                    ?? String(localized: "Select text, hold and say what to change. Sends the selection to your refinement provider.")) {
            HotkeyRecorderView(shortcut: Binding(get: { settings.editHotkey }, set: { settings.editHotkey = $0 }),
                               accessibilityName: String(localized: "Edit selection shortcut"))
        }
    }

    private func profileRow(slot: Int) -> some View {
        let entry = slot < settings.profileHotkeys.count ? settings.profileHotkeys[slot] : nil
        let missing = entry.map { item in !container.profiles.profiles.contains { $0.id == item.profileID } } ?? false
        let issue = entry.flatMap { container.hotkeys.extraIssues[.profile($0.profileID)] }
        let detail = missing ? String(localized: "Its profile was deleted. Choose another.")
            : issue ?? (slot == 0 ? String(localized: "Dictates with this profile in any app") : nil)
        return SettingRow(title: slot == 0 ? "Profile shortcut 1" : "Profile shortcut 2", detail: detail) {
            HStack(spacing: 8) {
                SoftPicker(slot == 0 ? "Profile for shortcut 1" : "Profile for shortcut 2", selection: Binding(
                    get: { entry?.profileID },
                    set: { setProfile($0, slot: slot) }
                ), width: 150) {
                    Text("None").tag(UUID?.none)
                    ForEach(container.profiles.profiles) { profile in
                        Text(profile.name.isEmpty ? String(localized: "Untitled profile") : profile.displayName)
                            .tag(Optional(profile.id))
                    }
                }
                if let entry {
                    HotkeyRecorderView(shortcut: Binding(get: { entry.hotkey }, set: { setHotkey($0, slot: slot) }),
                                       accessibilityName: String(localized: "Shortcut for \(profileName(entry.profileID))"))
                }
            }
        }
    }

    private func profileName(_ id: UUID) -> String {
        container.profiles.profiles.first { $0.id == id }?.displayName ?? String(localized: "Deleted profile")
    }

    private func setProfile(_ id: UUID?, slot: Int) {
        var entries = settings.profileHotkeys
        guard let id else {
            if slot < entries.count { entries.remove(at: slot) }
            settings.profileHotkeys = entries
            return
        }
        if slot < entries.count { entries[slot].profileID = id } else { entries.append(ProfileHotkey(profileID: id)) }
        settings.profileHotkeys = entries
    }

    private func setHotkey(_ hotkey: Hotkey?, slot: Int) {
        guard slot < settings.profileHotkeys.count else { return }
        settings.profileHotkeys[slot].hotkey = hotkey
    }
}

/// Send after pasting (AD-104): Shift lock, flag handling and local measurements.
struct SendSettings: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.revealSearchSettings) private var revealSearchSettings

    var body: some View {
        @Bindable var settings = container.settings
        PageSection("Send after pasting") {
            SettingsCard {
                SettingRow(title: "Shift to send",
                           subtitle: "Press Shift while recording to press Return once the text is confirmed") {
                    Toggle("Shift to send", isOn: $settings.sendWithShift).labelsHidden().toggleStyle(.softSwitch)
                        .accessibilityIdentifier("settings.sendWithShift")
                }
                RowDivider()
                SettingRow(title: "When words need a look",
                           subtitle: "Numbers, negations and names the cleanup added, and code-like words") {
                    SoftPicker("When words need a look", selection: $settings.flagHandling,
                               width: SoftPickerWidth.fitting(FlagHandling.allCases.map(\.title), minimum: 180)) {
                        ForEach(FlagHandling.allCases) { Text($0.title).tag($0) }
                    }
                }
                RowDivider()
                SettingRow(title: "Code-like words hold sending",
                           subtitle: "File names, paths and identifiers that aren't in Vocabulary") {
                    Toggle("Code-like words hold sending", isOn: $settings.identifiersHoldSend)
                        .labelsHidden().toggleStyle(.softSwitch)
                }
                RowDivider()
                SettingRow(title: "Show flagged words after every dictation",
                           subtitle: "Also when nothing is sent") {
                    Toggle("Show flagged words after every dictation", isOn: $settings.showsFlagsAfterDictation)
                        .labelsHidden().toggleStyle(.softSwitch)
                }
                if settings.sendWithShift || revealSearchSettings {
                    RowDivider()
                    SettingRow(title: "Send in terminals that can't confirm",
                               detail: settings.sendWithShift ? String(localized: "Warp, Zed, Ghostty and similar apps: Shift still required")
                                : String(localized: "Enable Shift to send")) {
                        Toggle("Send in terminals that can't confirm", isOn: $settings.sendsWhenUnconfirmed)
                            .labelsHidden().toggleStyle(.softSwitch)
                            .disabled(!settings.sendWithShift)
                    }
                }
                RowDivider()
                SpeedMeasurementRows()
            }
        }
    }
}

extension FlagHandling {
    var title: String {
        switch self {
        case .showAndWait: String(localized: "Show Them and Wait")
        case .pasteOnly: String(localized: "Paste Without Sending")
        }
    }
}

/// Local counts behind the speed gates (AD-104). Never sent anywhere.
private struct SpeedMeasurementRows: View {
    @Environment(AppContainer.self) private var container
    @State private var statistics: SpeedStatistics?
    @State private var metrics: SpeedMetricsSnapshot?

    var body: some View {
        SettingRow(title: "Measurements", detail: summary) {
            Button("Refresh") { Task { await load() } }
                .buttonStyle(SoftButtonStyle())
                .accessibilityLabel("Refresh measurements")
        }
        .task { await load() }
    }

    private var summary: String {
        guard let statistics else { return String(localized: "Counting…") }
        var parts: [String] = []
        if statistics.checked > 0 {
            let percent = Int((Double(statistics.flagged) / Double(statistics.checked) * 100).rounded())
            parts.append(String(localized: "Flagged: \(percent)% of \(statistics.checked) dictations"))
        }
        if statistics.sendRequested > 0 {
            parts.append(String(localized: "Sent: \(statistics.sent) of \(statistics.sendRequested) requested"))
        }
        if let metrics {
            let ai = metrics.deliveries(matching: SpeedMetricsSnapshot.aiDestinationPrefixes)
            if ai.total > 0 {
                parts.append(String(localized: "AI apps confirmed: \(ai.delivered) of \(ai.total)"))
            }
            if let ignored = metrics.ignoredPerHundred {
                parts.append(String(localized: "Presses while busy: \(Int(ignored.rounded())) per 100"))
            }
        }
        return parts.isEmpty ? String(localized: "No dictations measured yet. Counts stay on this Mac.")
            : parts.joined(separator: " · ")
    }

    private func load() async {
        let history = container.history
        let store = container.pipeline.metrics
        statistics = await Task.detached(priority: .utility) { (try? history?.speedStatistics()) ?? SpeedStatistics() }.value
        metrics = await store?.snapshot()
    }
}

/// A profile's destination and automatic send (AD-104).
struct ProfileOutputSettings: View {
    @Environment(AppContainer.self) private var container
    @Binding var output: ProfileOutput?
    @Binding var sendsAutomatically: Bool

    private enum Choice: Hashable { case appDefault, cursor, copy, file }

    private var choice: Choice {
        switch output?.kind {
        case nil: .appDefault
        case .cursor: .cursor
        case .copy: .copy
        case .file: .file
        }
    }

    private var deliversToCursor: Bool {
        switch output?.kind {
        case nil: container.settings.outputDestination == .cursor
        case .cursor: true
        case .copy, .file: false
        }
    }

    var body: some View {
        PageSection("Output") {
            SettingsCard {
                SettingRow(title: "Send to", detail: choice == .appDefault ? String(localized: "Follows Output and automation in Settings") : nil) {
                    SoftPicker("Send to", selection: Binding(get: { choice }, set: select), width: 200) {
                        Text("Use App Default").tag(Choice.appDefault)
                        Text("Insert at Cursor").tag(Choice.cursor)
                        Text("Copy Only").tag(Choice.copy)
                        Text("Add to File").tag(Choice.file)
                    }
                    .accessibilityIdentifier("profiles.output")
                }
                if choice == .file {
                    RowDivider()
                    SettingRow(title: "File",
                               detail: FileAppendDelivery.unavailableReason(template: output?.filePath ?? "")
                                ?? String(localized: "Each dictation is added as a new line. {date}, {time} and {app} are filled in.")) {
                        HStack(spacing: 8) {
                            TextField("File path", text: Binding(
                                get: { output?.filePath ?? "" },
                                set: { output = ProfileOutput(kind: .file, filePath: $0) }
                            ))
                            .softField()
                            .labelsHidden()
                            .frame(width: 220)
                            .accessibilityLabel("File path")
                            Button("Choose…", action: chooseFile).buttonStyle(SoftButtonStyle())
                                .accessibilityLabel("Choose file")
                        }
                    }
                }
                RowDivider()
                SettingRow(title: "Send automatically",
                           detail: deliversToCursor
                            ? String(localized: "For AI chats and agents: presses Return when nothing needs a look. Never in browsers, email or chat apps.")
                            : String(localized: "Choose Insert at Cursor to send automatically")) {
                    Toggle("Send automatically", isOn: $sendsAutomatically)
                        .labelsHidden().toggleStyle(.softSwitch)
                        .disabled(!deliversToCursor)
                        .accessibilityIdentifier("profiles.sendsAutomatically")
                }
            }
        }
    }

    private func select(_ choice: Choice) {
        switch choice {
        case .appDefault: output = nil
        case .cursor: output = .cursor
        case .copy: output = .copy
        case .file: output = ProfileOutput(kind: .file, filePath: output?.kind == .file ? output?.filePath ?? "" : "")
        }
        if choice == .copy || choice == .file { sendsAutomatically = false }
    }

    private func chooseFile() {
        // An existing file; type a path with {date} for a new file each day.
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a File for This Profile")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            output = ProfileOutput(kind: .file, filePath: url.path)
        }
    }
}
