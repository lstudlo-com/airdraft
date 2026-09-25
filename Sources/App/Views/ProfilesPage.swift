import AirdraftCore
import SwiftUI

struct ProfilesPage: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: UUID?
    @State private var editingProfileID: UUID?
    @State private var nameDraft = ""
    @State private var presentedSheet: ProfileSheet?
    @State private var confirmation: ProfileConfirmation?
    @State private var showsBasePromptWarning = false

    init(selection: UUID? = nil) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        PageScaffold(.profiles, scrollsContent: false) {
            if let error = container.profiles.persistenceError {
                StorageNotice(message: error) { container.profiles.retrySave() }
            }
            PageSection("Base system prompt") {
                SettingsCard {
                    HStack(spacing: Theme.controlSpacing) {
                        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                            Text(container.profiles.baseRulesAreDefault ? "Default prompt" : "Custom prompt")
                                .font(.system(size: 13, weight: .medium))
                            Text("Shared by all profiles that use AI refinement. Each profile adds its own instructions.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button("Edit…") { showsBasePromptWarning = true }
                            .buttonStyle(SoftButtonStyle())
                            .accessibilityLabel("Edit base system prompt")
                            .accessibilityIdentifier("profiles.editBasePrompt")
                    }
                }
            }
            HStack(alignment: .top, spacing: Theme.pagePadding) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(container.profiles.profiles) { profile in
                            ProfileListRow(
                                name: profile.name,
                                nameDraft: $nameDraft,
                                active: profile.id == container.profiles.activeProfileID,
                                selected: profile.id == selection,
                                editing: profile.id == editingProfileID,
                                action: {
                                    finishRenameIfNeeded()
                                    selection = profile.id
                                },
                                finishRename: { finishRename(profile.id) }
                            )
                            .contextMenu {
                                profileActions(for: profile)
                                Divider()
                                Button("Use Profile") { container.profiles.setActive(profile.id) }
                                    .disabled(profile.id == container.profiles.activeProfileID)
                            }
                        }
                    }
                }
                .frame(width: 136)
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { finishRenameIfNeeded() }
                }
                Divider().opacity(0.4)
                ScrollView {
                    if let profile = selectedProfile {
                        ProfileEditor(profile: profile).id(profile.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .simultaneousGesture(TapGesture().onEnded { finishRenameIfNeeded() })
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } accessory: {
            HStack(spacing: Theme.sectionTitleSpacing) {
                Button {
                    finishRenameIfNeeded()
                    let newProfile = container.profiles.addNew()
                    selection = newProfile.id
                    beginRename(newProfile)
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
        .onDisappear { finishRenameIfNeeded() }
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
            Text("Changes affect every profile that uses AI refinement. Removing core rules can reduce accuracy or make the AI answer your dictation instead of refining it. You can restore the default prompt at any time.")
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

    /// Shared by the action menu and each row's context menu.
    @ViewBuilder
    private func profileActions(for profile: RefinementProfile) -> some View {
        Button("Rename Profile") {
            selection = profile.id
            beginRename(profile)
        }
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

    private func beginRename(_ profile: RefinementProfile) {
        finishRenameIfNeeded()
        nameDraft = container.profiles.profiles.first(where: { $0.id == profile.id })?.name ?? profile.name
        editingProfileID = profile.id
    }

    private func finishRenameIfNeeded() {
        guard let editingProfileID else { return }
        finishRename(editingProfileID)
    }

    private func finishRename(_ id: UUID) {
        guard editingProfileID == id else { return }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty,
           var profile = container.profiles.profiles.first(where: { $0.id == id }),
           profile.name != name {
            profile.name = name
            container.profiles.update(profile)
        }
        editingProfileID = nil
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
        editingProfileID = nil
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

private struct ProfileListRow: View {
    let name: String
    @Binding var nameDraft: String
    let active: Bool
    let selected: Bool
    let editing: Bool
    let action: () -> Void
    let finishRename: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if editing {
                row {
                    TextField("Profile name", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .accessibilityLabel("Profile name")
                        .task {
                            await Task.yield()
                            nameFocused = true
                        }
                        .onSubmit { finishRename() }
                        .onExitCommand { finishRename() }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { finishRename() }
                        }
                }
                .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
            } else {
                Button(action: action) {
                    row { Text(name.isEmpty ? "Untitled profile" : name).lineLimit(1) }
                }
                .buttonStyle(NavigationRowStyle(selected: selected))
                .accessibilityLabel(name)
                .accessibilityValue(active ? "Current dictation profile" : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(active ? "\(name) · Current dictation profile" : name)
            }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 9) {
            content().font(.system(size: 13))
            Spacer(minLength: 2)
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .contentShape(Rectangle())
    }
}
