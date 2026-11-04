import AirdraftCore
import SwiftUI

/// A speech model's languages as the Models table shows them (AD-122): one compact
/// tag with the complete list in its tooltip, and the organized list in the row's
/// info sheet (AD-145). Local and
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

    /// Whether the info sheet lists languages; one language or none has nothing to organize.
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

/// The compact language tag in a model row (AD-122). A label, not a control:
/// the row's info button (AD-145) opens the full list for every model.
struct ModelLanguageTag: View {
    let info: ModelLanguageInfo

    var body: some View {
        // One line where it fits; a long label ("Idiomas definidos en macOS" at
        // Larger text) wraps instead of widening the row past the window.
        Text("\(Image(systemName: info.symbol)) \(info.label)")
            .appFont(.supporting, weight: .medium)
            .fixedSize(horizontal: false, vertical: true)
            .mutedForeground(0.75)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(SoftControl.shape.fill(Color.primary.opacity(0.05)))
            .help(info.detail)
    }
}
