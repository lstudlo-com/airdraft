#!/usr/bin/env python3
"""Build a licensed Debug app using only validated Polar Sandbox settings."""
import json
from pathlib import Path
import subprocess
import sys

from licensing import build_settings, verify_app
from release import ROOT, xcodegen
from swiftpm_lock import restore, verify


def main():
    # Validate before building. An unfinished sandbox must not borrow live IDs,
    # open production checkout, or fall back to an unlocked licensing test.
    settings = build_settings(ROOT / "scripts/licensing-sandbox.json", environment="sandbox")
    subprocess.run([str(xcodegen()), "generate"], cwd=ROOT, check=True)
    restore(ROOT)
    command = ["xcodebuild", "-project", "airdraft.xcodeproj", "-scheme", "airdraft",
               "-configuration", "Debug", "-skipPackagePluginValidation", "-skipMacroValidation",
               "-packageAuthorizationProvider", "netrc", "-onlyUsePackageVersionsFromResolvedFile", *settings]
    subprocess.run([*command, "build"], cwd=ROOT, check=True)
    verify(ROOT)
    result = subprocess.check_output([*command, "-showBuildSettings", "-json"], cwd=ROOT, text=True)
    built = next(item["buildSettings"] for item in json.loads(result) if item["target"] == "airdraft")
    app = Path(built["TARGET_BUILD_DIR"]) / built["FULL_PRODUCT_NAME"]
    verify_app(app, settings)
    if built["PRODUCT_BUNDLE_IDENTIFIER"] != "com.lstudlo.app.airdraft.debug":
        raise RuntimeError("Sandbox must use the separate Debug app identity")
    print(f"Verified Polar Sandbox Debug app: {app}")
    print("Open this app explicitly; /Applications/airdraft.app remains the production Release.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Sandbox build blocked: {error}", file=sys.stderr)
        sys.exit(1)
