#!/usr/bin/env python3
"""Generate the Xcode project using installed or workspace-bundled XcodeGen."""
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    executable = shutil.which("xcodegen")
    if executable is None:
        bundled = root / "dist/tools/xcodegen/bin/xcodegen"
        if bundled.is_file() and bundled.stat().st_mode & 0o111:
            executable = str(bundled)
    if executable is None:
        print("XcodeGen is missing. Install it with 'brew install xcodegen', then retry.", file=sys.stderr)
        return 127
    return subprocess.run([executable, "generate"], cwd=root).returncode


if __name__ == "__main__":
    raise SystemExit(main())
