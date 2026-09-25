#if DEBUG
import AirdraftCore
import Foundation

/// Sample data for Xcode previews. Nothing here reads or writes the user's
/// settings, history or Keychain.
@MainActor
enum PreviewData {
    /// A container whose history lives in a throwaway directory.
    static let container: AppContainer = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("airdraft-preview-\(UUID().uuidString)", isDirectory: true)
        if let store = try? HistoryStore(directory: dir) { seed(store) }
        let defaults = UserDefaults(suiteName: "airdraft.preview.\(UUID().uuidString)")!
        return AppContainer(settings: AppSettings(defaults: defaults), dataDirectory: dir)
    }()

    /// The Home overview for sample history, computed by the real query.
    static func overview(days: Int? = nil) -> HistoryStore.Overview {
        guard let store = try? HistoryStore(inMemory: true) else { return .empty }
        seed(store)
        return (try? store.overview(days: days)) ?? .empty
    }

    private static let apps: [(id: String, name: String)] = [
        ("com.apple.Notes", "Notes"),
        ("com.apple.mail", "Mail"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.dt.Xcode", "Xcode"),
    ]

    private static let phrases = [
        "Let's move the review to Thursday afternoon so the design team can join.",
        "Quick note: the build passes locally, but the release gate still needs the signed DMG.",
        "Thanks for the draft. I left a few comments on the pricing section and the hero copy.",
        "Remember to check the microphone route after the dock reconnects.",
        "Can you send me the latest numbers before the call? I want to compare them with last week.",
    ]

    private static func seed(_ store: HistoryStore) {
        let now = Date()
        for index in 0..<42 {
            // Mostly recent, with a few older days, a streak and some long dictations.
            let daysAgo = Double(index / 6) + (index % 6 == 0 ? 0.5 : 0)
            let app = apps[(index * 7 + index / 3) % apps.count]
            let repeats = 1 + (index * 5) % 4 + (index % 9 == 0 ? 5 : 0)
            let text = Array(repeating: phrases[index % phrases.count], count: repeats).joined(separator: " ")
            let words = text.split(separator: " ").count
            try? store.save(DictationRecord(
                createdAt: now.addingTimeInterval(-daysAgo * 86_400 - Double(index) * 600),
                appBundleId: app.id, appName: app.name, mode: "Clean", family: "document",
                rawTranscript: text, refinedText: text, finalText: text, asrEngine: "preview",
                audioSeconds: Double(words) / Double(110 + (index * 13) % 70) * 60,
                asrMs: 400 + index * 11, llmMs: 900 + index * 23, inserted: true
            ))
        }
    }
}
#endif
