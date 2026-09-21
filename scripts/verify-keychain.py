#!/usr/bin/env python3
"""Exercise passive reads across two real macOS code identities using fixture keys only."""
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
SWIFT = r'''
import Foundation
import Security

let mode = CommandLine.arguments[1]
let prefix = CommandLine.arguments[2]
let accounts = (0..<8).map { "keychain-selftest.\(prefix).\($0)" }
if mode == "create" {
    for account in accounts {
        precondition(Keychain.set("fixture-only", for: account))
    }
    print("PASS: created eight fixture keys with the writer identity")
} else if mode == "cleanup" {
    for account in accounts { precondition(Keychain.delete(account)) }
    print("PASS: removed only this run's fixture keys")
} else if mode == "trusted-read" {
    for account in accounts { let value = try Keychain.read(account); precondition(value == "fixture-only") }
    print("PASS: rebuilt app with the same signing identity reads all eight keys without reauthorization")
} else if mode == "read" {
    var before: DarwinBoolean = false
    precondition(SecKeychainGetUserInteractionAllowed(&before) == errSecSuccess)
    for account in accounts {
        precondition(Keychain.presence(account) == .saved)
        do {
            _ = try Keychain.read(account)
            fatalError("A different identity unexpectedly read a protected fixture")
        } catch Keychain.AccessError.authorizationRequired {
            // Expected: return an actionable state, without a password prompt.
        } catch { fatalError("Unexpected Keychain failure") }
    }
    var after: DarwinBoolean = false
    precondition(SecKeychainGetUserInteractionAllowed(&after) == errSecSuccess)
    precondition(before.boolValue == after.boolValue)
    print("PASS: eight protected keys returned authorizationRequired silently; metadata checks succeeded; interaction policy restored")
}
'''

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

with tempfile.TemporaryDirectory(prefix="airdraft-keychain-test-") as directory:
    temp = Path(directory)
    source = temp / "main.swift"
    source.write_text(SWIFT)
    core = ROOT / "Packages/AirdraftCore/Sources/AirdraftCore"
    binary = temp / "fixture"
    run("swiftc", "-swift-version", "5", core / "Settings/AppIdentity.swift",
        core / "Providers/Keychain.swift", source, "-o", binary,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    identity = json.loads((ROOT / "scripts/release-signing.json").read_text())["certificateSHA1"]
    apps = []
    for role in ("writer", "reader", "successor"):
        app = temp / f"{role}.app"
        executable = app / "Contents/MacOS/fixture"
        executable.parent.mkdir(parents=True)
        executable.write_bytes(binary.read_bytes())
        executable.chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": f"com.lstudlo.app.airdraft.keychain-test.{'writer' if role == 'successor' else role}",
            "CFBundleVersion": "2" if role == "successor" else "1",
            "CFBundleExecutable": "fixture", "CFBundlePackageType": "APPL",
        }))
        run("codesign", "--force", "--sign", identity, app, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        apps.append(executable)
    prefix = str(uuid.uuid4())
    try:
        run(apps[0], "create", prefix, timeout=20)
        run(apps[2], "trusted-read", prefix, timeout=20)
        run(apps[1], "read", prefix, timeout=20)
    finally:
        run(apps[0], "cleanup", prefix, timeout=20)
