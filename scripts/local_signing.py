"""Choose the code-signing team for local builds without touching release signing.

Builds from source sign ad-hoc unless the git-ignored Config/Local.xcconfig names
a team. On a Mac that holds the pinned release certificate, project generation
creates that file for the pinned team so its Debug builds keep a stable identity
(and their macOS privacy grants) across rebuilds and new worktrees. Release
builds never read it: scripts/release.py passes the pinned identity explicitly.
Set AIRDRAFT_LOCAL_SIGNING=ad-hoc to skip the automatic file, for example to
reproduce a contributor build on the maintainer's Mac.
"""
import json
import os
from pathlib import Path
import subprocess

LOCAL = Path("Config/Local.xcconfig")
POLICY = Path("scripts/release-signing.json")


def pinned_identity_installed(certificate, run=subprocess.run):
    """Whether the keychain lists the pinned certificate. Never reads key material."""
    try:
        result = run(["security", "find-identity", "-v", "-p", "codesigning"],
                     capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0 and certificate.upper() in result.stdout.upper()


def local_config(team):
    return ("// Created by scripts/generate-project.py because the pinned release certificate\n"
            "// is installed on this Mac. Git-ignored; edit or delete it to sign differently.\n"
            f"DEVELOPMENT_TEAM = {team}\n"
            "CODE_SIGN_IDENTITY = Apple Development\n"
            "ENABLE_HARDENED_RUNTIME = YES\n")


def ensure_local_config(root, run=subprocess.run, log=print, environ=os.environ):
    """Create Config/Local.xcconfig for the pinned team when possible; keep existing files."""
    root = Path(root)
    target = root / LOCAL
    if target.exists():
        return "existing"
    policy = json.loads((root / POLICY).read_text())
    if (environ.get("AIRDRAFT_LOCAL_SIGNING") == "ad-hoc"
            or not pinned_identity_installed(policy["certificateSHA1"], run)):
        log("Local builds are signed ad-hoc. To keep macOS permissions across rebuilds, "
            "copy Config/Local.xcconfig.example to Config/Local.xcconfig and set your team.")
        return "ad-hoc"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(local_config(policy["teamID"]))
    log(f"Created {LOCAL} for the pinned development team {policy['teamID']}.")
    return "pinned"
