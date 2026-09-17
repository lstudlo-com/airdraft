import AirdraftCore
import SwiftUI

struct ProfilesPage: View {
    @Environment(AppContainer.self) private var container
    @State private var selection: UUID?
    @State private var confirmResetAll = false
    @State private var showBaseRules = false

    var body: some View {
        PageScaffold {
            SectionTitle("Profiles") {
                HStack(spacing: 8) {
                    Button { selection = container.profiles.addNew().id } label: { Label("New profile", systemImage: "plus") }
                        .buttonStyle(SoftButtonStyle())
                    Button("Reset all…", role: .destructive) { confirmResetAll = true }
                        .buttonStyle(SoftButtonStyle())
                }
            }
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 0) {
                    ForEach(Array(container.profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                        if index > 0 { RowDivider().padding(.leading, 16) }
                        ProfileListRow(
                            profile: profile,
                            active: profile.id == container.profiles.activeProfileID,
                            selected: profile.id == selection
                        ) { selection = profile.id }
                    }
                }
                .frame(width: 220)

                if let profile = selectedProfile {
                    Card(padding: 0) {
                        ProfileEditor(profile: profile, onDelete: {
                            container.profiles.remove(id: profile.id)
                            selection = container.profiles.activeProfileID
                        })
                    }
                    .id(profile.id)
                } else {
                    Card { Text("Select a profile").foregroundStyle(.secondary) }
                }
            }

            DisclosureGroup("Shared base rules (advanced)", isExpanded: $showBaseRules) {
                Card {
                    TextEditor(text: Binding(
                        get: { container.profiles.baseRules },
                        set: { container.profiles.setBaseRules($0) }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 180)
                    .padding(.vertical, 8)
                    HStack {
                        Spacer()
                        Button("Reset base rules") { container.profiles.resetBaseRules() }
                            .buttonStyle(SoftButtonStyle())
                            .disabled(container.profiles.baseRulesAreDefault)
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .onAppear { selection = container.profiles.activeProfileID }
        .confirmationDialog(
            "Reset every profile and the base rules to their defaults? Profiles you created will be removed.",
            isPresented: $confirmResetAll, titleVisibility: .visible
        ) {
            Button("Reset everything", role: .destructive) {
                container.profiles.resetAll()
                selection = container.profiles.activeProfileID
            }
        }
    }

    private var selectedProfile: RefinementProfile? {
        container.profiles.profiles.first { $0.id == selection }
    }
}

struct ProfileListRow: View {
    let profile: RefinementProfile
    let active: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: profile.symbol.isEmpty ? "questionmark" : profile.symbol, color: profile.usesLLM ? .blue : .gray, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.system(size: 13, weight: .medium))
                Text(profile.usesLLM ? "LLM" : "No LLM").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if active { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tint) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Color.primary.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct ProfileEditor: View {
    @Environment(AppContainer.self) private var container
    let profile: RefinementProfile
    let onDelete: () -> Void
    @State private var showPrompt = false

    static let symbols = ["sparkles", "text.line.first.and.arrowtriangle.forward", "list.bullet", "text.quote", "envelope", "bubble.left", "doc.text", "chevron.left.forwardslash.chevron.right", "globe", "checklist"]

    private var current: RefinementProfile {
        container.profiles.profiles.first { $0.id == profile.id } ?? profile
    }

    private func binding<T>(_ keyPath: WritableKeyPath<RefinementProfile, T>) -> Binding<T> {
        Binding(
            get: { current[keyPath: keyPath] },
            set: { value in
                var p = current
                p[keyPath: keyPath] = value
                container.profiles.update(p)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: icon, editable name, state
            HStack(spacing: 10) {
                IconBadge(symbol: current.symbol.isEmpty ? "questionmark" : current.symbol, color: current.usesLLM ? .blue : .gray, size: 26)
                TextField("Name", text: binding(\.name))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if current.isBuiltIn { PillTag(text: "BUILT-IN") }
                if current.id == container.profiles.activeProfileID {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Button("Set active") { container.profiles.setActive(current.id) }.buttonStyle(SoftButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider().opacity(0.45)

            VStack(spacing: 0) {
                SettingRow(title: "Icon") {
                    HStack(spacing: 6) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button { binding(\.symbol).wrappedValue = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(current.symbol == symbol ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(current.symbol == symbol ? Color.accentColor : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(current.symbol == symbol ? Color.accentColor : Color.secondary)
                        }
                    }
                }
                RowDivider()
                SettingRow(title: "Use LLM", subtitle: current.usesLLM ? nil : "Inserts the raw transcript; only vocabulary and script conversion run") {
                    Toggle("", isOn: binding(\.usesLLM)).labelsHidden().toggleStyle(.switch)
                }
                if current.usesLLM {
                    RowDivider()
                    PromptEditorRow(title: "Task", hint: "Optional. Leads the prompt when the output is not a cleaned transcript.", text: binding(\.task), minHeight: 52)
                    RowDivider()
                    PromptEditorRow(title: "Instructions", hint: "Length, tone and shape of the output.", text: binding(\.instructions), minHeight: 132)
                }
            }
            .padding(.horizontal, 14)

            Divider().opacity(0.45)
            HStack {
                if current.isBuiltIn {
                    Button("Reset to default") { container.profiles.resetProfile(id: current.id) }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(container.profiles.isDefault(current))
                } else {
                    Button("Delete profile", role: .destructive, action: onDelete).buttonStyle(SoftButtonStyle())
                }
                Spacer()
                Button("Preview prompt") { showPrompt = true }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(!current.usesLLM)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showPrompt) {
            let req = RefineRequest(
                transcript: "<transcription>",
                profile: current,
                baseRules: container.profiles.baseRules,
                context: .empty, family: .general,
                dictionary: container.dictionary.entries,
                chineseScript: container.settings.asr.chineseScript
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("System prompt for “\(current.name)”").font(.headline)
                ScrollView {
                    Text(PromptBuilder.systemPrompt(for: req))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("Close") { showPrompt = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(16)
            .frame(width: 600, height: 500)
        }
    }
}

/// Label + hint on the left, an inset text editor below. Reads like a form, not a code box.
struct PromptEditorRow: View {
    let title: String
    let hint: String
    @Binding var text: String
    var minHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(hint).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: minHeight)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .padding(.vertical, 11)
    }
}
