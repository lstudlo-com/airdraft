import AirdraftCore
import SwiftUI

struct ProfileEditor: View {
    @Environment(AppContainer.self) private var container
    let profile: RefinementProfile
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var showPrompt = false
    @State private var showTask = false
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var editingName = false
    @FocusState private var nameFocused: Bool

    private static let symbols: [(String, String)] = [
        ("sparkles", "Clean"), ("text.line.first.and.arrowtriangle.forward", "Concise"),
        ("list.bullet", "List"), ("text.quote", "Quotation"), ("envelope", "Email"),
        ("bubble.left", "Message"), ("doc.text", "Document"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("globe", "Language"),
        ("checklist", "Checklist")
    ]

    private var current: RefinementProfile {
        container.profiles.profiles.first { $0.id == profile.id } ?? profile
    }

    private var active: Bool { current.id == container.profiles.activeProfileID }

    private func binding<T>(_ keyPath: WritableKeyPath<RefinementProfile, T>) -> Binding<T> {
        Binding(get: { current[keyPath: keyPath] }, set: { value in
            var updated = current
            updated[keyPath: keyPath] = value
            container.profiles.update(updated)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            header
            Divider().opacity(0.4)
            Toggle("Refine transcript", isOn: binding(\.usesLLM))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13, weight: .medium))
            if current.usesLLM {
                ProfileTextEditor(title: "Instructions", text: binding(\.instructions), height: 200)
                DisclosureGroup("Task", isExpanded: $showTask) {
                    ProfileTextEditor(
                        title: "Task", text: binding(\.task), height: 90,
                        showsTitle: false,
                        placeholder: "Optional: give the transcript a different purpose, such as a summary or translation."
                    )
                    .padding(.top, Theme.sectionTitleSpacing)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                Text("Your transcript is inserted without AI refinement. Vocabulary replacements and script conversion still apply.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 2)
        .onAppear { showTask = !current.task.isEmpty }
        .sheet(isPresented: $showPrompt) { ProfilePromptPreview(profile: current) }
        .confirmationDialog("Reset “\(current.name)” to its default?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset profile", role: .destructive) {
                container.profiles.resetProfile(id: current.id)
                showTask = !current.task.isEmpty
            }
        } message: { Text("Your changes to this built-in profile will be replaced.") }
        .confirmationDialog("Delete “\(current.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive, action: onDelete)
        } message: { Text("This cannot be undone.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.controlSpacing) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Icon", selection: binding(\.symbol)) {
                        ForEach(Self.symbols, id: \.0) { symbol, name in
                            Label(name, systemImage: symbol).tag(symbol)
                        }
                    }
                } label: {
                    Image(systemName: current.symbol.isEmpty ? "text.alignleft" : current.symbol)
                        .font(.system(size: 18))
                        .frame(width: 24, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Change profile icon")
                .accessibilityLabel("Change profile icon")
                Group {
                    if editingName {
                        TextField("Profile name", text: binding(\.name))
                            .textFieldStyle(.plain)
                            .focused($nameFocused)
                            .accessibilityLabel("Profile name")
                            .task {
                                await Task.yield()
                                nameFocused = true
                            }
                            .onSubmit { editingName = false }
                            .onExitCommand { editingName = false }
                            .onChange(of: nameFocused) { _, focused in
                                if !focused { editingName = false }
                            }
                    } else {
                        Button { editingName = true } label: {
                            Text(current.name.isEmpty ? "Untitled profile" : current.name)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rename \(current.name)")
                        .help("Rename profile")
                    }
                }
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                actions
            }
            HStack {
                Text(current.isBuiltIn ? "Built-in profile" : "Custom profile")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if active {
                    Label("Current profile", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                } else {
                    Button("Use profile") { container.profiles.setActive(current.id) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("profiles.activate")
                }
            }
        }
    }

    private var actions: some View {
        Menu {
            Button("Rename profile") { editingName = true }
            Button("Duplicate profile", action: onDuplicate)
            Button("Preview prompt…") { showPrompt = true }
                .disabled(!current.usesLLM)
            Divider()
            if current.isBuiltIn {
                Button("Reset profile…") { confirmReset = true }
                    .disabled(container.profiles.isDefault(current))
            } else {
                Button("Delete profile…", role: .destructive) { confirmDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions for \(current.name)")
        .accessibilityLabel("Actions for \(current.name)")
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
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.13), lineWidth: focused ? 1.5 : 0.5)
            }
        }
    }
}
