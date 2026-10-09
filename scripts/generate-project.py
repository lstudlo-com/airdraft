#!/usr/bin/env python3
"""Generate the Xcode project using installed or workspace-bundled XcodeGen."""
from pathlib import Path
import shutil
import subprocess
import sys

from swiftpm_lock import restore


def main():
    root = Path(__file__).resolve().parents[1]
    executable = shutil.which("xcodegen")
    if executable is None:
        # A linked worktree has no dist/ of its own; reuse the main folder's tool.
        common = subprocess.run(["git", "-C", str(root), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True)
        bases = [root] + ([Path(common.stdout.strip()).parent] if common.returncode == 0 and common.stdout else [])
        for base in bases:
            bundled = base / "dist/tools/xcodegen/bin/xcodegen"
            if executable is None and bundled.is_file() and bundled.stat().st_mode & 0o111:
                executable = str(bundled)
    if executable is None:
        print("XcodeGen is missing. Install it with 'brew install xcodegen', then retry.", file=sys.stderr)
        return 127
    code = subprocess.run([executable, "generate"], cwd=root).returncode
    if code == 0:
        restore(root)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
