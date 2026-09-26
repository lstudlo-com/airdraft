import AirdraftCore
import SwiftUI

struct ProfilesPage: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: UUID?
    @State private var nameFocusRequest: UUID?
    @State private var presentedSheet: ProfileSheet?
    @State private var confirmation: ProfileConfirmation?
    @State private var showsBasePromptWarning = false

    init(selection: UUID? = nil) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        PageScaffold(.profiles) {
            if let error = container.profiles.persistenceError {
                StorageNotice(message: error) { container.profiles.retrySave() }
            }
            if let profile = selectedProfile {
                ProfileEditor(profile: profile, nameFocusRequest: $nameFocusRequest) {
                    profilePicker
                }
                .id(profile.id)
            }
            PageSection("Base system prompt") {
                SettingsCard {
                    SettingRow(
                        title: container.profiles.baseRulesAreDefault ? "Default prompt" : "Custom prompt",
                        subtitle: "Shared by all AI refinement profiles"
                    ) {
                        Button("Edit…") { showsBasePromptWarning = true }
                            .buttonStyle(SoftButtonStyle())
                            .accessibilityLabel("Edit base system prompt")
                            .accessibilityIdentifier("profiles.editBasePrompt")
                    }
                }
            }
        } accessory: {
            HStack(spacing: Theme.sectionTitleSpacing) {
                Button {
                    let newProfile = container.profiles.addNew()
                    selection = newProfile.id
                    nameFocusRequest = newProfile.id
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .buttonStyle(SoftButtonStyle())
                .accessibilityIdentifier("profiles.new")
                Menu {
                    if let profile = selectedProfile {
                        profileActions(for: profile)
                        Divider()
                    }
                    Button("Reset All Profiles…", role: .destructive) { confirmation = .resetAll }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .softControlSurface()
                .help("Profile actions")
                .accessibilityLabel("Profile actions")
            }
        }
        .onAppear {
            if selectedProfile == nil { selection = container.profiles.activeProfileID }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .basePrompt: BaseSystemPromptEditor()
            case .prompt(let profile): ProfilePromptPreview(profile: profile)
            }
        }
        .alert("Edit the base system prompt?", isPresented: $showsBasePromptWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue Editing") { presentedSheet = .basePrompt }
        } message: {
            Text("Affects all AI profiles. Removing rules may reduce accuracy or make AI answer your dictation. Defaults can be restored.")
        }
        .confirmationDialog(
            confirmation?.title ?? "",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmation {
                Button(confirmation.actionTitle, role: .destructive) {
                    perform(confirmation)
                }
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
    }

    /// One compact selector replaces the former profile list; the name field,
    /// dictation state and instructions below all follow it.
    private var profilePicker: some View {
        Picker("Profile", selection: Binding(
            get: { selectedProfile?.id ?? container.profiles.activeProfileID },
            set: { selection = $0 }
        )) {
            ForEach(container.profiles.profiles) { profile in
                Text(profile.name.isEmpty ? "Untitled profile" : profile.name).tag(profile.id)
            }
        }
        .settingsPicker(width: 200)
        .accessibilityIdentifier("profiles.picker")
    }

    @ViewBuilder
    private func profileActions(for profile: RefinementProfile) -> some View {
        Button("Rename Profile") { nameFocusRequest = profile.id }
        Button("Duplicate Profile") {
            selection = container.profiles.duplicate(id: profile.id)?.id
        }
        Button("Preview Prompt…") { presentedSheet = .prompt(profile) }
            .disabled(!profile.usesLLM)
        if profile.isBuiltIn {
            Button("Reset Profile…") { confirmation = .reset(profile) }
                .disabled(container.profiles.isDefault(profile))
        } else {
            Button("Delete Profile…", role: .destructive) { confirmation = .delete(profile) }
        }
    }

    private var selectedProfile: RefinementProfile? {
        container.profiles.profiles.first { $0.id == selection }
    }

    private func perform(_ action: ProfileConfirmation) {
        switch action {
        case .reset(let profile):
            container.profiles.resetProfile(id: profile.id)
        case .delete(let profile):
            container.profiles.remove(id: profile.id)
            selection = container.profiles.activeProfileID
        case .resetAll:
            container.profiles.resetAll()
            selection = container.profiles.activeProfileID
        }
        confirmation = nil
    }
}

private enum ProfileSheet: Identifiable {
    case basePrompt
    case prompt(RefinementProfile)

    var id: String {
        switch self {
        case .basePrompt: "base-prompt"
        case .prompt(let profile): "prompt-\(profile.id)"
        }
    }
}

private enum ProfileConfirmation {
    case reset(RefinementProfile)
    case delete(RefinementProfile)
    case resetAll

    var title: String {
        switch self {
        case .reset(let profile): "Reset “\(profile.name)” to its default?"
        case .delete(let profile): "Delete “\(profile.name)”?"
        case .resetAll: "Reset all profiles?"
        }
    }

    var actionTitle: String {
        switch self {
        case .reset: "Reset Profile"
        case .delete: "Delete Profile"
        case .resetAll: "Reset All Profiles"
        }
    }

    var message: String {
        switch self {
        case .reset: "Your changes to this built-in profile will be replaced."
        case .delete: "This cannot be undone."
        case .resetAll: "Restores built-in profiles and the base system prompt. Profiles you created will be deleted."
        }
    }
}
