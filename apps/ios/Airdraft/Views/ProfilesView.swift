import AirdraftCore
import SwiftUI

/// Chooses the profile dictation uses. Profiles are shared with the Mac app's
/// model: built-ins keep their stable IDs and their localized names.
struct ProfilesView: View {
    @Environment(ProfileStore.self) private var profiles

    var body: some View {
        SoftPage {
            SoftSection(title: "Profile") {
                ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { RowDivider() }
                    Button {
                        profiles.setActive(profile.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .foregroundStyle(.primary)
                                Text(profile.usesLLM ? String(localized: "Refines the transcript") : String(localized: "Keeps your exact words"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profiles.activeProfileID == profile.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: MobileTheme.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(profiles.activeProfileID == profile.id ? .isSelected : [])
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Preferred spellings and the misheard forms to replace. The dictionary is
/// applied last, after refinement, as on the Mac.
struct VocabularyView: View {
    @Environment(DictionaryStore.self) private var dictionary
    @State private var editing: DictionaryEntry?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(dictionary.entries) { entry in
                    Button { editing = entry } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term).foregroundStyle(.primary)
                            if !entry.aliases.isEmpty {
                                Text(entry.aliases.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { dictionary.remove(id: dictionary.entries[index].id) }
                }
            } footer: {
                Text("Names and terms Airdraft should always spell your way.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(MobileTheme.background.ignoresSafeArea())
        .overlay {
            if dictionary.entries.isEmpty {
                ContentUnavailableView("No Terms", systemImage: "character.book.closed",
                                       description: Text("Add names and terms Airdraft should always spell your way."))
            }
        }
        .navigationTitle("Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { adding = true } label: { Label("Add Term", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) {
            TermEditor(entry: nil) { dictionary.add($0) }
        }
        .sheet(item: $editing) { entry in
            TermEditor(entry: entry) { dictionary.update($0) }
        }
    }
}

private struct TermEditor: View {
    let entry: DictionaryEntry?
    let save: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var aliases = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Spelling", text: $term)
                        .autocorrectionDisabled()
                } footer: {
                    Text("How the word should appear.")
                }
                Section {
                    TextField("Misheard as", text: $aliases)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Optional. Separate several with commas.")
                }
            }
            .navigationTitle(entry == nil ? "Add Term" : "Edit Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let list = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        var saved = entry ?? DictionaryEntry(term: "")
                        saved.term = term.trimmingCharacters(in: .whitespaces)
                        saved.aliases = list
                        save(saved)
                        dismiss()
                    }
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            term = entry?.term ?? ""
            aliases = entry?.aliases.joined(separator: ", ") ?? ""
        }
    }
}
