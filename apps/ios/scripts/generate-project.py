#!/usr/bin/env python3
"""Generate the iOS Xcode project with the same XcodeGen the Mac app uses.

The iOS app builds the same SwiftPM graph as the Mac app (AirdraftCore and its
engines), so the repository's root Package.resolved is restored into the
generated project, exactly as scripts/generate-project.py does for the Mac.
Normal generation never downloads tools.
"""
from pathlib import Path
import shutil
import subprocess
import sys

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from swiftpm_lock import resolution  # noqa: E402

PROJECT = IOS / "AirdraftiOS.xcodeproj"
GENERATED_LOCK = PROJECT / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"


def find_xcodegen():
    """Installed XcodeGen, else the main folder's pinned copy in dist/tools."""
    executable = shutil.which("xcodegen")
    if executable:
        return executable
    common = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                            capture_output=True, text=True)
    bases = [ROOT] + ([Path(common.stdout.strip()).parent] if common.returncode == 0 and common.stdout else [])
    for base in bases:
        bundled = base / "dist/tools/xcodegen/bin/xcodegen"
        if bundled.is_file() and bundled.stat().st_mode & 0o111:
            return str(bundled)
    return None


def restore_pins():
    canonical = ROOT / "Package.resolved"
    resolution(canonical)
    GENERATED_LOCK.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(canonical, GENERATED_LOCK)


def main():
    executable = find_xcodegen()
    if executable is None:
        print("XcodeGen is missing. Run 'python3 scripts/generate-project.py --install-xcodegen' "
              "from the repository root once, then retry.", file=sys.stderr)
        return 127
    code = subprocess.run([executable, "generate", "--spec", str(IOS / "project.yml")], cwd=IOS).returncode
    if code == 0:
        restore_pins()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
