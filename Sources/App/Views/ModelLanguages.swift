import AirdraftCore
import SwiftUI

/// A speech model's languages as the Models table shows them (AD-122): one compact
/// tag, the complete list in its tooltip, and an organized sheet on click. Local and
/// cloud rows read the same `SpeechLanguagePolicy` capabilities, so the table never
/// claims a language the recording check would refuse.
struct ModelLanguageInfo: Identifiable, Equatable {
    let id: String
    let modelTitle: String
    /// A complete known list, or nil when macOS or the provider owns it.
    let codes: [String]?
    /// The policy's own sentence, such as whether a selected language is a hint.
    let summary: String
    let ownedByMacOS: Bool
    let detectsAutomatically: Bool

    @MainActor private static var cache: [String: ModelLanguageInfo] = [:]

    @MainActor static func make(id: String, title: String, config: ASRConfig) -> ModelLanguageInfo {
        if let cached = cache[id], cached.modelTitle == title { return cached }
        let capabilities = SpeechLanguagePolicy.capabilities(for: config)
        let codes = capabilities.supportedLanguages.flatMap { $0.isEmpty ? nil : $0 }
        let info = ModelLanguageInfo(id: id, modelTitle: title, codes: codes, summary: capabilities.summary,
                                     ownedByMacOS: capabilities.manualControl == .locale,
                                     detectsAutomatically: capabilities.supportsAutomatic == true)
        cache[id] = info
        return info
    }

    /// Full names, the user's language and widely spoken languages first.
    @MainActor var names: [String] {
        guard let codes else { return [] }
        return SpeechLanguageList(codes: codes, preferredLanguage: ModelCatalogue.systemLanguage).names
    }

    /// Whether the tag opens the full list; one language or none has nothing to organize.
    var opensList: Bool { (codes?.count ?? 0) > 1 }

    var label: String {
        if let codes {
            if codes.count == 1 {
                // The name in its mid-sentence form ("Solo inglés"); only the tag's start is capitalized.
                return SpeechLanguagePolicy.startingWithCapital(
                    String(localized: "\(SpeechLanguagePolicy.languageName(codes[0])) only",
                           comment: "Tag on a speech model that recognizes one language, such as English only"))
            }
            return String(localized: "\(codes.count) languages",
                          comment: "Tag on a speech model: how many languages it recognizes")
        }
        if ownedByMacOS { return String(localized: "Languages set in macOS") }
        return detectsAutomatically ? String(localized: "Detects languages") : String(localized: "Languages unverified")
    }

    var symbol: String { "globe" }

    /// The tooltip: every language by name, or why there is no list.
    @MainActor var detail: String {
        if let codes {
            let names = names
            if codes.count == 1 { return String(localized: "Supports \(names[0]) only.") }
            return String(localized: "Supports \(names.count) languages: \(names.formatted(.list(type: .and)))")
        }
        if ownedByMacOS { return String(localized: "Uses the Apple Speech locale chosen in Speech options.") }
        return summary + " " + String(localized: "Airdraft has no complete language list for this model.")
    }
}

/// Presents a model's language sheet from the page, so a table row that scrolls
/// out of a virtualized list cannot dismiss it. Like `DismissAction`, it compares
/// equal: the page installs one action for its lifetime.
struct ShowModelLanguagesAction: Equatable {
    let present: @MainActor (ModelLanguageInfo) -> Void
    @MainActor func callAsFunction(_ info: ModelLanguageInfo) { present(info) }
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var showModelLanguages = ShowModelLanguagesAction { _ in }
}

/// The compact language tag in a model row. Clicking it opens the language
/// sheet and takes precedence over choosing the row's model.
struct ModelLanguageTag: View {
    @Environment(\.showModelLanguages) private var showLanguages
    let info: ModelLanguageInfo

    var body: some View {
        if info.opensList {
            Button { showLanguages(info) } label: { content }
                .buttonStyle(ModelLanguageTagStyle())
                .help(info.detail)
        } else {
            content
                .padding(.horizontal, 6)
                .frame(minHeight: 18)
                .background(SoftControl.shape.fill(Color.primary.opacity(0.05)))
                .help(info.detail)
        }
    }

    /// One line where it fits; a long label ("Idiomas definidos en macOS" at
    /// Larger text) wraps instead of widening the row past the window.
    private var content: some View {
        Text("\(Image(systemName: info.symbol)) \(info.label)")
            .appFont(.supporting, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
            .mutedForeground(0.75)
    }
}

/// A small raised tag that sinks while pressed, like the other soft controls.
private struct ModelLanguageTagStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background { SoftRaisedSurface(shape: SoftControl.shape, pressed: configuration.isPressed) }
            .contentShape(SoftControl.shape)
    }
}

/// Every language a model recognizes, organized: the user's own languages first,
/// then the rest A to Z, with a search field for long lists.
struct ModelLanguagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let info: ModelLanguageInfo
    @State private var query = ""

    private struct Language: Identifiable {
        let id: String
        let name: String
    }

    private var languages: [Language] {
        (info.codes ?? []).map { Language(id: $0, name: SpeechLanguagePolicy.languageLabel($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var userCodes: Set<String> {
        var codes = Set(Locale.preferredLanguages.compactMap(LocalSpeechRecommendation.normalized))
        if let system = LocalSpeechRecommendation.normalized(ModelCatalogue.systemLanguage) { codes.insert(system) }
        return codes
    }

    private static let shadowRoom: CGFloat = 12

    /// The policy's sentence when it already names the count (Qwen3-ASR's
    /// "30 languages."), otherwise the count tag followed by that sentence.
    private var subtitle: String {
        let count = (info.codes?.count ?? 0).formatted()
        return info.summary.contains(count) ? info.summary : info.label + " · " + info.summary
    }

    private var filtered: [Language] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return languages }
        return languages.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        let all = filtered
        let mine = all.filter { userCodes.contains($0.id) }
        VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.controlSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.modelTitle).appFont(.title, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle).supportingText()
                }
                Spacer(minLength: 0)
                if languages.count > 12 { SearchField(text: $query, placeholder: "Search languages") }
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.sectionTitleSpacing) {
                    if all.isEmpty {
                        EmptyNote("No languages match your search.")
                    }
                    if !mine.isEmpty { section("Your languages", mine) }
                    if !all.isEmpty { section(mine.isEmpty ? "All languages" : "All supported languages", all) }
                }
                // Room for the cards' light and shade, which the scroll view would clip.
                .padding(Self.shadowRoom)
            }
            .padding(-Self.shadowRoom)
            .frame(maxHeight: 360)
            .scrollBounceBehavior(.basedOnSize)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .primaryButtonStyle()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.pagePadding)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section(_ title: LocalizedStringResource, _ items: [Language]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appFont(.detail, weight: .semibold).foregroundStyle(.secondary)
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
