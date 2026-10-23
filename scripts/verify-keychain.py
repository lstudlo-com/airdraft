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

@diagnose(DeprecatedDeclaration, as: ignored)
func fileKeychainInteractionAllowed() -> Bool {
    var allowed: DarwinBoolean = false
    precondition(SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess)
    return allowed.boolValue
}

let mode = CommandLine.arguments[1]
let prefix = CommandLine.arguments[2]
let accounts = (0..<8).map { "keychain-selftest.\(prefix).\($0)" }
if mode == "create" {
    for account in accounts {
        precondition(Keychain.set("fixture-only", for: account))
    }
    print("PASS: created eight fixture keys with the writer identity")
    // License receipts write without interaction: add, then update in place.
    let silent = "keychain-selftest.\(prefix).silent"
    precondition(Keychain.set("fixture-silent", for: silent, allowInteraction: false))
    precondition(Keychain.set("fixture-silent-2", for: silent, allowInteraction: false))
    let silentValue = try Keychain.read(silent)
    precondition(silentValue == "fixture-silent-2")
    precondition(Keychain.delete(silent) && Keychain.presence(silent) == .missing)
    print("PASS: non-interactive add, update and passive read of a fixture key succeed for its owner")
} else if mode == "cleanup" {
    for account in accounts { precondition(Keychain.delete(account)) }
    print("PASS: removed only this run's fixture keys")
} else if mode == "trusted-read" {
    for account in accounts { let value = try Keychain.read(account); precondition(value == "fixture-only") }
    print("PASS: rebuilt app with the same signing identity reads all eight keys without reauthorization")
} else if mode == "read" {
    let before = fileKeychainInteractionAllowed()
    for account in accounts {
        precondition(Keychain.presence(account) == .saved)
        do {
            _ = try Keychain.read(account)
            fatalError("A different identity unexpectedly read a protected fixture")
        } catch Keychain.AccessError.authorizationRequired {
            // Expected: return an actionable state, without a password prompt.
        } catch { fatalError("Unexpected Keychain failure") }
    }
    precondition(before == fileKeychainInteractionAllowed())
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
    # Core files localize through SwiftPM's Bundle.module; compiled alone they
    # read the fixture's main bundle, which yields the English source strings.
    shim = temp / "ModuleBundle.swift"
    shim.write_text("import Foundation\nextension Bundle { static let module = Bundle.main }\n")
    build = subprocess.run(["swiftc", "-swift-version", "5", str(core / "Settings/AppIdentity.swift"),
                            str(core / "Providers/Keychain.swift"), str(shim), str(source), "-o", str(binary)],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if build.returncode != 0:
        raise SystemExit("FAIL: fixture did not compile:\n" + build.stderr)
    deprecated = [line for line in build.stderr.splitlines() if "Keychain.swift" in line and "deprecated" in line]
    if deprecated:
        raise SystemExit("FAIL: Keychain.swift has unscoped deprecation warnings:\n" + "\n".join(deprecated))
    print("PASS: Keychain.swift compiles without deprecation warnings", flush=True)
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
