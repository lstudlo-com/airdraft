// Compiled with AppUpdater.swift into an isolated app by verify-updater.py.
import AppKit
import Sparkle

@MainActor
final class Verification: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var controller: SPUStandardUpdaterController!
    var finished = false
    var failure: Error?
    var foundVersion: String?
    var cleanupFinished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                if CommandLine.arguments.last == "policy" {
                    try await verifyPolicy()
                } else if CommandLine.arguments.last == "installed" {
                    try require(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2", "Relaunch used the old version")
                    let service = AppUpdater { false }
                    service.start()
                    try require(service.isStarted && service.automaticallyChecksForUpdates && service.automaticallyDownloadsUpdates,
                                "Updater settings did not survive installation")
                } else if ["install", "tampered-download"].contains(CommandLine.arguments.last!) {
                    try await verifyInstallation()
                } else {
                    try await verifyFeed()
                }
                print("PASS: \(CommandLine.arguments.last!)")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard CommandLine.arguments.last == "install", !cleanupFinished else { return .terminateNow }
        // Exercise the same cancel-then-terminate handshake as Airdraft's
        // asynchronous model cleanup, without loading real models in this fixture.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            cleanupFinished = true
            print("PASS: asynchronous cleanup before installation")
            NSApp.terminate(nil)
        }
        return .terminateCancel
    }

    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "UpdaterVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    func verifyPolicy() async throws {
        var busy = false
        let service = AppUpdater { busy }
        try require(!service.isStarted && !service.canCheckForUpdates, "Updater started before app launch")
        service.start()
        try require(service.isStarted && service.startupError == nil, "Sparkle did not start")
        try require(service.canCheckForUpdates, "Idle app cannot check for updates")
        service.setAutomaticChecks(true)
        service.setAutomaticDownloads(true)
        try require(service.automaticallyChecksForUpdates && service.automaticallyDownloadsUpdates, "Settings did not refresh through KVO")
        try require(UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks"), "Automatic check preference was not persisted by Sparkle")
        try require(UserDefaults.standard.bool(forKey: "SUAutomaticallyUpdate"), "Automatic download preference was not persisted by Sparkle")
        service.setAutomaticChecks(false)
        service.setAutomaticDownloads(false)

        // A separate, unstarted controller supplies the delegate's updater argument.
        let dummy = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
        busy = true
        try require(!service.canCheckForUpdates, "Manual checks remain enabled during dictation")
        do {
            try service.updater(dummy, mayPerform: .updatesInBackground)
            throw NSError(domain: "UpdaterVerification", code: 2)
        } catch {
            try require((error as NSError).domain == "com.lightiichen.airdraft.updates", "Background check was not deferred")
        }
        let item = SUAppcastItem.empty()
        var resumed = 0
        try require(service.updater(dummy, shouldPostponeRelaunchForUpdate: item, untilInvokingBlock: { resumed += 1 }), "Busy restart was not deferred")
        try await Task.sleep(for: .milliseconds(350))
        try require(resumed == 0, "Restart interrupted dictation")
        busy = false
        try await Task.sleep(for: .milliseconds(350))
        try require(resumed == 1, "Restart did not resume exactly once")
        try require(!service.updater(dummy, shouldPostponeRelaunchForUpdate: item, untilInvokingBlock: { resumed += 1 }), "Idle restart was deferred")
        busy = true
        _ = service.updater(dummy, shouldPostponeRelaunchForUpdate: item, untilInvokingBlock: { resumed += 1 })
        service.updater(dummy, didAbortWithError: NSError(domain: "test", code: 1))
        busy = false
        try await Task.sleep(for: .milliseconds(350))
        try require(resumed == 1, "Canceled update still restarted")
    }

    func verifyFeed() async throws {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        try controller.updater.start()
        controller.updater.checkForUpdateInformation()
        let deadline = Date().addingTimeInterval(15)
        while !finished && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        try require(finished, "Feed check timed out")
        if CommandLine.arguments.last == "valid-feed" {
            try require(failure == nil && foundVersion == "2", "Signed update feed was not accepted: \(String(describing: failure))")
        } else {
            try require(failure != nil && foundVersion == nil, "Tampered update feed was accepted")
        }
    }

    func verifyInstallation() async throws {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        try controller.updater.start()
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = true
        controller.updater.checkForUpdatesInBackground()
        let deadline = Date().addingTimeInterval(30)
        // A completed cycle can mean "ready to install on quit". In that case
        // keep the process alive until the delegate's normal termination finishes.
        while (CommandLine.arguments.last == "install" ? failure == nil : !finished) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        if CommandLine.arguments.last == "tampered-download" {
            try require(finished && containsValidationError(failure as NSError?), "Tampered archive was not rejected by signature validation: \(String(describing: failure))")
        } else {
            throw NSError(domain: "UpdaterVerification", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Update did not install on quit: \(String(describing: failure))"])
        }
    }

    func containsValidationError(_ error: NSError?) -> Bool {
        guard let error else { return false }
        if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.validationError.rawValue) { return true }
        return containsValidationError(error.userInfo[NSUnderlyingErrorKey] as? NSError)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        if CommandLine.arguments.last == "install" {
            print("PASS: downloaded and verified update; installing on quit")
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return false
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { foundVersion = item.versionString }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        failure = error
        finished = true
    }
}

@main
enum UpdaterVerification {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = Verification()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
