import AirdraftCore
import SwiftUI

/// What a Models row knows about its speech model (AD-145): the facts behind the
/// row's info button, whose tooltip summarizes them and whose sheet shows them
/// with the full language list. Every local and cloud row has one, so every
/// model's details stay reachable, whatever its language tag says.
struct ModelInfo: Identifiable {
    struct Fact: Hashable {
        let label: String
        let value: String
    }

    let id: String
    let title: String
    /// Who makes or hosts the model, in one short line.
    let subtitle: String
    let facts: [Fact]
    /// The longer explanation: strengths, rating sources, billing.
    let notes: [String]
    let languages: ModelLanguageInfo
    var documentationURL: URL?

    /// The info button's tooltip: the facts and languages in a few lines.
    @MainActor var tooltip: String {
        var lines = [title, subtitle]
        lines += facts.map { "\($0.label): \($0.value)" }
        lines.append(languages.detail)
        lines.append(String(localized: "Click for details."))
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

extension ModelInfo {
    /// A model on this Mac.
    @MainActor init(entry: ModelEntry) {
        let runtime = entry.vendor.components(separatedBy: " · ").dropFirst() + entry.tags
        var facts = [Fact(label: String(localized: "Developer"), value: entry.provider)]
        if !runtime.isEmpty { facts.append(Fact(label: String(localized: "Runtime"), value: runtime.joined(separator: " · "))) }
        switch entry.storage {
        case .download(let size): facts.append(Fact(label: String(localized: "Download size"), value: size))
        case .builtIn: facts.append(Fact(label: String(localized: "Download size"), value: String(localized: "Built in")))
        }
        if let tier = entry.tier { facts.append(Fact(label: String(localized: "Testing"), value: tier.title)) }
        facts.append(Fact(label: String(localized: "Speed"),
                          value: entry.speed > 0 ? ModelRating.label(entry.speed) : String(localized: "Not rated")))
        facts.append(Fact(label: String(localized: "Accuracy"),
                          value: entry.accuracy > 0 ? ModelRating.label(entry.accuracy) : String(localized: "Not rated")))
        facts.append(Fact(label: String(localized: "Languages"), value: entry.languageInfo.label))
        var notes = [entry.note]
        if let tier = entry.tier { notes.append(tier.detail) }
        notes.append(entry.speed > 0 || entry.accuracy > 0
                     ? String(localized: "Ratings are Airdraft's relative guidance for local models. Actual speed depends on your Mac.")
                     : String(localized: "Not benchmarked in Airdraft."))
        self.init(id: entry.id, title: entry.title, subtitle: String(localized: "Runs on this Mac"),
                  facts: facts, notes: notes.filter { !$0.isEmpty }, languages: entry.languageInfo)
    }

    /// A model a cloud provider hosts.
    @MainActor init(preset: EndpointPreset.Speech, model: SpeechModelInfo, languages: ModelLanguageInfo) {
        var facts = [Fact(label: String(localized: "Provider"), value: preset.name),
                     Fact(label: String(localized: "Strength"), value: model.quality),
                     Fact(label: String(localized: "Speed"),
                          value: model.realtimeSpeedFactor.map { "\($0.formatted())×" } ?? model.speed)]
        if let wer = model.wordErrorRate {
            facts.append(Fact(label: String(localized: "Accuracy"), value: String(localized: "\(wer.formatted())% WER")))
        }
        facts.append(Fact(label: String(localized: "Price"), value: model.price))
        facts.append(Fact(label: String(localized: "Languages"), value: languages.label))
        var notes = [model.qualityDetail, model.speedDetail, model.billing]
        if model.wordErrorRate != nil { notes.append(String(localized: "WER is word error rate; lower is better.")) }
        self.init(id: languages.id, title: model.title,
                  subtitle: String(localized: "Hosted by \(preset.name)"),
                  facts: facts, notes: notes.filter { !$0.isEmpty }, languages: languages,
                  documentationURL: model.documentationURL)
    }
}

/// Presents a model's info sheet from the page, so a table row that scrolls out
/// of a virtualized list cannot dismiss it. Like `DismissAction`, it compares
/// equal: the page installs one action for its lifetime.
struct ShowModelInfoAction: Equatable {
    let present: @MainActor (ModelInfo) -> Void
    @MainActor func callAsFunction(_ info: ModelInfo) { present(info) }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var showModelInfo = ShowModelInfoAction { _ in }
}

/// The info button beside a row's pin: hover shows the model's details as a
/// tooltip, clicking opens them with every language in a sheet. A button of
/// its own, so its click wins over the row's whole-row click.
struct ModelInfoButton: View {
    @Environment(\.showModelInfo) private var showInfo
    @Environment(\.colorSchemeContrast) private var contrast
    /// Built only when needed: the tooltip and sheet, not every row redraw.
    let info: @MainActor () -> ModelInfo
    let title: String
    let rowHovered: Bool

    var body: some View {
        Button { showInfo(info()) } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .opacity(rowHovered || contrast == .increased ? 1 : 0.6)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(rowHovered ? info().tooltip : "")
        .accessibilityLabel(String(localized: "Details for \(title)"))
        .accessibilityHint(Text("Shows the model's details and every language it recognizes."))
    }
}

/// A model's details and every language it recognizes, organized: the user's own
/// languages first, then the rest A to Z, with a search field for long lists.
struct ModelInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let info: ModelInfo
    @State private var query = ""

    private struct Language: Identifiable {
        let id: String
        let name: String
    }

    private var languages: [Language] {
        (info.languages.codes ?? []).map { Language(id: $0, name: SpeechLanguagePolicy.languageLabel($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var userCodes: Set<String> {
        var codes = Set(SystemLanguages.preferred.compactMap(LocalSpeechRecommendation.normalized))
        if let system = LocalSpeechRecommendation.normalized(ModelCatalogue.systemLanguage) { codes.insert(system) }
        return codes
    }

    private static let shadowRoom: CGFloat = 12

    private var filtered: [Language] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return languages }
        return languages.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: info.title).appFont(.title, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: info.subtitle).supportingText()
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                    details
                    languageSection
                }
                // Room for the cards' light and shade, which the scroll view would clip.
                .padding(Self.shadowRoom)
            }
            .padding(-Self.shadowRoom)
            .frame(maxHeight: 480)
            .scrollBounceBehavior(.basedOnSize)
            HStack {
                if let url = info.documentationURL {
                    Link("Model Page", destination: url)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .primaryButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
            // The scroll view's shadow room reaches into the gap above.
            .padding(.top, Self.shadowRoom)
        }
        .padding(Theme.pagePadding)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("Details")
            // Two columns of label-over-value pairs, so the languages stay in view.
            Card {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.controlSpacing, alignment: .topLeading), count: 2),
                          alignment: .leading, spacing: 12) {
                    ForEach(info.facts, id: \.self) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: fact.label).supportingText()
                            Text(verbatim: fact.value).appFont(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !info.notes.isEmpty {
                Text(verbatim: Self.joined(info.notes))
                    .supportingText()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.sectionTitleLeadingInset)
            }
        }
    }

    @ViewBuilder
    private var languageSection: some View {
        if info.languages.opensList {
            let all = filtered
            let mine = all.filter { userCodes.contains($0.id) }
            HStack(alignment: .center, spacing: Theme.controlSpacing) {
                heading("Languages")
                Spacer(minLength: 0)
                if languages.count > 12 { SearchField(text: $query, placeholder: "Search languages") }
            }
            if all.isEmpty { EmptyNote("No languages match your search.") }
            if !mine.isEmpty { languageGroup("Your languages", mine) }
            if !all.isEmpty { languageGroup(mine.isEmpty ? "All languages" : "All supported languages", all) }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                heading("Languages")
                Card {
                    Text(verbatim: info.languages.detail).appFont(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Sentences joined with a space, except after full-width punctuation ("較弱。已在").
    private static func joined(_ sentences: [String]) -> String {
        sentences.map { $0.trimmingCharacters(in: .whitespaces) }.reduce(into: "") { text, sentence in
            if let last = text.last, !"。！？）」".contains(last) { text += " " }
            text += sentence
        }
    }

    private func heading(_ title: LocalizedStringResource) -> some View {
        Text(title).appFont(.detail, weight: .semibold).foregroundStyle(.secondary)
            .padding(.leading, Theme.sectionTitleLeadingInset)
            .accessibilityAddTraits(.isHeader)
    }

    private func languageGroup(_ title: LocalizedStringResource, _ items: [Language]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appFont(.detail).foregroundStyle(.secondary)
                .padding(.leading, Theme.sectionTitleLeadingInset)
                .accessibilityAddTraits(.isHeader)
            Card {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.controlSpacing, alignment: .leading), count: 3),
                          alignment: .leading, spacing: 8) {
                    ForEach(items) { language in
                        Text(language.name).appFont(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
