#!/usr/bin/env python3
"""Create a DMG and signed Sparkle appcast locally. Does not publish anything."""

import argparse
import pathlib
import plistlib
import re
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET

from release_signing import inspect_app, inspect_dmg


def run(*args, capture=False):
    return subprocess.run([str(arg) for arg in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=pathlib.Path, required=True, help="Release airdraft.app")
    parser.add_argument("--sparkle-bin", type=pathlib.Path, required=True,
                        help="bin directory from the pinned Sparkle distribution")
    parser.add_argument("--download-url-prefix", required=True,
                        help="HTTPS release asset directory, ending with /")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("dist/updates"))
    parser.add_argument("--account", default="com.lstudlo.app.airdraft.sparkle")
    args = parser.parse_args()
    app = args.app.resolve()
    tools = args.sparkle_bin.resolve()
    output = args.output.resolve()
    prefix = urllib.parse.urlsplit(args.download_url_prefix)
    if prefix.scheme != "https" or not prefix.hostname or prefix.query or prefix.fragment or prefix.username is not None:
        parser.error("--download-url-prefix must be an HTTPS directory URL without credentials, query, or fragment")
    if not args.download_url_prefix.endswith("/"):
        parser.error("--download-url-prefix must end with /")
    for tool in ("generate_keys", "generate_appcast", "sign_update"):
        if not (tools / tool).is_file():
            parser.error(f"Missing Sparkle tool: {tools / tool}")

    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleIdentifier") != "com.lstudlo.app.airdraft":
        parser.error("Expected Airdraft's bundle identifier")
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version) or not re.fullmatch(r"[0-9]+", build):
        parser.error("Use a numeric dotted version and an increasing integer build number")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        parser.error("The app must require signed feeds and verify updates before extraction")
    feed = urllib.parse.urlsplit(info.get("SUFeedURL", ""))
    if feed.scheme != "https" or not feed.hostname:
        parser.error("The app must contain an HTTPS SUFeedURL")
    public_key = run(tools / "generate_keys", "--account", args.account, "-p", capture=True).stdout.strip()
    if public_key != info.get("SUPublicEDKey"):
        parser.error("The Keychain signing key does not match the public key embedded in the app")
    inspect_app(app)
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    if run("lipo", "-archs", executable, capture=True).stdout.strip() != "arm64":
        parser.error("This release workflow currently supports Apple Silicon builds only")
    if not (app / "Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib").is_file():
        parser.error("Missing MLX Metal library; build the app with Xcode")

    output.mkdir(parents=True, exist_ok=True)
    feed_path = output / "appcast.xml"
    if feed_path.exists():
        run(tools / "sign_update", "--account", args.account, "--verify", feed_path)
        ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
        previous = ET.parse(feed_path).findall(".//sparkle:version", ns)
        if any(int(item.text) >= int(build) for item in previous):
            parser.error("Increment CFBundleVersion before packaging a new update")
    archive = output / f"Airdraft-{version}-{build}-arm64.dmg"
    if archive.exists():
        parser.error(f"Refusing to overwrite {archive}")

    run("uv", "run", "--locked", pathlib.Path(__file__).with_name("build-dmg.py"),
        "--app", app, "--output", archive)
    inspect_dmg(archive)
    run(tools / "generate_appcast", "--account", args.account,
        "--download-url-prefix", args.download_url_prefix,
        "--maximum-deltas", "0", "--versions", build, "-o", feed_path, output)
    run(tools / "sign_update", "--account", args.account, "--verify", feed_path)
    print(f"Prepared {archive}\nSigned feed: {feed_path}\nNothing has been uploaded.")


if __name__ == "__main__":
    main()
