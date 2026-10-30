import AppKit
import AirdraftCore
import Observation

/// Settings > Appearance > Language (AD-137). The choice lives where macOS keeps an
/// app's own language, so System Settings' per-app choice and this one agree. The
/// running interface keeps the language it launched with until Airdraft relaunches.
@MainActor @Observable final class InterfaceLanguageStore {
    struct Storage {
        var read: () -> [String]?
        var write: ([String]?) -> Void
        /// The Mac's languages, which System Default follows.
        var system: () -> [String]
    }

    private let storage: Storage
    /// The localization this launch shows.
    let launchLanguage: String
    /// nil follows the Mac.
    private(set) var selection: InterfaceLanguage?

    init(storage: Storage, launchLanguage: String = Bundle.main.preferredLocalizations.first ?? "en") {
        self.storage = storage
        self.launchLanguage = launchLanguage
        selection = InterfaceLanguage.choice(forStored: storage.read())
    }

    /// The localization the next launch shows.
    var nextLaunchLanguage: String {
        InterfaceLanguage.resolved(selection.map { [$0.code] } ?? storage.system())
    }

    var needsRelaunch: Bool { nextLaunchLanguage != launchLanguage }

    func select(_ language: InterfaceLanguage?) {
        guard language != selection else { return }
        selection = language
        storage.write(language.map { [$0.code] })
    }
}

/// Settings' Relaunch: quit through the normal path (its unfinished-work alert and
/// model shutdown included), then open this bundle again once the process is gone.
@MainActor enum AppRelaunch {
    private(set) static var isRequested = false

    static func request() {
        isRequested = true
        NSApp.terminate(nil)
    }

    /// A quit that stops without terminating (Keep Open, running cleanup) relaunches nothing later.
    static func cancel() { isRequested = false }

    /// From `applicationWillTerminate`: a detached shell waits up to ten seconds for
    /// this process to exit before opening the bundle, so the new copy never meets
    /// the old one's data lease. A quit that hangs past that relaunches nothing.
    static func launchHelperIfRequested() {
        guard isRequested else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", """
            i=0; while [ "$i" -lt 100 ]; do
              /bin/kill -0 "$0" 2>/dev/null || exec /usr/bin/open "$1"
              i=$((i + 1)); /bin/sleep 0.1
            done
            """, String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        try? helper.run()
    }
}

extension InterfaceLanguageStore.Storage {
    /// `AppleLanguages` in Airdraft's own preferences domain, never the global one.
    static var appDomain: Self {
        Self(
            read: {
                CFPreferencesCopyValue(InterfaceLanguage.preferenceKey as CFString, kCFPreferencesCurrentApplication,
                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
            },
            write: { languages in
                CFPreferencesSetValue(InterfaceLanguage.preferenceKey as CFString, languages as CFPropertyList?,
                                      kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            },
            system: { SystemLanguages.preferred })
    }

    /// Isolated containers (renders, fixtures, tests) never touch the real preference.
    /// System Default resolves to the launch language, so no relaunch is offered.
    static func memory(launchLanguage: String = Bundle.main.preferredLocalizations.first ?? "en",
                       stored: [String]? = nil) -> Self {
        final class Box { var languages: [String]? }
        let box = Box()
        box.languages = stored
        return Self(read: { box.languages }, write: { box.languages = $0 }, system: { [launchLanguage] })
    }
}
