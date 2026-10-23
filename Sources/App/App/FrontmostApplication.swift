import AppKit
import Observation

/// The app a dictation started now would go to: the frontmost app other than
/// Airdraft. Only its bundle ID and name are read, for the labels that show an
/// automatic profile (AD-080). The pipeline resolves its own destination when a
/// recording starts; this never decides what a dictation uses.
@MainActor
@Observable
final class FrontmostApplication {
    struct App: Equatable {
        let bundleID: String
        let name: String
    }

    private(set) var current: App?
    @ObservationIgnored private var observer: NSObjectProtocol?
    #if DEBUG
    @ObservationIgnored private var isOverridden = false
    #endif

    init() {
        current = Self.read(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                #if DEBUG
                if self.isOverridden { return }
                #endif
                let next = Self.read(app)
                if next != self.current { self.current = next }
            }
        }
    }

    private static func read(_ app: NSRunningApplication?) -> App? {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return nil }
        return App(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }

    #if DEBUG
    /// Fixtures name the frontmost app instead of following real activation.
    func override(_ app: App?) {
        isOverridden = true
        current = app
    }
    #endif
}

/// Names and icons for apps a rule names by bundle ID. Launch Services lookups
/// only, cached per bundle ID; no app content is read.
@MainActor
enum InstalledApplications {
    struct Entry {
        let name: String?
        let icon: NSImage?
    }

    private static var cache: [String: Entry] = [:]

    static func entry(for bundleID: String) -> Entry {
        if let cached = cache[bundleID] { return cached }
        let entry: Entry
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            entry = Entry(name: displayName(of: url), icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            entry = Entry(name: nil, icon: nil)
        }
        cache[bundleID] = entry
        return entry
    }

    static func displayName(of url: URL) -> String {
        let bundle = Bundle(url: url)
        let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        return name ?? url.deletingPathExtension().lastPathComponent
    }

    /// Regular apps that are running now, other than Airdraft, by name.
    static func running() -> [FrontmostApplication.App] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app -> FrontmostApplication.App? in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                  seen.insert(bundleID).inserted else { return nil }
            return FrontmostApplication.App(bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
