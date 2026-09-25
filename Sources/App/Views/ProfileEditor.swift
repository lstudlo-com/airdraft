import AirdraftCore
import SwiftUI

struct ProfileEditor: View {
    @Environment(AppContainer.self) private var container
    let profile: RefinementProfile
    @State private var showTask = false

    private var current: RefinementProfile {
        container.profiles.profiles.first { $0.id == profile.id } ?? profile
    }

    private func binding<T>(_ keyPath: WritableKeyPath<RefinementProfile, T>) -> Binding<T> {
        Binding(get: { current[keyPath: keyPath] }, set: { value in
            var updated = current
            updated[keyPath: keyPath] = value
            container.profiles.update(updated)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            HStack {
                Toggle("Refine transcript", isOn: binding(\.usesLLM))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if current.id != container.profiles.activeProfileID {
                    Button("Use profile") { container.profiles.setActive(current.id) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("profiles.activate")
                }
            }
            if current.usesLLM {
                ProfileTextEditor(title: "Profile instructions", text: binding(\.instructions), height: 200)
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
        .onChange(of: current.task) { _, task in
            if !task.isEmpty { showTask = true }
        }
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
