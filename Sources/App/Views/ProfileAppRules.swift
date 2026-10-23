import AirdraftCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Profile by app (AD-080): rules that choose a profile from the app you dictate
/// into, by bundle ID or app family. Rules never read what the app shows.
struct ProfileAppRules: View {
    @Environment(AppContainer.self) private var container
    /// The profile shown in the editor above; a new rule starts with it.
    let selectedProfileID: UUID

    private var store: ProfileStore { container.profiles }

    var body: some View {
        PageSection("Profile by app") {
            SettingsCard {
                SettingRow(title: "Choose profile by app", subtitle: "Apps without a rule use the profile in use") {
                    Toggle("Choose profile by app", isOn: Binding(
                        get: { store.choosesProfileByApp },
                        set: { store.setChoosesProfileByApp($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.softSwitch)
                    .accessibilityIdentifier("profiles.byApp")
                }
                if store.choosesProfileByApp {
                    ForEach(store.appRules) { rule in
                        RowDivider()
                        ruleRow(rule)
                    }
                    RowDivider()
                    SettingRow(title: "Rule priority", subtitle: "An app's own rule comes before its family's") {
                        addMenu
                    }
                }
            }
        }
    }

    // MARK: Rows

    private func ruleRow(_ rule: AppProfileRule) -> some View {
        let name = title(rule)
        return HStack(spacing: Theme.controlSpacing) {
            icon(rule)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            SettingRow(title: .verbatim(name), detail: detail(rule)) {
                HStack(spacing: 8) {
                    SoftPicker(String(localized: "Profile for \(name)"), selection: Binding(
                        get: { rule.profileID },
                        set: { store.setProfile($0, forRule: rule.id) }
                    ), width: 160) {
                        ForEach(store.profiles) { profile in
                            Text(profile.name.isEmpty ? String(localized: "Untitled profile") : profile.displayName).tag(profile.id)
                        }
                    }
                    Button {
                        store.removeAppRule(id: rule.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(SoftIconButtonStyle())
                    .help("Remove Rule")
                    .accessibilityLabel(Text("Remove rule for \(name)"))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func title(_ rule: AppProfileRule) -> String {
        switch rule.match {
        case .family(let family): family.ruleTitle
        case .app(let bundleID): InstalledApplications.entry(for: bundleID).name ?? rule.appName ?? bundleID
        }
    }

    private func detail(_ rule: AppProfileRule) -> String? {
        switch rule.match {
        case .family(let family):
            let examples = family.ruleExamples.prefix(4).joined(separator: ", ")
            return String(localized: "\(examples) and similar apps", comment: "Apps an app family rule matches")
        case .app(let bundleID):
            return InstalledApplications.entry(for: bundleID).name == nil ? String(localized: "Not found on this Mac") : nil
        }
    }

    @ViewBuilder
    private func icon(_ rule: AppProfileRule) -> some View {
        switch rule.match {
        case .app(let bundleID):
            if let image = InstalledApplications.entry(for: bundleID).icon {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").font(.system(size: 16)).foregroundStyle(.secondary)
            }
        case .family(let family):
            Image(systemName: Self.symbol(for: family)).font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private static func symbol(for family: AppFamily) -> String {
        switch family {
        case .code: "chevron.left.forwardslash.chevron.right"
        case .terminal: "terminal"
        case .email: "envelope"
        case .workChat: "bubble.left.and.bubble.right"
        case .personalChat: "message"
        case .document: "doc.text"
        case .general: "app"
        }
    }

    // MARK: Adding rules

    private var addMenu: some View {
        SoftMenuButton(title: "Add Rule") {
            let families = AppProfileRule.selectableFamilies.filter { family in
                !store.appRules.contains { $0.match == .family(family) }
            }
            if !families.isEmpty {
                Section("App Families") {
                    ForEach(families, id: \.self) { family in
                        Button(family.ruleTitle) { add(.family(family), name: nil) }
                    }
                }
            }
            let running = InstalledApplications.running().filter { app in
                !store.appRules.contains { $0.match == .app(bundleID: app.bundleID) }
            }
            if !running.isEmpty {
                Section("Open Apps") {
                    ForEach(running, id: \.bundleID) { app in
                        Button(app.name) { add(.app(bundleID: app.bundleID), name: app.name) }
                    }
                }
            }
            Divider()
            Button("Choose App…", action: chooseApp)
        } label: {
            Text("Add Rule  \(Image(systemName: "chevron.down"))")
        }
        // The label's chevron would otherwise trail the name with spaces.
        .accessibilityLabel(Text("Add Rule"))
        .accessibilityIdentifier("profiles.addAppRule")
    }

    private func add(_ match: AppProfileRule.Match, name: String?) {
        let profileID = store.profiles.contains { $0.id == selectedProfileID } ? selectedProfileID : store.activeProfileID
        store.addAppRule(match, profileID: profileID, appName: name)
    }

    /// Reads only the chosen bundle's identifier and name.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "Add Rule")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return }
        add(.app(bundleID: bundleID), name: InstalledApplications.displayName(of: url))
    }
}
