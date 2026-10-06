"""Restore and check the app's committed SwiftPM resolution after XcodeGen."""
import json
from pathlib import Path
import re
import shutil

GENERATED_LOCK = Path("airdraft.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")


def resolution(path):
    try:
        value = json.loads(path.read_text())
        pins = value["pins"]
        if value["version"] != 3 or not isinstance(pins, list) or not pins:
            raise ValueError("expected a nonempty version 3 resolution")
        identities = set()
        for pin in pins:
            identity = pin["identity"]
            if (not isinstance(identity, str) or not identity or identity in identities
                    or pin["kind"] != "remoteSourceControl"
                    or not isinstance(pin["location"], str)
                    or not re.fullmatch(r"[0-9a-f]{40}", pin["state"]["revision"])):
                raise ValueError("invalid or duplicate package pin")
            identities.add(identity)
        # originHash belongs to Xcode's resolver context, not package identity.
        return sorted(pins, key=lambda pin: pin["identity"])
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise RuntimeError(f"Invalid SwiftPM resolution at {path}: {error}") from error


def restore(root):
    root = Path(root)
    canonical = root / "Package.resolved"
    resolution(canonical)
    target = root / GENERATED_LOCK
    if not (root / "airdraft.xcodeproj/project.pbxproj").is_file():
        raise RuntimeError("Generate the Xcode project before restoring SwiftPM pins")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(canonical, target)
    return target


def verify(root):
    root = Path(root)
    if resolution(root / "Package.resolved") != resolution(root / GENERATED_LOCK):
        raise RuntimeError("SwiftPM resolution changed from committed Package.resolved; review the dependency change before building a release")
    return root / GENERATED_LOCK
