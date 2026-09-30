#!/usr/bin/env python3
"""Check that the isolated Debug harness rejects invalid inputs and failed reports."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if not str(info.get("CFBundleIdentifier", "")).startswith("com.lstudlo.app.airdraft.debug"):
        parser.error("Use a Debug build with the isolated E2E entry point.")
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    env = {name: os.environ[name] for name in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG") if name in os.environ}
    cases = [
        ("unknown-model", "inventory", ["--e2e-model", "not-a-model"]),
        ("unknown-profile", "transcribe", ["--e2e-audio", "/unused.wav", "--e2e-profile", "not-a-profile"]),
        ("unknown-refiner", "transcribe", ["--e2e-audio", "/unused.wav", "--e2e-refiner", "not-a-refiner"]),
        ("unknown-action", "not-an-action", []),
        ("insertion-missing-fixture", "insert", []),
        ("insertion-invalid-token", "insert", ["--e2e-target-bundle", "com.apple.TextEdit",
            "--e2e-insertion-token", "not-a-uuid", "--e2e-insertion-method", "auto"]),
        ("insertion-invalid-method", "insert", ["--e2e-target-bundle", "com.apple.TextEdit",
            "--e2e-insertion-token", "F0B51C04-E469-480E-A757-740A1952CD44", "--e2e-insertion-method", "invalid"]),
        ("missing-audio", "transcribe", []),
        ("unwritable-report", "inventory", []),
    ]
    with tempfile.TemporaryDirectory(prefix="airdraft-e2e-errors-") as temporary:
        root = Path(temporary)
        for name, action, extra in cases:
            directory = root / name
            directory.mkdir()
            report = directory / "result.json"
            if name == "unwritable-report":
                report.mkdir()
            with (directory / "run.log").open("w") as log:
                process = subprocess.Popen([str(binary), "--e2e-local", str(directory), "--e2e-action", action, *extra],
                                           env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=3)
                    raise RuntimeError(f"{name}: harness did not stop within its deadline")
            if code != 1:
                raise RuntimeError(f"{name}: expected failure exit 1, got {code}")
            if name != "unwritable-report":
                result = json.loads(report.read_text())
                if result.get("status") != "failed" or not result.get("error"):
                    raise RuntimeError(f"{name}: missing failed status or diagnostic")
            print(f"PASS: {name} rejects failure without a successful exit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
