#!/usr/bin/env python3
"""Run the live insertion fixture against every installed editor and saved method.

For each installed target among TextEdit, Chrome, Safari, Notes, VS Code, Slack,
Warp, Zed, Ghostty, Terminal and iTerm2 (detected by bundle ID in the
application folders; nothing is installed), and each saved insertion method
(auto, paste), this prepares a disposable field holding a fresh
`Airdraft insertion fixture <UUID>` marker, waits until the user has focused it,
runs the Debug app's `--e2e-action insert` and checks the result:

* editors with a field: the actual resulting text, one delivery callback, no
  notice and the Debug build's binary hashes;
* editors in `TextInserter.selfDrawingEditorBundlePrefixes` (read from the
  build itself): the documented sent-unverified outcome, plus the receiver's
  bracketed-paste evidence where the target is a terminal.

Fields are prepared without AppleScript, System Events or synthetic input:
files and a local HTML page are opened with `open -a`, terminals run a
prompt-less receiver, and apps without a file route (Notes, Slack) print
manual steps. Accessibility trust is read first from the Debug app's own
`--e2e-action accessibility` report (`AXIsProcessTrusted`, which never
prompts). Without it every case is UNVERIFIED and the script explains how to
grant access once; it never requests or changes a permission.

Exit status: 0 when every case passed, 1 when any case failed, 2 when the
matrix is incomplete (UNVERIFIED cases, nothing failed).
"""
import argparse
from dataclasses import dataclass, field
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import select
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).resolve()
METHODS = ("auto", "paste")
GATE_BUNDLES = ("com.apple.TextEdit", "com.google.Chrome")
INSERTER_SOURCE = ROOT / "Packages/AirdraftCore/Sources/AirdraftCore/Insertion/TextInserter.swift"
APPLICATION_DIRS = (Path("/Applications"), Path("/Applications/Utilities"), Path("/System/Applications"),
                    Path("/System/Applications/Utilities"), Path("/System/Volumes/Preboot/Cryptexes/App/System/Applications"),
                    Path.home() / "Applications")
PREPARATION_FAILURE = "fixture refused before any paste"


@dataclass(frozen=True)
class Target:
    name: str
    bundle_ids: tuple
    # document: open a text file; web: open a local page whose field focuses
    # itself; receiver: a prompt-less terminal receiver; manual: printed steps.
    preparation: str
    # Open the receiver script with `open -a` (only where the app runs it).
    opens_receiver: bool = False
    instructions: str = ""


TARGETS = (
    Target("TextEdit", ("com.apple.TextEdit",), "document",
           instructions="Click at the very end of the marker line (or press Command-Down Arrow)."),
    Target("Chrome", ("com.google.Chrome",), "web",
           instructions="The page focuses its field with the caret at the end; click after the text if not."),
    Target("Safari", ("com.apple.Safari",), "web",
           instructions="The page focuses its field with the caret at the end; click after the text if not."),
    Target("Notes", ("com.apple.Notes",), "manual",
           instructions="Create a new, empty note, type or paste exactly the marker below as its only text, "
                        "and leave the caret at its end. Delete the note afterwards."),
    Target("VS Code", ("com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"), "document",
           instructions="Click at the very end of the marker line in the opened file."),
    Target("Slack", ("com.tinyspeck.slackmacgap",), "manual",
           instructions="Open your own direct message (You), type or paste exactly the marker below as the only "
                        "text in its message box and leave the caret at its end. Never press Return; clear the "
                        "draft afterwards."),
    Target("Warp", ("dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp"), "receiver",
           instructions="Open a new Warp window and run the receiver command below, then click into it."),
    Target("Zed", ("dev.zed.Zed", "dev.zed.Zed-Preview", "dev.zed.Zed-Nightly"), "document",
           instructions="Click at the very end of the marker line in the opened file. Close it without saving."),
    Target("Ghostty", ("com.mitchellh.ghostty",), "receiver",
           instructions="Open a new Ghostty window and run the receiver command below, then click into it."),
    Target("Terminal", ("com.apple.Terminal",), "receiver", opens_receiver=True,
           instructions="Click into the new Terminal window that shows the marker."),
    Target("iTerm2", ("com.googlecode.iterm2",), "receiver",
           instructions="Open a new iTerm2 window and run the receiver command below, then click into it."),
)


def load_gate():
    spec = importlib.util.spec_from_file_location("live_insertion", SCRIPT.with_name("verify-live-insertion.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bundle_id(app):
    try:
        return plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier")
    except Exception:  # Unreadable or malformed third-party bundles are skipped.
        return None


def detect_targets(directories=APPLICATION_DIRS, names=None):
    """Return [(Target, bundle ID, app path)] for installed targets, first match per target."""
    installed = {}
    for directory in directories:
        if not Path(directory).is_dir():
            continue
        for app in sorted(Path(directory).glob("*.app")):
            identifier = bundle_id(app)
            if identifier and identifier not in installed:
                installed[identifier] = app
    found = []
    for target in TARGETS:
        if names and target.name.lower() not in names:
            continue
        match = next((identifier for identifier in target.bundle_ids if identifier in installed), None)
        if match:
            found.append((target, match, installed[match]))
    return found


def self_drawing_prefixes(probe=None, source=INSERTER_SOURCE):
    """The build's own list when probed; otherwise the single source definition."""
    if probe and isinstance(probe.get("selfDrawingEditorBundlePrefixes"), list):
        return list(probe["selfDrawingEditorBundlePrefixes"])
    text = Path(source).read_text()
    block = re.search(r"selfDrawingEditorBundlePrefixes\s*=\s*\[(.*?)\]", text, re.DOTALL)
    if not block:
        raise RuntimeError(f"selfDrawingEditorBundlePrefixes not found in {source}")
    return re.findall(r'"([^"]+)"', block.group(1))


def expectation(bundle, prefixes):
    return "sent-unverified" if any(bundle.startswith(prefix) for prefix in prefixes) else "confirmed"


def field_mode(target, expected):
    if expected == "sent-unverified":
        return "none"
    return "suffix" if target.preparation == "receiver" else "exact"


def marker_for(token):
    return f"Airdraft insertion fixture {token}"


def inserted_text(token):
    return f" Delivery {token} succeeded."


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def evaluate(case, report, hashes, evidence=None):
    """Classify one case as passed, failed or unverified with a reason."""
    if report is None:
        return "failed", "the Debug app wrote no result.json"
    if report.get("error"):
        # Every fixture error is thrown before the production insertion runs.
        return "unverified", f"{PREPARATION_FAILURE}: {report['error']}"
    if report.get("binarySHA256") != hashes:
        return "failed", "result came from a different Debug build"
    if (report.get("fixtureToken") != case["token"] or report.get("targetBundle") != case["bundleID"]
            or report.get("requestedMethod") != case["method"]):
        return "failed", "result does not belong to this case"
    if type(report.get("deliveryCallbacks")) is not int or report["deliveryCallbacks"] != 1:
        return "failed", f"expected one delivery, saw {report.get('deliveryCallbacks')!r}"
    if report.get("notice") != "":
        return "failed", f"unexpected notice: {report.get('notice')!r}"
    if report.get("reportedMethod") != "paste" or report.get("fieldMode") != case["fieldMode"]:
        return "failed", f"reported {report.get('reportedMethod')!r} in field mode {report.get('fieldMode')!r}"
    if case["expectation"] == "confirmed":
        if not (report.get("status") == "passed" and report.get("delivery") == "delivered"
                and report.get("actualTextMatches") is True):
            return "failed", f"delivery {report.get('delivery')!r} without the expected field text"
    elif not (report.get("status") == "passed" and report.get("delivery") == "sentUnverified"):
        return "failed", f"expected the documented sent-unverified paste, saw {report.get('delivery')!r}"
    if case["preparation"] == "receiver":
        if evidence is None:
            return "failed", "the terminal receiver recorded no evidence"
        pastes = evidence.get("pastes")
        if pastes != [inserted_text(case["token"])]:
            count = len(pastes) if isinstance(pastes, list) else "no"
            return "failed", f"the receiver saw {count} paste(s), expected exactly the inserted text once"
        return "passed", "receiver read exactly one bracketed paste with the inserted text"
    if case["expectation"] == "sent-unverified":
        return "passed", "sent unverified as documented; this editor exposes no readable text"
    return "passed", "actual field text matched"


def summarize(cases):
    statuses = {case["status"] for case in cases}
    if not cases:
        return "unverified", 2
    if "failed" in statuses:
        return "failed", 1
    if statuses == {"passed"}:
        return "passed", 0
    return "unverified", 2


# MARK: - Debug app actions


def run_action(app, data, arguments, launcher, timeout):
    """Run one LocalE2E action and return its result.json (or None)."""
    data.mkdir(parents=True)
    argv = ["--e2e-local", str(data), *arguments]
    if launcher == "open":
        # LaunchServices makes the Debug app its own responsible process, so its
        # own Accessibility grant applies; -g keeps the fixture app frontmost.
        command = ["open", "-W", "-n", "-g", str(app), "--args", *argv]
        env = None
    else:
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        command = [str(app / "Contents/MacOS" / info["CFBundleExecutable"]), *argv]
        env = {name: os.environ[name] for name in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG")
               if name in os.environ}
    with (data.parent / f"{data.name}.log").open("w") as log:
        try:
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(["pkill", "-f", f"--e2e-local {data}"], capture_output=True)
    result = data / "result.json"
    try:
        return json.loads(result.read_text())
    except (OSError, ValueError):
        return None


def frontmost_bundle():
    """Frontmost app's bundle ID from LaunchServices (no Accessibility or Automation)."""
    try:
        front = subprocess.run(["lsappinfo", "front"], capture_output=True, text=True, timeout=5).stdout.strip()
        info = subprocess.run(["lsappinfo", "info", "-only", "bundleid", front],
                              capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r'"CFBundleIdentifier"="([^"]+)"', info)
    return match.group(1) if match else None


def wait_for_focus(bundle, deadline, ready=None, focus_file=None, settle=1.0):
    """Wait until the target stays frontmost (and a receiver is ready and focused)."""
    stable_since = None
    while time.monotonic() < deadline:
        ok = frontmost_bundle() == bundle
        if ready is not None:
            ok = ok and ready.exists()
        if focus_file is not None:
            ok = ok and focus_file.exists() and focus_file.read_text().strip() == "in"
        if ok:
            stable_since = stable_since or time.monotonic()
            if time.monotonic() - stable_since >= settle:
                return True
        else:
            stable_since = None
        time.sleep(0.2)
    return False


def write_web_fixture(path, marker):
    path.write_text(
        "<!doctype html><meta charset=utf-8><title>Airdraft insertion fixture</title>\n"
        "<p>Disposable Airdraft insertion fixture. Close this tab afterwards.</p>\n"
        f'<textarea id="fixture" autofocus rows="4" cols="80">{marker}</textarea>\n'
        "<script>const f = document.getElementById('fixture'); f.focus();"
        " f.setSelectionRange(f.value.length, f.value.length);</script>\n")


def prepare_field(case, target, app_path, fixture):
    """Create the disposable field's files and open them; return printed steps."""
    fixture.mkdir(parents=True)
    marker = case["marker"]
    steps = [target.instructions]
    if target.preparation == "document":
        path = fixture / "fixture.txt"
        path.write_text(marker)
        subprocess.run(["open", "-a", str(app_path), str(path)], check=True)
    elif target.preparation == "web":
        path = fixture / "fixture.html"
        write_web_fixture(path, marker)
        subprocess.run(["open", "-a", str(app_path), str(path)], check=True)
    elif target.preparation == "receiver":
        (fixture / "receiver.json").write_text(json.dumps({"marker": marker}))
        command = fixture / "receiver.command"
        command.write_text(f"#!/bin/sh\nexec /usr/bin/python3 -I '{SCRIPT}' --receiver '{fixture}'\n")
        command.chmod(0o700)
        if target.opens_receiver:
            subprocess.run(["open", "-a", str(app_path), str(command)], check=True)
        else:
            steps.append(f"Receiver command: '{command}'")
    else:
        steps.append(f"Marker: {marker}")
    return steps


def run_case(case, target, app_path, debug_app, hashes, args, log=print):
    fixture = Path(case["directory"]) / "fixture"
    steps = prepare_field(case, target, app_path, fixture)
    log(f"\n[{case['target']} / {case['method']}] Prepare the disposable field:")
    for step in steps:
        log(f"  {step}")
    receiver = target.preparation == "receiver"
    host = os.environ.get("__CFBundleIdentifier")
    deadline = time.monotonic() + args.focus_timeout
    focused = wait_for_focus(case["bundleID"], deadline,
                             ready=fixture / "ready" if receiver else None,
                             # The harness may itself run in this terminal app;
                             # then only the receiver's focus report proves focus.
                             focus_file=fixture / "focus" if receiver and host == case["bundleID"] else None)
    if not focused:
        return "unverified", f"the prepared field was not focused within {args.focus_timeout} s", None, None
    arguments = ["--e2e-action", "insert", "--e2e-target-bundle", case["bundleID"],
                 "--e2e-insertion-token", case["token"], "--e2e-insertion-method", case["method"],
                 "--e2e-insertion-field", case["fieldMode"]]
    report = run_action(debug_app, Path(case["data"]), arguments, args.launch, args.timeout)
    evidence = None
    if receiver:
        (fixture / "done").write_text("done\n")
        end = time.monotonic() + 5
        while time.monotonic() < end and not (fixture / "evidence.json").exists():
            time.sleep(0.1)
        try:
            evidence = json.loads((fixture / "evidence.json").read_text())
        except (OSError, ValueError):
            evidence = None
    status, reason = evaluate(case, report, hashes, evidence)
    return status, reason, report, evidence


def plan_cases(targets, prefixes, methods, output, gate_reports=None):
    cases = []
    for target, bundle, app_path in targets:
        expected = expectation(bundle, prefixes)
        for method in methods:
            token = str(uuid.uuid4()).upper()
            name = f"{slug(target.name)}-{method}"
            directory = output / "cases" / name
            gate = gate_reports is not None and bundle in GATE_BUNDLES
            cases.append({"target": target.name, "bundleID": bundle, "appPath": str(app_path), "method": method,
                          "token": token, "marker": marker_for(token), "expectation": expected,
                          "fieldMode": field_mode(target, expected), "preparation": target.preparation,
                          "directory": str(directory),
                          # Gate directories keep earlier attempts intact beside new ones.
                          "data": str((gate_reports / f"{name}-{token[:8].lower()}") if gate else (directory / "e2e")),
                          "releaseGate": gate, "status": "pending", "reason": ""})
    return cases


def access_instructions(app, bundle):
    return (f"Grant Accessibility once to the Debug identity, then rerun: System Settings > Privacy & Security > "
            f"Accessibility, turn on \"{app.stem}\" ({bundle}). If it is not listed, use + and choose {app}. "
            "This script never requests, grants or resets the permission.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, help="the Debug app whose binaries are verified")
    parser.add_argument("--output", type=Path, help="fresh evidence directory")
    parser.add_argument("--targets", help="comma-separated target names (default: every installed target)")
    parser.add_argument("--methods", default=",".join(METHODS), help="comma-separated insertion methods")
    parser.add_argument("--gate-reports", type=Path,
                        help="write TextEdit/Chrome cases here for verify-live-insertion.py (release prepare)")
    parser.add_argument("--launch", choices=("open", "direct"), default="open",
                        help="start the Debug app through LaunchServices (default) or as a child process")
    parser.add_argument("--focus-timeout", type=int, default=180, help="seconds to wait for each prepared field")
    parser.add_argument("--timeout", type=int, default=60, help="seconds for each Debug app action")
    parser.add_argument("--list", action="store_true", help="print installed targets and planned cases only")
    parser.add_argument("--no-launch", metavar="REASON",
                        help="launch and open nothing; record every planned case as UNVERIFIED with REASON")
    parser.add_argument("--applications-dir", type=Path, action="append", help=argparse.SUPPRESS)
    parser.add_argument("--receiver", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.receiver:
        return receive(args.receiver)
    if not args.list and (not args.app or not args.output):
        parser.error("--app and --output are required (except with --list)")
    methods = [method.strip() for method in args.methods.split(",") if method.strip()]
    if not methods or any(method not in METHODS for method in methods):
        parser.error(f"--methods must name {', '.join(METHODS)}")
    names = {name.strip().lower() for name in args.targets.split(",")} if args.targets else None
    if names and names - {target.name.lower() for target in TARGETS}:
        parser.error(f"unknown target in --targets; choose from {', '.join(t.name for t in TARGETS)}")
    targets = detect_targets(args.applications_dir or APPLICATION_DIRS, names)
    if args.list:
        prefixes = self_drawing_prefixes()
        for target, bundle, path in targets:
            print(f"{target.name}: {bundle} at {path} ({expectation(bundle, prefixes)}, {target.preparation})")
        missing = [t.name for t in TARGETS if (not names or t.name.lower() in names)
                   and t.name not in {found[0].name for found in targets}]
        print(f"Not installed: {', '.join(missing) or 'none'}")
        return 0
    app = args.app.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error(f"{output} must be empty")
    gate = load_gate()
    hashes = gate.app_hashes(app)
    summary = {"app": str(app), "binarySHA256": hashes, "launcher": args.launch, "methods": methods,
               "installedTargets": [{"target": t.name, "bundleID": b, "appPath": str(p)} for t, b, p in targets],
               "notInstalled": [t.name for t in TARGETS if (not names or t.name.lower() in names)
                                and t.name not in {found[0].name for found in targets}]}
    probe = None
    if args.no_launch is None:
        probe = run_action(app, output / "accessibility", ["--e2e-action", "accessibility"], args.launch, args.timeout)
    prefixes = self_drawing_prefixes(probe)
    cases = plan_cases(targets, prefixes, methods, output, args.gate_reports.resolve() if args.gate_reports else None)
    summary["selfDrawingEditorBundlePrefixes"] = prefixes
    reason = None
    if args.no_launch is not None:
        reason = f"not run: {args.no_launch.strip() or 'launching apps was not permitted'}"
        summary["accessibilityTrusted"] = None
    elif probe is None or probe.get("status") != "passed" or probe.get("binarySHA256") != hashes:
        reason = "the Debug app's accessibility probe failed or came from a different build"
        summary["accessibilityTrusted"] = None
    elif probe.get("trusted") is not True:
        summary["accessibilityTrusted"] = False
        reason = "Accessibility is not granted to the Debug app"
        summary["instructions"] = access_instructions(app, probe.get("bundleIdentifier", ""))
        print(f"UNVERIFIED: {reason}.\n{summary['instructions']}", file=sys.stderr)
    else:
        summary["accessibilityTrusted"] = True
    lookup = {target.name: target for target in TARGETS}
    for case in cases:
        if reason:
            case["status"], case["reason"] = "unverified", reason
        else:
            status, why, report, evidence = run_case(case, lookup[case["target"]], Path(case["appPath"]),
                                                     app, hashes, args)
            case.update(status=status, reason=why, report=report, evidence=evidence)
        print(f"{case['status'].upper()}: {case['target']} / {case['method']} ({case['expectation']}): {case['reason']}",
              flush=True)
    summary["status"], code = summarize(cases)
    summary["cases"] = cases
    (output / "matrix.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Insertion matrix {summary['status']}: {len(cases)} case(s); evidence {output / 'matrix.json'}")
    return code


# MARK: - Terminal receiver


PASTE_START, PASTE_END = b"\x1b[200~", b"\x1b[201~"
FOCUS_IN, FOCUS_OUT = b"\x1b[I", b"\x1b[O"


def parse_terminal_input(data):
    """Split raw terminal input into bracketed pastes, focus events and stray bytes."""
    pastes, focus, stray, index = [], [], 0, 0
    while index < len(data):
        if data.startswith(PASTE_START, index):
            end = data.find(PASTE_END, index + len(PASTE_START))
            if end < 0:
                break  # incomplete paste; wait for more input
            pastes.append(data[index + len(PASTE_START):end].decode("utf-8", "replace"))
            index = end + len(PASTE_END)
        elif data.startswith(FOCUS_IN, index) or data.startswith(FOCUS_OUT, index):
            focus.append("in" if data.startswith(FOCUS_IN, index) else "out")
            index += len(FOCUS_IN)
        else:
            stray += 1
            index += 1
    return pastes, focus, stray, index


def receive(directory, timeout=600):
    """Prompt-less receiver: prints the marker, records bracketed pastes and focus."""
    import termios
    config = json.loads((directory / "receiver.json").read_text())
    descriptor = sys.stdin.fileno()
    previous = termios.tcgetattr(descriptor)
    raw = termios.tcgetattr(descriptor)
    raw[3] &= ~(termios.ECHO | termios.ICANON)
    data, pastes, focus, stray, echoed = b"", [], [], 0, 0
    try:
        termios.tcsetattr(descriptor, termios.TCSANOW, raw)
        # Clear scrollback and screen, enable bracketed paste and focus reports.
        sys.stdout.write("\x1b[3J\x1b[H\x1b[2J\x1b[?2004h\x1b[?1004h" + config["marker"])
        sys.stdout.flush()
        (directory / "ready").write_text("ready\n")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and not (directory / "done").exists():
            readable, _, _ = select.select([descriptor], [], [], 0.1)
            if not readable:
                continue
            data += os.read(descriptor, 4096)
            pastes, focus, stray, _ = parse_terminal_input(data)
            if focus:
                (directory / "focus").write_text(focus[-1] + "\n")
            while echoed < len(pastes):
                # Echo the paste so the screen (and its accessible text) shows it.
                sys.stdout.write(pastes[echoed])
                sys.stdout.flush()
                echoed += 1
    finally:
        sys.stdout.write("\x1b[?2004l\x1b[?1004l\r\n[Airdraft insertion fixture finished; close this window]\r\n")
        sys.stdout.flush()
        termios.tcsetattr(descriptor, termios.TCSANOW, previous)
        (directory / "evidence.json").write_text(json.dumps(
            {"pastes": pastes, "focusEvents": focus, "strayBytes": stray}, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
