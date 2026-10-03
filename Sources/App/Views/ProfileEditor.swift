import AirdraftCore
import SwiftUI

/// The selected profile's sections. The picker sits in the Profile heading, as the
/// provider pickers do on Models.
struct ProfileEditor<Chooser: View>: View {
    @Environment(AppContainer.self) private var container
    let profile: RefinementProfile
    /// Set to this profile's id to focus its name field, then cleared.
    @Binding var nameFocusRequest: UUID?
    @ViewBuilder var chooser: Chooser
    @State private var nameDraft = ""
    @State private var showTask = false
    @FocusState private var nameFocused: Bool

    private var current: RefinementProfile {
        container.profiles.profiles.first { $0.id == profile.id } ?? profile
    }

    private var isActive: Bool { current.id == container.profiles.activeProfileID }

    private func binding<T>(_ keyPath: WritableKeyPath<RefinementProfile, T>) -> Binding<T> {
        Binding(get: { current[keyPath: keyPath] }, set: { value in
            var updated = current
            updated[keyPath: keyPath] = value
            container.profiles.update(updated)
        })
    }

    var body: some View {
        PageSection("Profile", trailing: { chooser }) {
            SettingsCard {
                SettingRow(title: "Name") {
                    TextField("Profile name", text: $nameDraft)
                        .softField()
                        .labelsHidden()
                        .frame(width: Theme.fieldWidth)
                        .focused($nameFocused)
                        .accessibilityLabel("Profile name")
                        .accessibilityIdentifier("profiles.name")
                        .onSubmit(commitName)
                        .onExitCommand {
                            nameDraft = current.name
                            nameFocused = false
                        }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { commitName() }
                        }
                }
                RowDivider()
                SettingRow(title: "Dictation") {
                    if isActive {
                        HStack(spacing: 8) {
                            StatusDot(.ok)
                            Text("In Use").foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 28)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Current dictation profile")
                    } else {
                        Button("Use Profile") { container.profiles.setActive(current.id) }
                            .buttonStyle(SoftButtonStyle())
                            .accessibilityIdentifier("profiles.activate")
                    }
                }
                RowDivider()
                SettingRow(
                    title: "Refine transcript",
                    subtitle: current.usesLLM ? nil : "Vocabulary and script conversion still apply"
                ) {
                    Toggle("Refine transcript", isOn: binding(\.usesLLM))
                        .labelsHidden()
                        .toggleStyle(.softSwitch)
                }
            }
            .onAppear {
                nameDraft = current.name
                showTask = !current.task.isEmpty
                focusNameIfRequested()
            }
            .onDisappear(perform: commitName)
            .onChange(of: current.name) { _, name in
                if !nameFocused { nameDraft = name }
            }
            .onChange(of: current.task) { _, task in
                if !task.isEmpty { showTask = true }
            }
            .onChange(of: nameFocusRequest) { _, _ in focusNameIfRequested() }
        }

        ProfileSpeechSettings(selection: binding(\.speechModel))

        if current.usesLLM {
            PageSection("Instructions") {
                ProfileTextEditor(title: "Profile instructions", text: binding(\.instructions), height: 180, showsTitle: false)
                DisclosureGroup("Task", isExpanded: $showTask) {
                    ProfileTextEditor(
                        title: "Task", text: binding(\.task), height: 90,
                        showsTitle: false,
                        placeholder: "Optional: summarize, translate, or set another task."
                    )
                    .padding(.top, Theme.sectionTitleSpacing)
                }
                .settingsDisclosure()
            }
        }
    }

    private func focusNameIfRequested() {
        guard nameFocusRequest == profile.id else { return }
        nameFocusRequest = nil
        Task {
            await Task.yield()
            nameFocused = true
        }
    }

    /// An empty draft restores the saved name rather than leaving the profile untitled.
    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            nameDraft = current.name
            return
        }
        if name != current.name {
            var updated = current
            updated.name = name
            container.profiles.update(updated)
        }
        nameDraft = name
    }
}

struct ProfileTextEditor: View {
    let title: String
    @Binding var text: String
    let height: CGFloat
    var showsTitle = true
    var placeholder = "Describe the wording, tone, or format you want."
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            if showsTitle {
                Text(title).font(.system(size: 13, weight: .medium))
            }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($focused)
                    .accessibilityLabel(title)
            }
            .foregroundStyle(.primary)
            .frame(height: height)
            .background { SoftRaisedSurface(shape: SoftControl.fieldShape) }
            .overlay {
                SoftControl.fieldShape
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .opacity(focused ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }
}
