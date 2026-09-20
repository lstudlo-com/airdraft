#!/usr/bin/env python3
"""Verify the real updater in a temporary app, without changing Airdraft's data."""

import argparse
import functools
import http.server
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sparkle", type=pathlib.Path, required=True,
                        help="Extracted Sparkle distribution with Sparkle.framework and bin")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    sparkle = args.sparkle.resolve()
    account = "com.lstudlo.app.airdraft.sparkle"
    public_key = run(sparkle / "bin/generate_keys", "--account", account, "-p",
                     capture_output=True, text=True).stdout.strip()
    bundle_id = "com.lightiichen.airdraft.updater-test." + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="airdraft-updater-test-") as temp:
        work = pathlib.Path(temp)
        app = work / "UpdaterTest.app"
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        run("ditto", sparkle / "Sparkle.framework", app / "Contents/Frameworks/Sparkle.framework")
        run("swiftc", "-parse-as-library", "-swift-version", "5", "-F", sparkle,
            "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            root / "Sources/App/App/AppUpdater.swift", root / "scripts/verify-updater.swift",
            "-o", macos / "UpdaterTest")
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
            functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(work)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        feed = work / "appcast.xml"
        feed.write_text('''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>Updater verification</title><item><title>Version 2</title>
<sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>
<enclosure url="https://example.invalid/update.zip" length="1" type="application/octet-stream"
sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="/>
</item></channel></rss>''')
        # This probe never downloads the archive. Its feed signature is real.
        run(sparkle / "bin/sign_update", "--account", account, feed)
        info = {"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "UpdaterTest",
                "CFBundleName": "UpdaterTest", "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1.0",
                "LSMinimumSystemVersion": "15.0",
                "SUFeedURL": f"http://127.0.0.1:{server.server_port}/appcast.xml",
                "SUPublicEDKey": public_key, "SURequireSignedFeed": True,
                "SUVerifyUpdateBeforeExtraction": True, "SUEnableAutomaticChecks": False,
                "SUAutomaticallyUpdate": False,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        run("codesign", "--force", "--sign", "-", app)
        try:
            for mode in ("policy", "valid-feed", "tampered-feed"):
                if mode == "tampered-feed":
                    feed.write_bytes(feed.read_bytes().replace(b"Version 2", b"Version 3"))
                run(macos / "UpdaterTest", mode, timeout=25)

            # Build an actual ad-hoc signed update and exercise Sparkle's
            # downloader and out-of-process installer, entirely inside temp.
            target = work / "new/UpdaterTest.app"
            run("ditto", app, target)
            target_info = dict(info, CFBundleVersion="2", CFBundleShortVersionString="0.1.1")
            (target / "Contents/Info.plist").write_bytes(plistlib.dumps(target_info))
            run("codesign", "--force", "--sign", "-", target)
            archives = work / "updates"
            archives.mkdir()
            archive = archives / "update.zip"
            run("ditto", "-c", "-k", "--keepParent", target, archive)
            feed.unlink()
            run(sparkle / "bin/generate_appcast", "--account", account,
                "--download-url-prefix", f"http://127.0.0.1:{server.server_port}/updates/",
                "--maximum-deltas", "0", "-o", feed, archives)
            original_archive = archive.read_bytes()
            changed = bytearray(original_archive)
            changed[len(changed) // 2] ^= 1
            archive.write_bytes(changed)
            run(macos / "UpdaterTest", "tampered-download", timeout=40)
            if plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleVersion"] != "1":
                raise RuntimeError("Tampered archive replaced the app")
            archive.write_bytes(original_archive)
            run(macos / "UpdaterTest", "install", timeout=40)
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                try:
                    installed = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                    if installed["CFBundleVersion"] == "2":
                        break
                except FileNotFoundError:
                    pass
                time.sleep(0.2)
            else:
                raise RuntimeError("Sparkle did not replace the fixture app after quit")
            run("codesign", "--verify", "--deep", "--strict", app)
            print("PASS: ad-hoc signed version 1 → 2 installed on quit", flush=True)
            run(macos / "UpdaterTest", "installed", timeout=25)
        finally:
            server.shutdown()
            subprocess.run(["defaults", "delete", bundle_id], capture_output=True)
            shutil.rmtree(pathlib.Path.home() / "Library/Caches" / bundle_id, ignore_errors=True)


if __name__ == "__main__":
    main()
