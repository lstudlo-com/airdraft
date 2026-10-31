#!/usr/bin/env python3
"""Maintain and check the iOS app's String Catalogs.

  sync   Merge the strings the compiler extracted during the last Debug
         simulator build into the iOS catalogs (what Xcode's IDE does on build).
  check  Fail when a key lacks a translated value in a shipped language
         (Config/languages.json), a translation's placeholders differ, a key is
         stale, an App Shortcut phrase drops ${applicationName}, or project.yml's
         CFBundleLocalizations differs from the list.

Build first (`moon run ios:build`), then `sync`, translate, and `check`.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import localization as shared  # noqa: E402  (the Mac app's catalog helpers)

CATALOGS = {
    "app": IOS / "Airdraft/Resources/Localizable.xcstrings",
    "shared": IOS / "Shared/Shared.xcstrings",
    "keyboard": IOS / "Keyboard/Localizable.xcstrings",
    "widgets": IOS / "Widgets/Localizable.xcstrings",
    "infoplist": IOS / "Airdraft/Resources/InfoPlist.xcstrings",
    "appshortcuts": IOS / "Airdraft/Resources/AppShortcuts.xcstrings",
}
# Which build targets' extracted strings feed each synced catalog.
SYNCED = {
    "app": ["Airdraft"],
    "shared": ["Airdraft", "AirdraftKeyboard", "AirdraftWidgets"],
    "keyboard": ["AirdraftKeyboard"],
    "widgets": ["AirdraftWidgets"],
}


def objroot():
    output = subprocess.run(
        ["xcodebuild", "-project", str(IOS / "AirdraftiOS.xcodeproj"), "-scheme", "Airdraft",
         "-configuration", "Debug", "-destination", "generic/platform=iOS Simulator", "-showBuildSettings"],
        capture_output=True, text=True, check=True).stdout
    match = re.search(r"^\s*OBJROOT = (.+)$", output, re.M)
    if not match:
        raise SystemExit("Could not find the build's OBJROOT.")
    return Path(match.group(1).strip())


def sync(_args):
    base = objroot() / "AirdraftiOS.build"
    for name, targets in SYNCED.items():
        files = sorted(path for target in targets
                       for path in base.glob(f"Debug-iphonesimulator/{target}.build/**/*.stringsdata"))
        if not files:
            raise SystemExit(f"No extracted strings for {name}. Build the Debug scheme for the simulator first.")
        subprocess.run(["xcrun", "xcstringstool", "sync", str(CATALOGS[name]), "--stringsdata", *map(str, files)],
                       check=True)
        count = len(json.loads(CATALOGS[name].read_text())["strings"])
        print(f"{name}: {count} keys after sync from {len(files)} files")
    return 0


def bundle_localizations():
    match = re.search(r"CFBundleLocalizations:\s*\[([^\]]*)\]", (IOS / "project.yml").read_text())
    return [code.strip() for code in match.group(1).split(",")] if match else []


def check(_args):
    errors, totals = [], []
    expected = sorted((shared.LANGUAGE_CONFIG["source"],) + shared.LANGUAGES)
    if sorted(bundle_localizations()) != expected:
        errors.append(f"apps/ios/project.yml CFBundleLocalizations {bundle_localizations()} differs from {expected}")
    for name, path in CATALOGS.items():
        catalog = json.loads(path.read_text())
        source = catalog.get("sourceLanguage", "en")
        strings = catalog.get("strings", {})
        translated = dict.fromkeys(shared.LANGUAGES, 0)
        for key, entry in strings.items():
            if entry.get("shouldTranslate") is False or not key.strip():
                for language in shared.LANGUAGES:
                    translated[language] += 1
                continue
            if entry.get("extractionState") == "stale":
                errors.append(f"{name}: stale key no longer used in source: {key!r}")
                continue
            english = shared.source_text(entry, key, source)
            for language in shared.LANGUAGES:
                units = shared.string_units(entry, language)
                if not units or any(u.get("state") != "translated" or not u.get("value", "").strip() for u in units):
                    errors.append(f"{name}: missing {language} translation: {key!r}")
                    continue
                values = [u["value"] for u in units]
                if any(sorted(shared.placeholders(v)) != sorted(shared.placeholders(english)) for v in values):
                    errors.append(f"{name}: {language} placeholders differ from source: {key!r}")
                    continue
                if "${applicationName}" in english and any("${applicationName}" not in v for v in values):
                    errors.append(f"{name}: {language} drops ${{applicationName}}: {key!r}")
                    continue
                translated[language] += 1
        counts = ", ".join(f"{language} {translated[language]}/{len(strings)}" for language in shared.LANGUAGES)
        totals.append(f"{name}: {counts} keys translated")
    print("\n".join(totals))
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} localization error(s).", file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("sync").set_defaults(run=sync)
    commands.add_parser("check").set_defaults(run=check)
    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
