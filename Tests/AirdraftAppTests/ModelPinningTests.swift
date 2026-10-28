import AirdraftCore
import XCTest

/// AD-124: pinned speech models come first in their list, once, in the compact
/// set, the full list and a provider filter; search keeps the normal order.
@MainActor
final class ModelPinningTests: XCTestCase {
    private let shortlist = LocalModelShortlist.make(languageCode: "en", physicalMemory: 16 << 30)

    private func ids(_ items: [LocalModelItem]) -> [String] {
        items.compactMap { if case .model(let entry, _, _) = $0 { entry.id } else { nil } }
    }

    private func headers(_ items: [LocalModelItem]) -> [String: LocalModelItem.Header] {
        var headers: [String: LocalModelItem.Header] = [:]
        for case let .model(entry, header?, _) in items { headers[entry.id] = header }
        return headers
    }

    private func roles(_ items: [LocalModelItem]) -> [String: LocalModelShortlist.Role] {
        var roles: [String: LocalModelShortlist.Role] = [:]
        for case let .model(entry, _, role?) in items { roles[entry.id] = role }
        return roles
    }

    func testPinnedLocalModelsComeFirstOnceInEveryListAndSearchKeepsOrder() throws {
        let entries = ModelCatalogue.entries
        let experimental = try XCTUnwrap(entries.first { $0.tier == .experimental && !$0.retired })
        let retired = try XCTUnwrap(entries.first(where: \.retired))
        let recommended = try XCTUnwrap(shortlist.picks.first)
        let secondRecommended = try XCTUnwrap(shortlist.picks.dropFirst().first)
        let verified = try XCTUnwrap(entries.first { $0.tier == .verified && !shortlist.ids.contains($0.id) })
        let pinned: Set<String> = [experimental.id, retired.id, recommended.id, verified.id, "no-such-model"]

        // Compact set: Pinned first in catalogue order, then the rest of the
        // recommended set and Your models, without repeating a pinned row.
        do {
            let items = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [verified.id],
                                                  pinned: pinned, showsAll: false, expanded: false, searching: false)
            let listed = ids(items)
            let pinnedOrder = entries.map(\.id).filter { pinned.contains($0) }
            XCTAssertEqual(Array(listed.prefix(pinnedOrder.count)), pinnedOrder)
            XCTAssertEqual(listed.count, Set(listed).count, "Each model is listed once")
            XCTAssertFalse(listed.contains("no-such-model"))
            XCTAssertTrue(listed.contains(retired.id), "A pinned retired model stays listed")
            let headers = headers(items)
            XCTAssertEqual(headers[pinnedOrder[0]], .pinned)
            XCTAssertEqual(headers[secondRecommended.id], .recommended, "Recommended moves to the next unpinned pick")
            XCTAssertFalse(headers.values.contains(.yourModels), "A pinned model in use is not repeated under Your models")
            XCTAssertEqual(roles(items)[recommended.id], recommended.role, "A pinned pick keeps its label")
        }

        // Full list: pinned rows leave Verified and Experimental; the collapsed
        // disclosure counts only the Experimental rows it holds.
        do {
            let unpinned = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                                     showsAll: true, expanded: false, searching: false)
            let items = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                                  pinned: pinned, showsAll: true, expanded: false, searching: false)
            let listed = ids(items)
            XCTAssertEqual(listed.count, Set(listed).count)
            XCTAssertEqual(headers(items)[listed[0]], .pinned)
            func experimentalCount(_ items: [LocalModelItem]) -> Int? {
                items.lazy.compactMap { if case let .experimental(count, _, _, _) = $0 { count } else { nil } }.first
            }
            XCTAssertEqual(experimentalCount(items), try XCTUnwrap(experimentalCount(unpinned)) - 1)
            XCTAssertTrue(listed.contains(experimental.id), "A pinned Experimental model shows while collapsed")
        }

        // A provider filter: only that provider's pinned rows lead.
        do {
            let provider = verified.provider
            let filtered = entries.filter { $0.provider == provider }
            let items = ModelCatalogue.localItems(filtered, shortlist: shortlist, inUse: [],
                                                  pinned: pinned, showsAll: true, expanded: false, searching: false)
            let listed = ids(items)
            let expected = filtered.map(\.id).filter { pinned.contains($0) }
            XCTAssertFalse(expected.isEmpty)
            XCTAssertEqual(Array(listed.prefix(expected.count)), expected)
            XCTAssertTrue(listed.allSatisfy { id in filtered.contains { $0.id == id } })
        }

        // Search: normal order, no Pinned group.
        do {
            let plain = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                                  showsAll: true, expanded: false, searching: true)
            let items = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                                  pinned: [verified.id, experimental.id],
                                                  showsAll: true, expanded: false, searching: true)
            XCTAssertEqual(ids(items), ids(plain))
            XCTAssertFalse(headers(items).values.contains(.pinned))
        }
    }

    func testPinnedCloudModelsComeFirstInProviderOrderExceptWhileSearching() {
        let models = ["groq/a", "openai/b", "groq/c", "deepgram/d"]
        XCTAssertEqual(ModelCatalogue.pinnedFirst(models, pinned: ["groq/c", "deepgram/d", "gone/x"], searching: false) { $0 },
                       ["groq/c", "deepgram/d", "groq/a", "openai/b"])
        XCTAssertEqual(ModelCatalogue.pinnedFirst(models, pinned: ["groq/c"], searching: true) { $0 }, models)
        XCTAssertEqual(ModelCatalogue.pinnedFirst(models, pinned: [], searching: false) { $0 }, models)
    }

    func testPinsArePerContainerSettingsAndToggleOff() {
        let isolated = IsolatedContainer()
        defer { isolated.tearDown() }
        let settings = isolated.container.settings
        settings.setSpeechModel("sherpa:parakeet", pinned: true)
        XCTAssertTrue(settings.pinnedSpeechModels.contains("sherpa:parakeet"))
        settings.setSpeechModel("sherpa:parakeet", pinned: false)
        XCTAssertTrue(settings.pinnedSpeechModels.isEmpty)
    }
}
