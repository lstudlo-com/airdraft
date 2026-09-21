"""Fail closed if a release would change the app identity used by macOS privacy grants.

The requirement is captured from Apple's default certificate signature. This
module validates it; it never replaces the app's designated requirement.
"""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

POLICY = json.loads(Path(__file__).with_name("release-signing.json").read_text())


def command(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True)


def preflight():
    identities = command("security", "find-identity", "-v", "-p", "codesigning").stdout.decode()
    if POLICY["certificateSHA1"] not in identities:
        raise RuntimeError("The pinned release signing identity is unavailable or expired. "
                           "Restore its certificate/private key; never fall back to ad-hoc signing.")
    return POLICY["certificateSHA1"]


def designated_requirement(app):
    output = command("codesign", "-d", "-r-", app)
    text = (output.stdout + output.stderr).decode()
    match = re.search(r"^designated => (.+)$", text, re.MULTILINE)
    if not match:
        raise RuntimeError("App has no certificate-bound designated requirement (possibly ad-hoc)")
    return match.group(1)


def validate_metadata(metadata):
    if metadata != POLICY:
        raise RuntimeError("Release signing identity differs from the approved policy. "
                           "A signer change requires an explicit permission-migration review.")


def inspect_app(app):
    app = Path(app)
    command("codesign", "--verify", "--deep", "--strict", app)
    output = command("codesign", "-d", "--verbose=4", app).stderr.decode()
    if "Signature=adhoc" in output:
        raise RuntimeError("Refusing an ad-hoc release: updates would invalidate macOS permissions")
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    team = re.search(r"^TeamIdentifier=(.+)$", output, re.MULTILINE)
    with tempfile.TemporaryDirectory(prefix="airdraft-certificate-") as temp:
        prefix = Path(temp) / "certificate"
        command("codesign", "-d", "--extract-certificates=" + str(prefix), app)
        leaf = Path(str(prefix) + "0")
        fingerprint = command("openssl", "x509", "-inform", "DER", "-in", leaf,
                              "-noout", "-fingerprint", "-sha1").stdout.decode()
        # Stop well before expiry. Certificate renewal must preserve the old DR.
        command("openssl", "x509", "-inform", "DER", "-in", leaf,
                "-noout", "-checkend", str(30 * 24 * 60 * 60))
    metadata = {
        "bundleID": info.get("CFBundleIdentifier"),
        "teamID": team.group(1) if team else None,
        "certificateSHA1": fingerprint.strip().split("=")[-1].replace(":", "").upper(),
        "designatedRequirement": designated_requirement(app),
    }
    validate_metadata(metadata)
    command("codesign", "--verify", "--strict", "-R", "=" + POLICY["designatedRequirement"], app)
    entitlements = command("codesign", "-d", "--entitlements", ":-", app).stdout
    if entitlements and plistlib.loads(entitlements).get("com.apple.security.get-task-allow"):
        raise RuntimeError("Release must not allow debugger attachment")
    if (app / "Contents/embedded.provisionprofile").exists():
        raise RuntimeError("Release unexpectedly requires a device provisioning profile")
    return metadata


def inspect_dmg(archive):
    with tempfile.TemporaryDirectory(prefix="airdraft-dmg-check-") as temp:
        command("hdiutil", "attach", archive, "-readonly", "-nobrowse", "-mountpoint", temp)
        try:
            apps = list(Path(temp).glob("*.app"))
            if len(apps) != 1:
                raise RuntimeError("Release DMG must contain exactly one app")
            return inspect_app(apps[0])
        finally:
            command("hdiutil", "detach", temp)
