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
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "airdraft.models-performance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); active = false }
        let settings = AppSettings(defaults: defaults)
        settings.llm.select(.none)
        let container = AppContainer(settings: settings, dataDirectory: directory.appendingPathComponent("data"))
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
                    "catalogueRows": ModelCatalogue.entries.count]
                results.append(result)
                if ProcessInfo.processInfo.environment["AIRDRAFT_RENDER_VERIFY_MODEL_LAZINESS"] == "1" {
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
        print("MODELS_PERFORMANCE \(results)")
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
    }

    private static func nativeTables(_ view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(nativeTables)
    }
}
#endif
