#!/usr/bin/env swift
import AppKit
import Darwin
import Foundation

// Run without arguments to reset this user's Accessibility grants and remove
// Airdraft app bundles. --dry-run only lists the actions.
private let currentBundleIDs = [
    "com.lstudlo.app.airdraft",
    "com.lstudlo.app.airdraft.debug",
]
private let legacyBundleID = "com.lightiichen.transcribar"
private let allBundleIDs = Set(currentBundleIDs + [legacyBundleID])
private let fileManager = FileManager.default
private let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL

private func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
}

private let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    print("Usage: swift scripts/purge-airdraft-apps.swift [--dry-run]")
    print("Resets this user's Airdraft Accessibility permissions and removes verified app bundles.")
    exit(0)
}
guard arguments.isEmpty || arguments == ["--dry-run"] else {
    fail("Unknown option. Use --help for usage.")
}
guard geteuid() != 0 else {
    fail("Run as your normal user, without sudo; sudo changes the scope of macOS privacy resets.")
}
private let dryRun = arguments == ["--dry-run"]

private func output(of executable: String, arguments: [String]) -> (status: Int32, text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
        return (-1, error.localizedDescription)
    }
}

private func bundleID(at url: URL) -> String? {
    guard url.pathExtension.lowercased() == "app" else { return nil }
    return Bundle(url: url)?.bundleIdentifier
}

private func scanApps(in root: URL, into candidates: inout Set<URL>) {
    guard let enumerator = fileManager.enumerator(at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
    for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
        enumerator.skipDescendants()
        candidates.insert(url.standardizedFileURL)
    }
}

private func scanXcodeProducts(into candidates: inout Set<URL>) {
    let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
    guard let projects = try? fileManager.contentsOfDirectory(at: derivedData,
        includingPropertiesForKeys: [.isDirectoryKey]) else { return }
    for project in projects {
        let products = project.appendingPathComponent("Build/Products")
        guard let configurations = try? fileManager.contentsOfDirectory(at: products,
            includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
        for configuration in configurations {
            guard let entries = try? fileManager.contentsOfDirectory(at: configuration,
                includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for app in entries where app.pathExtension.lowercased() == "app" {
                candidates.insert(app.standardizedFileURL)
            }
        }
    }
}

private func isLocalCopy(_ url: URL) -> Bool {
    let resolved = url.resolvingSymlinksInPath()
    let path = resolved.path
    let local = path.hasPrefix("/Applications/") || path.hasPrefix(home.path + "/")
    let cloud = path.hasPrefix(home.path + "/Library/CloudStorage/") ||
                path.hasPrefix(home.path + "/Library/Mobile Documents/")
    let trashed = path.contains("/.Trash/")
    let nestedApp = resolved.deletingLastPathComponent().pathComponents.contains {
        $0.lowercased().hasSuffix(".app")
    }
    return local && !cloud && !trashed && !nestedApp
}

private var candidates = Set<URL>()
scanApps(in: URL(fileURLWithPath: "/Applications"), into: &candidates)
scanApps(in: home.appendingPathComponent("Applications"), into: &candidates)
scanXcodeProducts(into: &candidates)

let query = (currentBundleIDs + [legacyBundleID])
    .map { "kMDItemCFBundleIdentifier == \"\($0)\"" }
    .joined(separator: " || ")
let spotlight = output(of: "/usr/bin/mdfind", arguments: [query])
guard spotlight.status == 0 else {
    fail("Spotlight discovery failed before any changes: \(spotlight.text)")
}
for line in spotlight.text.split(separator: "\n") {
    candidates.insert(URL(fileURLWithPath: String(line)).standardizedFileURL)
}

private var apps: [(url: URL, id: String)] = []
private var skipped: [URL] = []
for url in candidates.sorted(by: { $0.path < $1.path }) {
    guard fileManager.fileExists(atPath: url.path),
          let id = bundleID(at: url), allBundleIDs.contains(id) else { continue }
    let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    if isLink || !isLocalCopy(url) {
        skipped.append(url)
    } else {
        apps.append((url, id))
    }
}

let installedIDs = Set(apps.map(\.id))
let running = allBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
print("Airdraft app bundles found: \(apps.count)")
for app in apps { print("  \(app.url.path) [\(app.id)]") }
for url in skipped { print("  Skipped nonlocal or linked copy: \(url.path)") }
if dryRun {
    print("Would quit \(running.count) running Airdraft process(es).")
    print("Would reset Accessibility for both current bundle IDs and any installed legacy bundle ID.")
    print("Would remove the \(apps.count) app bundle(s) listed above. No changes made.")
    exit(0)
}

for app in running {
    guard app.terminate() else { fail("Could not quit \(app.localizedName ?? app.bundleIdentifier ?? "Airdraft").") }
}
let deadline = Date().addingTimeInterval(10)
while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}
guard running.allSatisfy(\.isTerminated) else {
    fail("Airdraft is still running. Quit it normally and rerun the script.")
}

for id in currentBundleIDs + (installedIDs.contains(legacyBundleID) ? [legacyBundleID] : []) {
    let result = output(of: "/usr/bin/tccutil", arguments: ["reset", "Accessibility", id])
    if result.status == 0 {
        print("Reset Accessibility: \(id)")
    } else if installedIDs.contains(id) {
        fail("Accessibility reset failed for \(id): \(result.text). App bundles were not removed.")
    } else {
        print("No registered \(id) app to reset: \(result.text)")
    }
}

for app in apps {
    guard bundleID(at: app.url) == app.id else {
        fail("Bundle identity changed before deletion: \(app.url.path)")
    }
    do {
        try fileManager.removeItem(at: app.url)
        print("Removed: \(app.url.path)")
    } catch {
        fail("Could not remove \(app.url.path): \(error.localizedDescription)")
    }
}

print("Done. Settings, models, history, and Keychain credentials were left untouched.")
print("If an older path-based entry remains in System Settings → Privacy & Security → Accessibility, remove it there with the minus button.")
