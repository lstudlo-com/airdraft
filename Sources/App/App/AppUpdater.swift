import AppKit
import Combine
import Observation
import Sparkle
import os

/// Owns Sparkle's lifetime. Sparkle owns persistence and scheduling; these
/// observed values only keep SwiftUI in sync with its settings and dialogs.
@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    // The updater fixture compiles this file independently of AirdraftCore.
    private static let log = Logger(subsystem: "com.lightiichen.airdraft", category: "updates")

    private(set) var isStarted = false
    private(set) var startupError: String?
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var lastCheckedAt: Date?
    private var sparkleCanCheck = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var observations = Set<AnyCancellable>()
    @ObservationIgnored private var pendingRelaunch: Task<Void, Never>?
    @ObservationIgnored private let isDictating: @MainActor () -> Bool

    init(isDictating: @escaping @MainActor () -> Bool) {
        self.isDictating = isDictating
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.sparkleCanCheck = $0 }.store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }.store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }.store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] in self?.lastCheckedAt = $0 }.store(in: &observations)
    }

    var canCheckForUpdates: Bool { isStarted && sparkleCanCheck && !isDictating() }

    var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }

    /// Called only on a normal app launch, never by offscreen renders or self-tests.
    func start() {
        guard Bundle.main.bundleIdentifier != "com.lstudlo.app.airdraft.debug" else {
            startupError = "Development builds do not install public releases."
            return
        }
        guard !isStarted else { return }
        do {
            try controller.updater.start()
            isStarted = true
            startupError = nil
            Self.log.notice("updater started")
        } catch {
            startupError = "Updates are unavailable in this build."
            Self.log.error("updater could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !isDictating() else {
            throw NSError(domain: "com.lightiichen.airdraft.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Finish dictating before checking for updates."])
        }
    }

    /// A download can finish after a new dictation starts. Defer the restart
    /// until its text has been inserted; AppDelegate still performs model cleanup.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isDictating() else { return false }
        pendingRelaunch?.cancel()
        pendingRelaunch = Task { [weak self] in
            while let self, self.isDictating(), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, self != nil else { return }
            installHandler()
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pendingRelaunch?.cancel()
        pendingRelaunch = nil
    }
}
