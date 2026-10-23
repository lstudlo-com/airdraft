#if DEBUG
import AirdraftCore
import AppKit
import SwiftUI

/// Production navigation with disposable data, no model loads or credential reads.
@MainActor
enum ModelsPerformanceVerification {
    private static var active = false
    private static var rows = Set<String>()
    private static var measuringViewport = false
    private static var viewportHeight: CGFloat = 0
    static func noteRow(_ id: String) { if active { rows.insert(id) } }
    static func noteViewport(_ height: CGFloat) { if measuringViewport { viewportHeight = height } }

    static func run(to directory: URL) {
        precondition(LocalE2E.isActive, "Use --e2e-local <disposable directory>")
        let ids = Set(ModelCatalogue.entries.map(\.id))
        let unknown = Set(ModelCatalogue.verificationEvidence.keys).subtracting(ids)
        precondition(unknown.isEmpty, "Verification evidence names unknown models: \(unknown.sorted())")
        verifyShortlists(ids)
        let laziness = ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_VERIFY_MODEL_LAZINESS"] == "1"
        // Laziness is measured over the whole catalogue, so show all models and
        // open the Experimental group. Otherwise Models opens with its compact set.
        if laziness { setenv("AIRDRAFT_RENDER_SHOW_EXPERIMENTAL", "1", 1) }
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "airdraft.models-performance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); active = false }
        let settings = AppSettings(defaults: defaults)
        settings.llm.select(.none)
        settings.showsAllLocalModels = laziness
        let container = AppContainer(settings: settings, dataDirectory: directory.appendingPathComponent("data"))
        // The shortlist plus the app default and any models in the disposable model root.
        let installed = ModelCatalogue.entries.filter { $0.isDownloadable && LocalModels.isInstalled($0.config(from: settings.asr)) }
        let compactLimit = ModelCatalogue.shortlist.picks.count + 1 + installed.count
        var results: [[String: Any]] = []
        for height in [600.0, 1000.0] {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                container.navigation.page = .home
                let host = NSHostingView(rootView: MainWindowView().environment(container))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 784, height: height),
                                      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                var timings: [Double] = []
                var counts: [Int] = []
                for _ in 0..<5 {
                    container.navigation.page = .home
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    rows = []
                    active = true
                    let started = ProcessInfo.processInfo.systemUptime
                    container.navigation.page = .models
                    host.layoutSubtreeIfNeeded()
                    let layoutMs = (ProcessInfo.processInfo.systemUptime - started) * 1000
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    host.layoutSubtreeIfNeeded()
                    active = false
                    timings.append(layoutMs)
                    counts.append(rows.count)
                }
                let result: [String: Any] = ["appearance": name, "height": height,
                    "layoutMs": timings, "materializedLocalRows": counts,
                    "catalogueRows": ModelCatalogue.entries.count, "showsAllLocalModels": laziness]
                results.append(result)
                if !laziness {
                    precondition(counts.allSatisfy { $0 > 0 && $0 <= compactLimit },
                                 "Models must open with the compact recommended set: \(counts)")
                }
                if laziness {
                    precondition(counts.allSatisfy { $0 > 0 && $0 < ModelCatalogue.entries.count / 2 },
                                 "Models must not materialize the entire catalogue on navigation")
                    let table = nativeTables(host).first { $0.numberOfRows > 6 }!
                    rows = []
                    active = true
                    table.scrollRowToVisible(table.numberOfRows - 1)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    host.layoutSubtreeIfNeeded()
                    active = false
                    precondition(rows.contains(ModelCatalogue.entries.last!.id), "The last model must be rendered when scrolling to the end")
                    table.scrollRowToVisible(0)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                }
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(
                        to: directory.appendingPathComponent("models-\(name)-\(Int(height)).png"))
                }
                window.orderOut(nil)
                window.contentView = nil
            }
        }
        try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("models-performance.json"))
        verifyShortTables()
        // The in-use checks start from the default, collapsed page.
        unsetenv("AIRDRAFT_RENDER_SHOW_EXPERIMENTAL")
        verifyKeptExperimental(directory)
        print("MODELS_PERFORMANCE \(results)")
    }

    /// AD-071: every language and memory case opens with a few verified
    /// models from the catalogue, the recommendation first.
    private static func verifyShortlists(_ ids: Set<String>) {
        let entries = Dictionary(uniqueKeysWithValues: ModelCatalogue.entries.map { ($0.id, $0) })
        for language in ["zh-Hant-TW", "zh-Hans", "en-US", "ja-JP", "ko-KR", "fr-FR", "de", "th", "ar", ""] {
            for gigabytes in [4, 8, 16, 64] as [UInt64] {
                let shortlist = LocalModelShortlist.make(languageCode: language, physicalMemory: gigabytes << 30)
                precondition((1...3).contains(shortlist.picks.count) && shortlist.picks.first?.role == .recommended)
                for id in shortlist.ids {
                    precondition(entries[id]?.tier == .verified, "Shortlist \(language) \(gigabytes) GB names \(id), which is not a Verified model")
                }
            }
        }
        print("MODELS_SHORTLIST PASS")
    }

    private static func modelIDs(_ items: [LocalModelItem]) -> [String] {
        items.compactMap { if case let .model(entry, _, _) = $0 { entry.id } else { nil } }
    }

    /// AD-071: the compact set and a collapsed Experimental group still list
    /// the models in use.
    private static func verifyKeptExperimental(_ directory: URL) {
        let entries = ModelCatalogue.entries
        let shortlist = ModelCatalogue.shortlist
        let selected = entries.first { $0.id == "sherpa:parakeet" }!
        let downloading = entries.first { $0.id == "cohere" }!
        precondition(selected.tier == .experimental && downloading.tier == .experimental)
        let experimental = entries.filter { $0.tier == .experimental }.map(\.id)
        func kept(_ items: [LocalModelItem]) -> Int? {
            items.lazy.compactMap { if case let .experimental(_, kept, _, _) = $0 { kept } else { nil } }.first
        }
        let keep: Set = [selected.id, downloading.id]
        // Compact: the shortlist, then the models in use, each once; no Experimental group.
        let compact = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: keep.union(shortlist.ids.prefix(1)),
                                                showsAll: false, expanded: false, searching: false)
        precondition(modelIDs(compact) == shortlist.ids + entries.map(\.id).filter(keep.contains) && kept(compact) == nil,
                     "The compact set must list the shortlist and then the models in use once")
        precondition(modelIDs(ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                                        showsAll: false, expanded: false, searching: false)) == shortlist.ids)
        // Searching always searches the whole catalogue, except retired entries
        // nobody uses; a retired entry in use is listed like any other.
        let offered = ModelCatalogue.offered(entries, inUse: []).map(\.id)
        let retired = entries.filter(\.retired).map(\.id)
        precondition(retired == ["sherpa:senseVoice"] && Set(offered).isDisjoint(with: retired))
        let searching = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                                  showsAll: false, expanded: false, searching: true)
        precondition(modelIDs(searching).sorted() == offered.sorted(), "Search must include every offered model")
        let retiredInUse = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: Set(retired),
                                                     showsAll: false, expanded: false, searching: false)
        precondition(modelIDs(retiredInUse) == shortlist.ids + retired, "A retired model in use must stay listed")
        let hidden = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: [],
                                               showsAll: true, expanded: false, searching: false)
        precondition(Set(modelIDs(hidden)).isDisjoint(with: experimental) && kept(hidden) == 0)
        precondition(Array(modelIDs(hidden).prefix(shortlist.ids.count)) == shortlist.ids)
        let collapsed = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: keep,
                                                  showsAll: true, expanded: false, searching: false)
        let collapsedIDs = modelIDs(collapsed)
        precondition(Set(collapsedIDs).intersection(experimental) == keep && kept(collapsed) == 2
                     && collapsedIDs.count == Set(collapsedIDs).count, "In-use Experimental models must stay listed once")
        let expanded = ModelCatalogue.localItems(entries, shortlist: shortlist, inUse: keep,
                                                 showsAll: true, expanded: true, searching: false)
        precondition(modelIDs(expanded).sorted() == offered.sorted() && kept(expanded) == 0)

        // The production page keeps the app default and a running download visible.
        let suite = "airdraft.models-kept.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.llm.select(.none)
        selected.select(&settings.asr)
        let container = AppContainer(settings: settings, dataDirectory: directory.appendingPathComponent("kept-data"))
        container.downloads.setPreviewProgress(.init(fraction: 0.4, currentFile: "model.safetensors"),
                                               for: downloading.config(from: settings.asr))
        container.navigation.page = .models
        precondition(!settings.showsAllLocalModels, "Models must open with the compact set")
        rows = []
        active = true
        let host = NSHostingView(rootView: MainWindowView().environment(container))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 784, height: 1000),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        active = false
        precondition(rows.isSuperset(of: keep.union(shortlist.ids)) && rows.count < entries.count / 2,
                     "Compact Models must list the shortlist plus the selected and downloading models: \(rows.sorted())")
        // The full list is remembered and still keeps in-use Experimental models.
        settings.showsAllLocalModels = true
        precondition(AppSettings(defaults: defaults).showsAllLocalModels, "Show All Models must be remembered")
        window.setContentSize(NSSize(width: 784, height: 600))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let table = nativeTables(host).first { $0.numberOfRows > 6 }!
        precondition(table.numberOfRows < expanded.count, "Experimental models must start collapsed")
        rows = []
        active = true
        for row in 0..<table.numberOfRows {
            table.scrollRowToVisible(row)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        }
        active = false
        precondition(rows.isSuperset(of: keep), "Collapsed Models must list the selected and downloading models")
        window.orderOut(nil)
        window.contentView = nil
        print("MODELS_KEPT_EXPERIMENTAL PASS rows=\(table.numberOfRows) expanded=\(expanded.count)")
    }

    private static func verifyShortTables() {
        for count in [0, 1, 3, 92] {
            measuringViewport = true
            viewportHeight = 0
            let host = NSHostingView(rootView: ModelTable(cost: "Storage", rowCount: count) {
                if count == 0 { Text("No models").padding(Theme.cardPadding) }
                ForEach(0..<count, id: \.self) { index in Text("Model \(index)").frame(height: 64) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 536, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            let height = viewportHeight
            measuringViewport = false
            precondition(height > 0 && height <= Theme.modelTableMaxHeight + 1)
            precondition(count == 92 ? abs(height - Theme.modelTableMaxHeight) < 1 : height < Theme.modelTableMaxHeight)
            window.contentView = nil
        }
        // AD-071: the compact recommended set shows all of its rows without an inner scroll.
        measuringViewport = true
        viewportHeight = 0
        let host = NSHostingView(rootView: ModelTable(cost: "Storage", rowCount: 5, capped: false) {
            ForEach(0..<5, id: \.self) { index in Text("Model \(index)").frame(height: 100) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 536, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        measuringViewport = false
        precondition(abs(viewportHeight - 500) < 1, "The compact set must not scroll inside the table: \(viewportHeight)")
        window.contentView = nil
    }

    private static func nativeTables(_ view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(nativeTables)
    }
}
#endif
