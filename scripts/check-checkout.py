#!/usr/bin/env python3
"""Warn when this checkout would build stale or unexpected sources.

The main folder must stay on `main`; agent worktrees may use their own branch
but must contain the latest `origin/main`. Uses only local refs (no fetch) and
always exits 0, so it can run as an Xcode build phase. Pass `--xcode` to print
issues as Xcode build warnings.
"""
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def version(ref):
    data = subprocess.run(["git", "-C", str(ROOT), "show", f"{ref}:Sources/App/Info.plist"], capture_output=True)
    try:
        return plistlib.loads(data.stdout).get("CFBundleShortVersionString", "?") if data.returncode == 0 else "?"
    except Exception:
        return "?"


def main():
    xcode = "--xcode" in sys.argv[1:]
    toplevel = git("rev-parse", "--show-toplevel")
    # Exported sources (dist/release-source) have no repository of their own;
    # git would describe the enclosing folder instead, so say nothing.
    if toplevel is None or Path(toplevel).resolve() != ROOT:
        return 0
    branch = git("symbolic-ref", "--short", "-q", "HEAD") or "a detached HEAD"
    git_dir = Path(git("rev-parse", "--absolute-git-dir") or "")
    common_dir = Path(ROOT, git("rev-parse", "--git-common-dir") or ".git").resolve()
    primary = git_dir.resolve() == common_dir

    issues = []
    if primary and branch != "main":
        issues.append(f"The main folder is on {branch}, not main. Agent work belongs in a worktree; switch this folder back to main.")
    behind = git("rev-list", "--count", "HEAD..origin/main") if git("rev-parse", "-q", "--verify", "origin/main") else None
    if behind and int(behind) > 0:
        issues.append(f"{branch} is {behind} commits behind origin/main "
                      f"(version {version('HEAD')} here, {version('origin/main')} on main). Update before building.")

    for issue in issues:
        print(("warning: " if xcode else "") + issue)
    if not issues and not xcode:
        print(f"Checkout OK: {branch} at {git('rev-parse', '--short', 'HEAD')}, version {version('HEAD')}"
              f"{'' if primary else ' (worktree)'}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
