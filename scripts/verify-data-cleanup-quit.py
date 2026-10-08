#!/usr/bin/env python3
"""Exercise modal quit with the production window policy and app delegate.

All app services are disposable doubles. No user data, keys, models, microphone,
clipboard or system preferences are accessed. The fixture stays offscreen and
checks the modal policy before requesting quit, so regressions cannot beep.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]

FIXTURE = r'''
import AppKit
import SwiftUI

@MainActor final class CleanupFixture {
    var isRunning = false
    var finishedScope: String?
}
@MainActor final class PipelineFixture {
    var hasRecoverableRecording = false
    var historyStorageError: String?
    var isBusy = false
    var isMaintainingData = false
    func cancel() {}
}
@MainActor final class StoreFixture { var persistenceError: String? }
@MainActor final class DownloadsFixture {
    var isBusy = false
    func cancelAll() {}
}
@MainActor final class MediaFixture { func cancel() {} }
@MainActor final class MeetingFixture {
    var isBusy = false
    var shutdownCalls = 0
    func prepareForQuit() async { shutdownCalls += 1; await Task.yield() }
}
@MainActor final class ModelsFixture {
    var shutdownCalls = 0
    func shutdown() async { shutdownCalls += 1; await Task.yield() }
}
@MainActor final class UpdaterFixture { func start() {} }
@MainActor final class AppContainer {
    static let shared = AppContainer()
    var dataLease: Int? = 1
    let cleanup = CleanupFixture()
    let pipeline = PipelineFixture()
    let dictionary = StoreFixture()
    let profiles = StoreFixture()
    let downloads = DownloadsFixture()
    let models = ModelsFixture()
    var media: MediaFixture? = nil
    var meeting: MeetingFixture? = MeetingFixture()
    let updates = UpdaterFixture()
    var shutdownCalls = 0
    func beginShutdown() { shutdownCalls += 1 }
    func start() {}
    func showMainWindow() {}
}

@MainActor final class QuitFixtureDelegate: NSObject, NSApplicationDelegate {
    private let production = AppDelegate()
    private var parent: NSWindow!
    private var sheet: NSWindow!
    private var host: NSHostingView<AnyView>!

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        production.applicationShouldTerminate(sender)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = AppContainer.shared
        if CommandLine.arguments.contains("unavailable") {
            app.dataLease = nil
            app.pipeline.historyStorageError = "Database was never opened"
            app.pipeline.isMaintainingData = true
            app.pipeline.isBusy = true
        } else if CommandLine.arguments.contains("reset") {
            app.cleanup.finishedScope = "reset"
            app.pipeline.historyStorageError = "Database intentionally closed"
        }
        let frame = NSRect(x: -10_000, y: -10_000, width: 320, height: 160)
        parent = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        sheet = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        sheet.isReleasedWhenClosed = false
        host = NSHostingView(rootView: AnyView(DataCleanupSheetWindow(isRunning: false)))
        sheet.contentView = host
        parent.orderFront(nil)
        parent.beginSheet(sheet)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !sheet.preventsApplicationTerminationWhenModal else {
                print("FAIL: idle recovery sheet blocks Quit before the app delegate")
                exit(1)
            }
            app.cleanup.isRunning = true
            host.rootView = AnyView(DataCleanupSheetWindow(isRunning: true))
            try? await Task.sleep(for: .milliseconds(100))
            guard sheet.preventsApplicationTerminationWhenModal,
                  applicationShouldTerminate(NSApp) == .terminateCancel,
                  app.shutdownCalls == 0 else {
                print("FAIL: active data removal must prevent shutdown")
                exit(1)
            }
            app.cleanup.isRunning = false
            host.rootView = AnyView(DataCleanupSheetWindow(isRunning: false))
            try? await Task.sleep(for: .milliseconds(100))
            guard !sheet.preventsApplicationTerminationWhenModal else {
                print("FAIL: a finished or failed cleanup must allow Quit again")
                exit(1)
            }
            NSApp.terminate(nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            print("FAIL: modal Quit did not finish through the production delegate")
            exit(1)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let app = AppContainer.shared
        guard app.shutdownCalls == 1, app.models.shutdownCalls == 1,
              app.meeting?.shutdownCalls == 1 else {
            print("FAIL: Quit must finish model and meeting shutdown exactly once")
            exit(1)
        }
        print("PASS: \(CommandLine.arguments.last!) modal Quit; active cleanup fenced; shutdown completed")
    }
}

@main struct QuitCheck {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = QuitFixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy", action="store_true", help="Require the former modal policy to fail without requesting Quit")
    args = parser.parse_args()
    delegate = (REPO / "Sources/App/App/AirdraftApp.swift").read_text().split("@main\nstruct AirdraftApp", 1)[0]
    delegate = delegate.replace("import AirdraftCore\n", "").replace(".reset", '"reset"')
    policy = (REPO / "Sources/App/Views/DataCleanupSheetWindow.swift").read_text()
    if args.legacy:
        policy = policy.replace("window?.preventsApplicationTerminationWhenModal = isRunning", "// Former default modal policy")
    with tempfile.TemporaryDirectory(prefix="airdraft-quit-check-") as temporary:
        root = Path(temporary)
        source = root / "QuitCheck.swift"
        binary = root / "QuitCheck"
        source.write_text(policy + "\n" + delegate + "\n" + FIXTURE)
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(binary)], check=True)
        for scenario in ("unavailable", "interrupted", "reset"):
            result = subprocess.run([str(binary), scenario], text=True, capture_output=True, timeout=10)
            print(result.stdout.strip())
            if args.legacy:
                if result.returncode != 1 or "idle recovery sheet blocks Quit" not in result.stdout:
                    raise SystemExit("Legacy negative check did not fail at the expected modal boundary")
            elif result.returncode != 0 or "PASS:" not in result.stdout:
                print(result.stderr)
                raise SystemExit(result.returncode or 1)
        if args.legacy:
            print("PASS: all three former modal-policy cases fail before requesting Quit or making sound")


if __name__ == "__main__":
    main()
