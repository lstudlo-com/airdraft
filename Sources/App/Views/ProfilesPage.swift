import AirdraftCore
import SwiftUI

struct ProfilesPage: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: UUID?
    @State private var editingProfileID: UUID?
    @State private var presentedSheet: ProfileSheet?
    @State private var confirmation: ProfileConfirmation?
    @State private var showsBasePromptWarning = false

    private static let symbols: [(String, String)] = [
        ("sparkles", "Clean"), ("text.line.first.and.arrowtriangle.forward", "Concise"),
        ("list.bullet", "List"), ("text.quote", "Quotation"), ("envelope", "Email"),
        ("bubble.left", "Message"), ("doc.text", "Document"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("globe", "Language"),
        ("checklist", "Checklist")
    ]

    init(selection: UUID? = nil) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        PageScaffold(scrollsContent: false) {
            HStack {
                Spacer()
                Button {
                    let newProfile = container.profiles.addNew()
                    selection = newProfile.id
                    editingProfileID = newProfile.id
                } label: {
                    Label("New profile", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("profiles.new")
                Menu {
                    if let profile = selectedProfile {
                        Button("Rename profile") { editingProfileID = profile.id }
                        Menu {
                            ForEach(Self.symbols, id: \.0) { symbol, name in
                                Button {
                                    setSymbol(symbol, for: profile.id)
                                } label: {
                                    Label(name, systemImage: symbol)
                                }
                            }
                        } label: {
                            Label("Change icon", systemImage: profile.symbol.isEmpty ? "text.alignleft" : profile.symbol)
                        }
                        Button("Duplicate profile") {
                            selection = container.profiles.duplicate(id: profile.id)?.id
                        }
                        Button("Preview prompt…") { presentedSheet = .prompt(profile) }
                            .disabled(!profile.usesLLM)
                        if profile.isBuiltIn {
                            Button("Reset profile…") { confirmation = .reset(profile) }
                                .disabled(container.profiles.isDefault(profile))
                        } else {
                            Button("Delete profile…", role: .destructive) { confirmation = .delete(profile) }
                        }
                        Divider()
                    }
                    Button("Reset all profiles…", role: .destructive) { confirmation = .resetAll }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Profile actions")
                .accessibilityLabel("Profile actions")
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
                                profile: profile,
                                name: nameBinding(for: profile),
                                active: profile.id == container.profiles.activeProfileID,
                                selected: profile.id == selection,
                                editing: profile.id == editingProfileID,
                                action: { selection = profile.id },
                                finishRename: { finishRename(profile.id) }
                            )
                        }
                    }
                }
                .frame(width: 164)
                Divider().opacity(0.4)
                ScrollView {
                    if let profile = selectedProfile {
                        ProfileEditor(profile: profile).id(profile.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
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
            Button("Continue editing") { presentedSheet = .basePrompt }
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

    private var selectedProfile: RefinementProfile? {
        container.profiles.profiles.first { $0.id == selection }
    }

    private func nameBinding(for profile: RefinementProfile) -> Binding<String> {
        Binding(
            get: { container.profiles.profiles.first { $0.id == profile.id }?.name ?? profile.name },
            set: { name in
                guard var updated = container.profiles.profiles.first(where: { $0.id == profile.id }) else { return }
                updated.name = name
                container.profiles.update(updated)
            }
        )
    }

    private func setSymbol(_ symbol: String, for id: UUID) {
        guard var updated = container.profiles.profiles.first(where: { $0.id == id }) else { return }
        updated.symbol = symbol
        container.profiles.update(updated)
    }

    private func finishRename(_ id: UUID) {
        if var profile = container.profiles.profiles.first(where: { $0.id == id }),
           profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.name = "Untitled profile"
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
        case .reset: "Reset profile"
        case .delete: "Delete profile"
        case .resetAll: "Reset all profiles"
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
    let profile: RefinementProfile
    @Binding var name: String
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
                    TextField("Profile name", text: $name)
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
            Image(systemName: profile.symbol.isEmpty ? "text.alignleft" : profile.symbol)
                .font(.system(size: 14))
                .frame(width: 18)
                .accessibilityHidden(true)
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
