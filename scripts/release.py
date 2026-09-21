#!/usr/bin/env python3
"""Build committed sources locally before a main push; publish that draft after push."""
import argparse
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import xml.etree.ElementTree as ET

from release_signing import POLICY, inspect_app, inspect_dmg, preflight, validate_metadata

REPO = "lstudlo-com/airdraft"
ACCOUNT = "com.lstudlo.app.airdraft.sparkle"
ROOT = Path(__file__).resolve().parents[1]
ZERO = "0" * 40
XCODEGEN_SHA256 = "4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"


def run(*args, cwd=ROOT, capture=False, **kwargs):
    result = subprocess.run([str(a) for a in args], cwd=cwd, check=True,
                            stdout=subprocess.PIPE if capture else None, text=True, **kwargs)
    return result.stdout.strip() if capture else None


def gh(*args, capture=False):
    return run("gh", *args, capture=capture)


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def version_for(project, build):
    match = re.search(r'CFBundleShortVersionString: "([0-9]+(?:\.[0-9]+)*)"', project)
    if not match:
        raise RuntimeError("project.yml needs a numeric CFBundleShortVersionString")
    version = match.group(1)
    return version, f"v{version}-build.{build}"


def pushed_commit(lines):
    commits = []
    for line in lines.splitlines():
        local_ref, local_sha, remote_ref, remote_sha = line.split()
        if remote_ref != "refs/heads/main":
            continue
        if local_sha == ZERO:
            raise RuntimeError("The release hook refuses deletion of main")
        if not re.fullmatch(r"[0-9a-f]{40}", local_sha):
            raise RuntimeError("Invalid pushed commit")
        commits.append((local_sha, remote_sha))
    if len(commits) > 1:
        raise RuntimeError("Expected a single main update")
    return commits[0] if commits else None


def releases():
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{REPO}/releases?per_page=100", capture=True))
    return [release for page in pages for release in page]


def release_for(tag):
    return next((r for r in releases() if r["tag_name"] == tag), None)


def validate_continuity(previous):
    # The one known ad-hoc -> certificate migration. No future unsigned baseline
    # is accepted, even if someone accidentally omits signing metadata again.
    if (previous.get("tag") == "v0.1.4-build.6"
            and previous.get("commit") == "7dbd3aaac6a669715c64c150238f71d397e0ad26"
            and "signing" not in previous):
        return
    signing = previous.get("signing")
    identity_fields = ("bundleID", "teamID", "designatedRequirement")
    if not isinstance(signing, dict) or any(signing.get(key) != POLICY[key] for key in identity_fields):
        raise RuntimeError("Latest published release has a different permission identity. "
                           "Refusing to publish an incompatible update.")


def check_previous_release():
    tag = gh("api", f"repos/{REPO}/releases/latest", "--jq", ".tag_name", capture=True)
    with tempfile.TemporaryDirectory(prefix="airdraft-previous-release-") as temporary:
        gh("release", "download", tag, "--repo", REPO, "--dir", temporary,
           "--pattern", "release.json")
        validate_continuity(json.loads((Path(temporary) / "release.json").read_text()))


def validate_manifest(manifest, commit, tag):
    validate_metadata(manifest.get("signing"))
    if manifest.get("commit") != commit or manifest.get("tag") != tag:
        raise RuntimeError("Release manifest does not match the pushed commit/tag")
    build = manifest.get("build")
    if not isinstance(build, int) or build < 1:
        raise RuntimeError("Invalid release build")
    version = manifest.get("version", "")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
        raise RuntimeError("Invalid release version")
    archive = f"Airdraft-{version}-{build}-arm64.dmg"
    expected = {archive, "appcast.xml"}
    if set(manifest.get("sha256", {})) != expected:
        raise RuntimeError("Release must contain exactly the expected DMG and appcast hashes")
    if any(not re.fullmatch(r"[0-9a-f]{64}", value) for value in manifest["sha256"].values()):
        raise RuntimeError("Invalid asset checksum")
    return archive


def download_and_verify(tag, commit, directory):
    gh("release", "download", tag, "--repo", REPO, "--dir", directory,
       "--pattern", "release.json", "--pattern", "appcast.xml", "--pattern", "*.dmg")
    manifest = json.loads((directory / "release.json").read_text())
    archive = validate_manifest(manifest, commit, tag)
    for name, digest in manifest["sha256"].items():
        if sha256(directory / name) != digest:
            raise RuntimeError(f"Uploaded asset checksum mismatch: {name}")
    ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    items = ET.parse(directory / "appcast.xml").findall("./channel/item")
    current = next((item for item in items if item.findtext("sparkle:version", namespaces=ns) == str(manifest["build"])), None)
    enclosure = current.find("enclosure") if current is not None else None
    url = f"https://github.com/{REPO}/releases/download/{tag}/{archive}"
    if enclosure is None or enclosure.get("url") != url or not enclosure.get(f'{{{ns["sparkle"]}}}edSignature'):
        raise RuntimeError("Feed does not describe this release's signed DMG")
    if int(enclosure.get("length", "0")) != (directory / archive).stat().st_size:
        raise RuntimeError("Feed archive length mismatch")
    if sys.platform == "darwin":
        if inspect_dmg(directory / archive) != manifest["signing"]:
            raise RuntimeError("DMG signature differs from its release manifest")
    return manifest


def xcodegen():
    installed = shutil.which("xcodegen")
    if installed:
        return installed
    directory = ROOT / "dist/tools"
    executable = directory / "xcodegen/bin/xcodegen"
    if not executable.exists():
        directory.mkdir(parents=True, exist_ok=True)
        archive = directory / "xcodegen-2.46.0.zip"
        run("curl", "--fail", "--location", "--retry", "3", "--output", archive,
            "https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip")
        if sha256(archive) != XCODEGEN_SHA256:
            raise RuntimeError("XcodeGen download checksum mismatch")
        run("ditto", "-xk", archive, directory)
    return executable


def export_snapshot(commit):
    # Stable path gives Xcode one reusable DerivedData tree. Never includes dirty files.
    destination = ROOT / "dist/release-source"
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    archive = subprocess.check_output(["git", "archive", "--format=tar", commit], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(destination, filter="data")
    vendor = ROOT / "Packages/SherpaOnnxKit/Vendor"
    if not vendor.is_dir():
        raise RuntimeError("Run moon run airdraft:prepare once to install the native speech libraries")
    (destination / "Packages/SherpaOnnxKit/Vendor").symlink_to(vendor, target_is_directory=True)
    return destination


def logged(args, source, log):
    print(f"Running {args[-1]}; log: {log}", flush=True)
    with log.open("a") as output:
        result = subprocess.run([str(a) for a in args], cwd=source, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-70:]), file=sys.stderr)
        raise RuntimeError(f"Local validation failed; see {log}")


def prepare(commit):
    if sys.platform != "darwin":
        raise RuntimeError("Release preparation requires the signing Mac")
    if run("git", "rev-parse", "--is-shallow-repository", capture=True) != "false":
        raise RuntimeError("Fetch complete Git history before deriving release build numbers")
    commit = run("git", "rev-parse", f"{commit}^{{commit}}", capture=True)
    build = int(run("git", "rev-list", "--count", commit, capture=True))
    project = run("git", "show", f"{commit}:project.yml", capture=True)
    version, tag = version_for(project, build)
    check_previous_release()
    existing = release_for(tag)
    if existing:
        with tempfile.TemporaryDirectory(prefix="airdraft-release-check-") as temporary:
            download_and_verify(tag, commit, Path(temporary))
        print(f"Verified existing release assets for {tag}; push may continue.", flush=True)
        return
    source = export_snapshot(commit)
    identity = preflight()
    project = re.sub(r'CFBundleVersion: "[0-9]+"', f'CFBundleVersion: "{build}"', project)
    (source / "project.yml").write_text(project + "\n")
    output = ROOT / "dist/releases" / tag
    output.mkdir(parents=True, exist_ok=True)
    logged([sys.executable, source / "scripts/test-release.py"], source, output / "build.log")
    run(xcodegen(), "generate", cwd=source)
    common = ["xcodebuild", "-project", "airdraft.xcodeproj", "-scheme", "airdraft",
              "-skipPackagePluginValidation", "-skipMacroValidation",
              f"CODE_SIGN_IDENTITY={identity}", "CODE_SIGN_STYLE=Manual"]
    logged(common + ["-configuration", "Debug", "test"], source, output / "build.log")
    logged(common + ["-configuration", "Release", "-destination", "generic/platform=macOS", "ARCHS=arm64", "build"], source, output / "build.log")
    raw = run(*common, "-configuration", "Release", "-showBuildSettings", "-json", cwd=source, capture=True)
    settings = next(item["buildSettings"] for item in json.loads(raw) if item["target"] == "airdraft")
    app = Path(settings["TARGET_BUILD_DIR"]) / settings["FULL_PRODUCT_NAME"]
    derived = Path(settings["BUILD_DIR"]).parents[1]
    tools = derived / "SourcePackages/artifacts/sparkle/Sparkle/bin"
    signing = inspect_app(app)
    logged([sys.executable, source / "scripts/verify-updater.py", "--sparkle", tools.parent],
           source, output / "updater.log")
    logged([sys.executable, source / "scripts/verify-updater.py", "--sparkle", tools.parent,
            "--legacy-source"], source, output / "updater.log")
    # Package to a fresh directory, then replace only our generated local output.
    with tempfile.TemporaryDirectory(prefix="airdraft-package-", dir=output) as temporary:
        artifacts = Path(temporary)
        logged([sys.executable, source / "scripts/package-update.py", "--app", app,
                "--sparkle-bin", tools, "--output", artifacts,
                "--download-url-prefix", f"https://github.com/{REPO}/releases/download/{tag}/"], source, output / "build.log")
        for asset in artifacts.iterdir():
            if asset.is_file() and asset.suffix in (".xml", ".dmg"):
                shutil.copy2(asset, output / asset.name)
    archive = output / f"Airdraft-{version}-{build}-arm64.dmg"
    manifest = {"commit": commit, "tag": tag, "version": version, "build": build,
                "signing": signing,
                "sha256": {p.name: sha256(p) for p in [archive, output / "appcast.xml"]}}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    subject = run("git", "show", "-s", "--format=%s", commit, capture=True)
    notes = output / "notes.md"
    notes.write_text(f"{subject}\n\nDownload the DMG, open it, and drag Airdraft into Applications.\n\n"
                     "Requires Apple Silicon and macOS 15 or later. This build is not notarized; "
                     "macOS may require approval in System Settings → Privacy & Security on first launch. "
                     "Signed with the pinned Apple Development certificate for personal use; "
                     "this is not a Developer ID/notarized public distribution build.\n\n"
                     "Upgrading from 0.1.4 or earlier changes the old ad-hoc app identity. "
                     "If access is missing, quit Airdraft, remove its stale Accessibility entries, "
                     "add /Applications/airdraft.app, and reopen it. Approve Microphone if prompted. "
                     "Certificate-signed updates now preserve the designated requirement; "
                     "the release process rejects incompatible signing identities.\n\n"
                     f"Includes a signed Sparkle update feed. Built locally from `{commit}`.\n")
    # A draft creates no public tag. The workflow sets its final target after Git accepts the push.
    gh("release", "create", tag, archive, output / "appcast.xml", output / "release.json",
       "--repo", REPO, "--draft", "--target", "main", "--title", f"Airdraft {version} (build {build})",
       "--notes-file", notes)
    with tempfile.TemporaryDirectory(prefix="airdraft-upload-check-") as temporary:
        download_and_verify(tag, commit, Path(temporary))
    print(f"Verified draft {tag}. GitHub will publish it after this commit reaches main.", flush=True)


def publish(commit):
    # Runs in GitHub Actions or explicitly after a successful push for recovery.
    actual = gh("api", f"repos/{REPO}/git/ref/heads/main", "--jq", ".object.sha", capture=True)
    if actual != commit:
        raise RuntimeError("main has moved; refusing to publish an older build as latest")
    build = int(run("git", "rev-list", "--count", commit, capture=True))
    project = run("git", "show", f"{commit}:project.yml", capture=True)
    _, tag = version_for(project, build)
    release = release_for(tag)
    if not release:
        raise RuntimeError("No locally built draft. Run the release hook on the signing Mac, then rerun this workflow.")
    with tempfile.TemporaryDirectory(prefix="airdraft-publish-") as temporary:
        manifest = download_and_verify(tag, commit, Path(temporary))
    if manifest["build"] != build:
        raise RuntimeError("Release build does not match commit history")
    check_previous_release()
    if not release["draft"]:
        target = gh("api", f"repos/{REPO}/git/ref/tags/{tag}", "--jq", ".object.sha", capture=True)
        if target != commit:
            raise RuntimeError("Published release tag points at another commit")
        print(f"Already published: https://github.com/{REPO}/releases/tag/{tag}")
        return
    # Recheck immediately before publication after potentially slow downloads.
    if gh("api", f"repos/{REPO}/git/ref/heads/main", "--jq", ".object.sha", capture=True) != commit:
        raise RuntimeError("main moved during validation; refusing stale publication")
    gh("release", "edit", tag, "--repo", REPO, "--target", commit, "--draft=false", "--latest")
    print(f"Published: https://github.com/{REPO}/releases/tag/{tag}")


def install_hook():
    run("swift", ROOT / "scripts/migrate-sparkle-key.swift")
    hook = Path(run("git", "rev-parse", "--git-path", "hooks/pre-push", capture=True))
    if not hook.is_absolute():
        hook = ROOT / hook
    content = (ROOT / ".githooks/pre-push").read_bytes()
    if hook.exists() and b"Airdraft local release hook" not in hook.read_bytes():
        raise RuntimeError(f"Existing hook at {hook}; integrate .githooks/pre-push without overwriting it")
    hook.parent.mkdir(parents=True, exist_ok=True)
    hook.write_bytes(content)
    hook.chmod(0o755)
    print(f"Installed {hook}. Every push to origin/main now prepares a local DMG.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["install-hook", "pre-push", "prepare", "publish"])
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args()
    if args.command == "install-hook":
        install_hook()
        return
    if args.command == "publish":
        publish(args.arguments[0] if args.arguments else run("git", "rev-parse", "HEAD", capture=True))
        return
    commit = args.arguments[0] if args.arguments else "HEAD"
    if args.command == "pre-push":
        pushed = pushed_commit(sys.stdin.read())
        if not pushed:
            return
        if not args.arguments or args.arguments[0] != "origin":
            return
        url = args.arguments[1] if len(args.arguments) > 1 else ""
        if url not in (f"https://github.com/{REPO}.git", f"git@github.com:{REPO}.git", f"https://github.com/{REPO}"):
            raise RuntimeError("origin does not match the configured release repository")
        commit, previous = pushed
        if previous != ZERO:
            run("git", "merge-base", "--is-ancestor", previous, commit)
    lock_path = ROOT / "dist/release.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        prepare(commit)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        sys.exit(1)
