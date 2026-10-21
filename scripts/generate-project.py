#!/usr/bin/env python3
"""Generate the Xcode project using installed or workspace-bundled XcodeGen.

Normal generation never downloads tools. Pass --install-xcodegen once to fetch
the pinned, checksum-verified XcodeGen release into dist/tools when neither
Homebrew's nor a bundled copy is available.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

from local_signing import ensure_local_config
from swiftpm_lock import restore


def find_xcodegen(root):
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
    return executable


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--install-xcodegen", action="store_true",
                        help="download the pinned XcodeGen into dist/tools if none is installed")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    executable = find_xcodegen(root)
    if executable is None and args.install_xcodegen:
        from release import xcodegen  # Pinned URL and SHA-256 shared with releases and CI.
        executable = str(xcodegen())
    if executable is None:
        print("XcodeGen is missing. Install it with 'brew install xcodegen', or run "
              "'python3 scripts/generate-project.py --install-xcodegen' to download the pinned, "
              "checksum-verified release into dist/tools. Then retry.", file=sys.stderr)
        return 127
    ensure_local_config(root)
    code = subprocess.run([executable, "generate"], cwd=root).returncode
    if code == 0:
        restore(root)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
