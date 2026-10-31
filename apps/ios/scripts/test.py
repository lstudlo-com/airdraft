#!/usr/bin/env python3
"""Run the iOS unit tests on an available iPhone simulator.

Picks the newest available iPhone runtime unless AIRDRAFT_IOS_SIMULATOR names a
device UDID. The tests use disposable defaults suites and never record audio.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

IOS = Path(__file__).resolve().parents[1]


def simulator():
    chosen = os.environ.get("AIRDRAFT_IOS_SIMULATOR")
    if chosen:
        return chosen
    devices = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                                        capture_output=True, text=True, check=True).stdout)["devices"]
    runtimes = sorted((runtime for runtime in devices if ".iOS-" in runtime), reverse=True)
    for runtime in runtimes:
        for device in devices[runtime]:
            if device["name"].startswith("iPhone"):
                return device["udid"]
    raise SystemExit("No iPhone simulator is available. Install one with 'xcodebuild -downloadPlatform iOS'.")


def main():
    command = ["xcodebuild", "-project", str(IOS / "AirdraftiOS.xcodeproj"), "-scheme", "Airdraft",
               "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={simulator()}",
               "-skipPackagePluginValidation", "-skipMacroValidation", "-packageAuthorizationProvider", "netrc",
               "-onlyUsePackageVersionsFromResolvedFile", "test", *sys.argv[1:]]
    return subprocess.run(command).returncode


if __name__ == "__main__":
    raise SystemExit(main())
