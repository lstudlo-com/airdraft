import AirdraftCore
import SwiftUI

struct ProfilesPage: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: UUID?
    @State private var confirmResetAll = false
    @State private var showBaseRules = false

    init(selection: UUID? = nil) {
        _selection = State(initialValue: selection)
    }

    var body: some View {
        PageScaffold(scrollsContent: false) {
            HStack {
                Text("Profiles").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { selection = container.profiles.addNew().id } label: {
                    Label("New profile", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityIdentifier("profiles.new")
                Menu {
                    Button("Shared rules…") { showBaseRules = true }
                    Divider()
                    Button("Reset all profiles…", role: .destructive) { confirmResetAll = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Profile settings")
                .accessibilityLabel("Profile settings")
            }

            HStack(alignment: .top, spacing: Theme.pagePadding) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(container.profiles.profiles) { profile in
                            ProfileListRow(
                                profile: profile,
                                active: profile.id == container.profiles.activeProfileID,
                                selected: profile.id == selection
                            ) { selection = profile.id }
                        }
                    }
                }
                .frame(width: 164)
                Divider().opacity(0.4)
                ScrollView {
                    if let profile = selectedProfile {
                        ProfileEditor(profile: profile, onDuplicate: {
                            selection = container.profiles.duplicate(id: profile.id)?.id
                        }, onDelete: {
                            container.profiles.remove(id: profile.id)
                            selection = container.profiles.activeProfileID
                        })
                        .id(profile.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            if selectedProfile == nil { selection = container.profiles.activeProfileID }
        }
        .sheet(isPresented: $showBaseRules) { SharedProfileRulesEditor() }
        .confirmationDialog("Reset all profiles?", isPresented: $confirmResetAll, titleVisibility: .visible) {
            Button("Reset all profiles", role: .destructive) {
                container.profiles.resetAll()
                selection = container.profiles.activeProfileID
            }
        } message: {
            Text("Restores built-in profiles and shared rules. Profiles you created will be deleted.")
        }
    }

    private var selectedProfile: RefinementProfile? {
        container.profiles.profiles.first { $0.id == selection }
    }
}

private struct ProfileListRow: View {
    let profile: RefinementProfile
    let active: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: profile.symbol.isEmpty ? "text.alignleft" : profile.symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(profile.name).font(.system(size: 13)).lineLimit(1)
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
        .buttonStyle(NavigationRowStyle(selected: selected))
        .accessibilityLabel(profile.name)
        .accessibilityValue(active ? "Current dictation profile" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(active ? "\(profile.name) · Current dictation profile" : profile.name)
    }
}
