import AirdraftCore
import SwiftUI

struct BaseSystemPromptEditor: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            Text("Base system prompt").font(.system(size: 20, weight: .semibold))
            Text("Shared by all profiles that use AI refinement. Profile instructions and context rules are added automatically.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ProfileTextEditor(title: "Base system prompt", text: $draft, height: 320, showsTitle: false)
            HStack {
                Button("Restore defaults") { draft = PromptBuilder.defaultBaseRules }
                    .disabled(draft == PromptBuilder.defaultBaseRules)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    container.profiles.setBaseRules(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.pagePadding)
        .frame(width: 620)
        .onAppear { draft = container.profiles.baseRules }
    }
}

struct ProfilePromptPreview: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    let profile: RefinementProfile

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            Text("Prompt for \(profile.name)").font(.system(size: 18, weight: .semibold))
            ScrollView {
                Text(prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.pagePadding)
        .frame(width: 620, height: 500)
    }

    private var prompt: String {
        PromptBuilder.systemPrompt(for: RefineRequest(
            transcript: "<transcription>", profile: profile,
            baseRules: container.profiles.baseRules, context: .empty, family: .general,
            dictionary: container.dictionary.entries,
            chineseScript: container.settings.asr.chineseScript
        ))
    }
}
