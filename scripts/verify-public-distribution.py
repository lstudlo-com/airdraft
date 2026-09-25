#!/usr/bin/env python3
"""Read-only public distribution gate. Does not sign, notarize, publish or change identity."""
import argparse
from pathlib import Path
import sys
import tempfile
from release_signing import command, inspect_app


def verify_app(app):
    # This also preserves the approved privacy/Keychain identity. Updating the
    # policy for Developer ID requires a separate, explicit migration review.
    inspect_app(app)
    signature = command("codesign", "-d", "--verbose=4", app).stderr.decode()
    if "Authority=Developer ID Application:" not in signature:
        raise RuntimeError("Public distribution requires a Developer ID Application identity and an approved identity migration")
    command("xcrun", "stapler", "validate", app)
    command("spctl", "--assess", "--type", "execute", "--verbose=4", app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    artifact = parser.parse_args().artifact.resolve()
    if artifact.suffix == ".app":
        verify_app(artifact)
    elif artifact.suffix == ".dmg":
        command("xcrun", "stapler", "validate", artifact)
        command("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", artifact)
        with tempfile.TemporaryDirectory(prefix="airdraft-public-check-") as temp:
            command("hdiutil", "attach", artifact, "-readonly", "-nobrowse", "-mountpoint", temp)
            try:
                apps = list(Path(temp).glob("*.app"))
                if len(apps) != 1: raise RuntimeError("DMG must contain exactly one app")
                verify_app(apps[0])
            finally:
                command("hdiutil", "detach", temp)
    else:
        raise RuntimeError("Expected an app or DMG")
    print("Public distribution checks passed")


if __name__ == "__main__":
    try: main()
    except Exception as error:
        print(f"Public distribution blocked: {error}", file=sys.stderr)
        sys.exit(1)
