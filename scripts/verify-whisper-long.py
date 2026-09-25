#!/usr/bin/env python3
"""Opt-in real Whisper regression through a built Debug app and local model files.

Example: python3 scripts/verify-whisper-long.py --app /tmp/Test.app \
    --models /tmp/test-models --audio /tmp/long.wav --tail 'purple elephant'
The WAV must exceed 30 seconds unless --allow-short is passed for short speech.
All app data is written to a fresh temporary
directory; the caller must provide already downloaded models and a Debug build.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import signal
import sqlite3
import subprocess
import tempfile
import time
import wave


def normalized(text):
    return " ".join(text.casefold().split())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--audio", type=Path, required=True)
    parser.add_argument("--tail", required=True, help="Distinct words spoken after 30 seconds")
    parser.add_argument("--allow-short", action="store_true", help="Check a short utterance using --tail as its expected text")
    args = parser.parse_args()
    with wave.open(str(args.audio)) as audio:
        duration = audio.getnframes() / audio.getframerate()
    if (duration <= 30 and not args.allow_short) or duration <= 0 or not args.tail.strip():
        parser.error("Provide audio longer than 30 seconds and a nonempty tail marker.")
    with (args.app / "Contents/Info.plist").open("rb") as file:
        bundle = plistlib.load(file)
    if bundle.get("CFBundleIdentifier") != "com.lstudlo.app.airdraft.debug":
        parser.error("Use the Debug app; Release builds have no isolated E2E entry point.")
    executable = bundle["CFBundleExecutable"]
    binary = args.app / "Contents/MacOS" / executable
    directory = Path(tempfile.mkdtemp(prefix="airdraft-whisper-regression-"))
    env = {name: os.environ[name] for name in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "LANG") if name in os.environ}
    env["AIRDRAFT_E2E_MODEL_ROOT"] = str(args.models.resolve())
    command = [str(binary.resolve()), "--e2e-local", str(directory), "--e2e-action", "transcribe",
               "--e2e-model", "whisper:turbo", "--e2e-audio", str(args.audio.resolve())]
    started = time.monotonic()
    evidence = {"directory": str(directory), "audioSeconds": duration, "tail": args.tail}
    with (directory / "run.log").open("w") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            evidence["exitCode"] = process.wait(timeout=90)
        except subprocess.TimeoutExpired:
            evidence["timedOut"] = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                evidence["exitCode"] = process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                evidence["exitCode"] = process.wait(timeout=3)
    evidence["elapsedSeconds"] = round(time.monotonic() - started, 3)
    report_path = directory / "result.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    evidence["appReport"] = report
    records = []
    database = directory / "history.sqlite"
    if database.exists():
        with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
            connection.row_factory = sqlite3.Row
            records = [dict(row) for row in connection.execute(
                "SELECT rawTranscript, finalText, audioSeconds, audioFilename, inserted FROM dictation")]
    evidence["history"] = records
    evidence["audioRetained"] = (len(records) == 1 and records[0]["audioFilename"] is not None
                                 and (directory / "Recordings" / records[0]["audioFilename"]).is_file())
    evidence["passed"] = (
        evidence.get("exitCode") == 0 and not evidence.get("timedOut")
        and report.get("status") == "passed"
        and normalized(args.tail) in normalized(report.get("raw", ""))
        and len(records) == 1 and records[0]["rawTranscript"] == report.get("raw")
        and records[0]["finalText"] == report.get("final")
        and abs(records[0]["audioSeconds"] - duration) < 0.1
        and evidence["audioRetained"] and not records[0]["inserted"]
    )
    (directory / "verification.json").write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(evidence, indent=2, ensure_ascii=False))
    return 0 if evidence["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
