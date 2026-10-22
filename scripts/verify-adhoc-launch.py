#!/usr/bin/env python3
"""Prove that a team-less ad-hoc source build launches and loads its frameworks.

Contributors build without an Apple developer team, so Xcode signs ad-hoc. An
ad-hoc signature has no Team ID; with Hardened Runtime, library validation then
rejects the app's own frameworks ("different Team IDs") and dyld stops the app
before main. Config/Signing.xcconfig therefore enables Hardened Runtime only for
team-signed builds (releases pass it explicitly).

By default this clones the committed HEAD into a disposable directory, generates
the project with AIRDRAFT_LOCAL_SIGNING=ad-hoc (no Config/Local.xcconfig), builds
Debug, checks the signature and launches the app with an isolated E2E data
directory and a Home render. It never touches this checkout's Local.xcconfig.
`--app` verifies an existing ad-hoc build instead (CI). A negative control
re-signs a copy with Hardened Runtime and requires dyld to refuse it, so the
check cannot pass vacuously.
"""
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DYLD_FAILURE = re.compile(r"Library not loaded|different Team IDs|not valid for use in process")
XCODE = ["-project", "airdraft.xcodeproj", "-scheme", "airdraft", "-configuration", "Debug",
         "-skipPackagePluginValidation", "-skipMacroValidation",
         "-packageAuthorizationProvider", "netrc", "-onlyUsePackageVersionsFromResolvedFile"]


def run(command, **kwargs):
    print("+", " ".join(str(part) for part in command), flush=True)
    return subprocess.run(command, check=True, **kwargs)


def find_xcodegen():
    """Reuse generate-project's lookup so a clone finds the main folder's pinned tool."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("generate_project", ROOT / "scripts/generate-project.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.find_xcodegen(ROOT)


def clone_and_build(work, log):
    source = work / "airdraft"
    revision = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], check=True,
                              capture_output=True, text=True).stdout.strip()
    run(["git", "clone", "--quiet", "--shared", "--no-checkout", str(ROOT), str(source)])
    run(["git", "-C", str(source), "checkout", "--quiet", "--detach", revision])
    vendor = ROOT / "Packages/SherpaOnnxKit/Vendor"
    if not vendor.is_dir():
        raise RuntimeError(f"{vendor} is missing; run scripts/make-sherpa-xcframeworks.sh first")
    run(["cp", "-cR", str(vendor), str(source / "Packages/SherpaOnnxKit/Vendor")])
    xcodegen = find_xcodegen()
    if xcodegen is None:
        raise RuntimeError("XcodeGen is missing; see scripts/generate-project.py --install-xcodegen")
    env = dict(os.environ, AIRDRAFT_LOCAL_SIGNING="ad-hoc",
               PATH=f"{Path(xcodegen).parent}{os.pathsep}{os.environ.get('PATH', '')}")
    run([sys.executable, "scripts/generate-project.py"], cwd=source, env=env)
    if (source / "Config/Local.xcconfig").exists():
        raise RuntimeError("the disposable clone unexpectedly has Config/Local.xcconfig")
    settings = subprocess.run(["xcodebuild", *XCODE, "-showBuildSettings"], cwd=source, check=True,
                              capture_output=True, text=True).stdout
    resolved = dict(re.findall(r"^\s+(ENABLE_HARDENED_RUNTIME|DEVELOPMENT_TEAM|CODE_SIGN_IDENTITY"
                               r"|TARGET_BUILD_DIR|FULL_PRODUCT_NAME|OBJROOT) = (.*)$", settings, re.MULTILINE))
    print(f"Resolved: {resolved}", flush=True)
    if resolved.get("DEVELOPMENT_TEAM", "").strip() or resolved.get("ENABLE_HARDENED_RUNTIME") != "NO":
        raise RuntimeError(f"ad-hoc clone must resolve no team and Hardened Runtime NO: {resolved}")
    with log.open("w") as output:
        code = subprocess.run(["xcodebuild", *XCODE, "build"], cwd=source,
                              stdout=output, stderr=subprocess.STDOUT).returncode
    if code != 0:
        raise RuntimeError(f"ad-hoc build failed with exit {code}; see {log}")
    return Path(resolved["TARGET_BUILD_DIR"]) / resolved["FULL_PRODUCT_NAME"], Path(resolved["OBJROOT"])


def signature(app):
    details = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], capture_output=True, text=True)
    flags = re.search(r"flags=0x([0-9a-fA-F]+)", details.stderr)
    return details.stderr, int(flags.group(1), 16) if flags else 0


def launch(app, directory, timeout):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if not str(info.get("CFBundleIdentifier", "")).startswith("com.lstudlo.app.airdraft.debug"):
        raise RuntimeError("use a Debug build with the isolated E2E entry point")
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    data, renders = directory / "data", directory / "renders"
    data.mkdir(parents=True)
    renders.mkdir()
    env = {name: os.environ[name] for name in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG")
           if name in os.environ}
    log_path = directory / "launch.log"
    with log_path.open("w") as log:
        process = subprocess.Popen([str(binary), "--e2e-local", str(data), "--render-window", "home", str(renders)],
                                   env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
            code = None
    output = log_path.read_text(errors="replace")
    pngs = sorted(path.name for path in renders.glob("home-*.png") if path.stat().st_size > 0)
    return code, output, pngs


def verify(app, work, timeout, negative):
    app = app.resolve(strict=True)
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    details, flags = signature(app)
    (work / "codesign.txt").write_text(details)
    if "Signature=adhoc" not in details or "TeamIdentifier=not set" not in details:
        raise RuntimeError("expected a team-less ad-hoc signature; see codesign.txt")
    if flags & 0x10000:
        raise RuntimeError("ad-hoc build carries Hardened Runtime; library validation will reject its frameworks")
    code, output, pngs = launch(app, work / "launch", timeout)
    if code != 0 or DYLD_FAILURE.search(output) or pngs != ["home-dark.png", "home-light.png"]:
        raise RuntimeError(f"ad-hoc app did not launch and render (exit {code}, renders {pngs}); "
                           f"see {work / 'launch/launch.log'}")
    print(f"PASS: ad-hoc build launched, loaded its frameworks and rendered {', '.join(pngs)}")
    if negative:
        copy = work / "negative" / app.name
        copy.parent.mkdir()
        run(["ditto", str(app), str(copy)])
        run(["codesign", "--force", "--sign", "-", "--options", "runtime",
             "--preserve-metadata=identifier,entitlements", str(copy)], capture_output=True)
        code, output, _ = launch(copy, work / "negative/launch", timeout)
        if code == 0 or not DYLD_FAILURE.search(output):
            raise RuntimeError("negative control: ad-hoc + Hardened Runtime unexpectedly launched")
        print("PASS: negative control (ad-hoc + Hardened Runtime) is refused by dyld")


def remove_derived_data(objroot, source):
    """Delete only the DerivedData folder Xcode created for the disposable clone."""
    derived = objroot.parents[1] if objroot.name == "Intermediates.noindex" else None
    info = derived / "info.plist" if derived else None
    if not info or not info.is_file():
        return
    workspace = plistlib.loads(info.read_bytes()).get("WorkspacePath", "")
    if Path(workspace).resolve().is_relative_to(source.resolve()):
        shutil.rmtree(derived)
        print(f"Removed disposable DerivedData {derived}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, help="verify this existing ad-hoc Debug build instead of cloning")
    parser.add_argument("--output", type=Path, help="evidence directory (default: a temporary directory)")
    parser.add_argument("--timeout", type=int, default=180, help="launch deadline in seconds")
    parser.add_argument("--keep", action="store_true", help="keep the clone and its DerivedData")
    parser.add_argument("--skip-negative", action="store_true", help="skip the Hardened Runtime negative control")
    args = parser.parse_args()
    work = (args.output or Path(tempfile.mkdtemp(prefix="airdraft-adhoc-"))).resolve()
    work.mkdir(parents=True, exist_ok=True)
    if any(work.iterdir()):
        parser.error(f"{work} must be empty")
    objroot = None
    try:
        if args.app:
            app = args.app
        else:
            app, objroot = clone_and_build(work, work / "build.log")
        verify(app, work, args.timeout, not args.skip_negative)
    finally:
        if objroot and not args.keep:
            remove_derived_data(objroot, work / "airdraft")
            shutil.rmtree(work / "airdraft", ignore_errors=True)
    print(f"Evidence: {work}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
