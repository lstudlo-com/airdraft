#!/usr/bin/env python3
"""Maintain and check Airdraft's String Catalogs.

  check   Fail when a catalog key lacks a current translation in a shipped
          language (zh-Hans, zh-Hant), a translation drops or adds a
          placeholder, or a key is stale.
  sync    Merge the strings the compiler extracted during the last Debug build
          into the app and AirdraftCore catalogs (what Xcode's IDE does on build).
  audit   List Swift string literals that look like interface copy but were not
          extracted, i.e. text that bypasses localization. Informational.

Build first (`moon run airdraft:build`), then `sync`, translate, and `check`.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("zh-Hans", "zh-Hant")
CATALOGS = {
    "app": ROOT / "Sources/App/Localizable.xcstrings",
    "infoplist": ROOT / "Sources/App/InfoPlist.xcstrings",
    "appshortcuts": ROOT / "Sources/App/AppShortcuts.xcstrings",
    "core": ROOT / "Packages/AirdraftCore/Sources/AirdraftCore/Resources/Localizable.xcstrings",
}
SOURCES = {
    "app": ROOT / "Sources/App",
    "core": ROOT / "Packages/AirdraftCore/Sources/AirdraftCore",
}
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDuUxXoOfeEgGcCsSpaAF%])")


def placeholders(text):
    """Placeholder types in argument order; positional forms may be reordered."""
    found, position = {}, 0
    for match in PLACEHOLDER.finditer(text):
        if match.group(2) == "%":
            continue
        position += 1
        index = int(match.group(1)) if match.group(1) else position
        kind = match.group(2).lower()
        found[index] = "d" if kind in "dioux" else kind
    return [found[i] for i in sorted(found)]


def string_units(entry, language):
    """All string units for a language, including plural and device variations."""
    localization = entry.get("localizations", {}).get(language)
    if localization is None:
        return None
    units = []

    def walk(node):
        if isinstance(node, dict):
            if "stringUnit" in node:
                units.append(node["stringUnit"])
            for key, value in node.items():
                if key != "stringUnit":
                    walk(value)
    walk(localization)
    return units


def check(_args):
    errors, totals = [], []
    for name, path in CATALOGS.items():
        catalog = json.loads(path.read_text())
        source = catalog.get("sourceLanguage", "en")
        strings = catalog.get("strings", {})
        translated = dict.fromkeys(LANGUAGES, 0)
        for key, entry in strings.items():
            if entry.get("shouldTranslate") is False or not key.strip():
                for language in LANGUAGES:
                    translated[language] += 1
                continue
            if entry.get("extractionState") == "stale":
                errors.append(f"{name}: stale key no longer used in source: {key!r}")
                continue
            english = entry.get("localizations", {}).get(source, {}).get("stringUnit", {}).get("value", key)
            for language in LANGUAGES:
                units = string_units(entry, language)
                if not units:
                    errors.append(f"{name}: missing {language} translation: {key!r}")
                    continue
                bad = [u for u in units if u.get("state") != "translated" or not u.get("value", "").strip()]
                if bad:
                    errors.append(f"{name}: {language} translation needs review ({bad[0].get('state')}): {key!r}")
                    continue
                expected = placeholders(english)
                for unit in units:
                    if sorted(placeholders(unit["value"])) != sorted(expected):
                        errors.append(f"{name}: {language} placeholders differ from source: {key!r} -> {unit['value']!r}")
                        break
                else:
                    translated[language] += 1
        counts = ", ".join(f"{language} {translated[language]}/{len(strings)}" for language in LANGUAGES)
        totals.append(f"{name}: {counts} keys translated")
    print("\n".join(totals))
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} localization error(s). Run scripts/localization.py sync after a Debug build, "
              "then translate the reported keys.", file=sys.stderr)
        return 1
    return 0


def build_intermediates():
    output = subprocess.run(
        ["xcodebuild", "-project", str(ROOT / "airdraft.xcodeproj"), "-scheme", "airdraft",
         "-configuration", "Debug", "-showBuildSettings"],
        capture_output=True, text=True, check=True).stdout
    match = re.search(r"^\s*OBJROOT = (.+)$", output, re.M)
    if not match:
        raise SystemExit("Could not find the build's OBJROOT.")
    return Path(match.group(1).strip())


def stringsdata(objroot):
    app = sorted((objroot / "airdraft.build/Debug/airdraft.build").rglob("*.stringsdata"))
    core = sorted((objroot / "AirdraftCore.build/Debug").rglob("*.stringsdata"))
    if not app or not core:
        raise SystemExit(f"No extracted strings under {objroot}. Build the Debug scheme first.")
    return {"app": app, "core": core}


def sync(args):
    objroot = Path(args.objroot) if args.objroot else build_intermediates()
    for name, files in stringsdata(objroot).items():
        subprocess.run(["xcrun", "xcstringstool", "sync", str(CATALOGS[name]), "--stringsdata", *map(str, files)],
                       check=True)
        count = len(json.loads(CATALOGS[name].read_text())["strings"])
        print(f"{name}: {count} keys after sync from {len(files)} files")
    return 0


def literals(text):
    """Yield (line, column, value, start, end) for Swift string literals, skipping comments.

    Columns are UTF-8 based like the compiler's; start/end are character offsets."""
    i, line, col, n = 0, 1, 1, len(text)

    def advance(count=1):
        nonlocal i, line, col
        for _ in range(count):
            if i < n and text[i] == "\n":
                line, col = line + 1, 1
            elif i < n:
                col += len(text[i].encode("utf-8"))  # the compiler reports UTF-8 columns
            i += 1

    while i < n:
        c = text[i]
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                advance()
            continue
        if text.startswith("/*", i):
            while i < n and not text.startswith("*/", i):
                advance()
            advance(2)
            continue
        if c == '"' or (c == "#" and text.startswith('#"', i)):
            raw = c == "#"
            start_line, start_col, start = line, col, i
            if raw:
                advance()
            triple = text.startswith('"""', i)
            advance(3 if triple else 1)
            value, interpolated = [], False
            while i < n:
                if triple and text.startswith('"""', i):
                    advance(3)
                    break
                if not triple and text[i] == '"':
                    advance()
                    break
                if not raw and text.startswith("\\(", i):
                    # Interpolation: record a placeholder, then scan nested code.
                    value.append("%@")
                    interpolated = True
                    advance(2)
                    depth = 1
                    while i < n and depth:
                        if text[i] == '"':
                            # Nested literal inside the interpolation.
                            j = i + 1
                            while j < n and text[j] != '"':
                                j += 2 if text[j] == "\\" else 1
                            nested = text[i + 1:j]
                            yield (line, col, nested, i, j + 1)
                            advance(j - i + 1)
                            continue
                        depth += {"(": 1, ")": -1}.get(text[i], 0)
                        advance()
                    continue
                if not raw and text[i] == "\\":
                    value.append(text[i:i + 2])
                    advance(2)
                    continue
                value.append(text[i])
                advance()
            if raw and i < n and text[i] == "#":
                advance()
            yield (start_line, start_col, "".join(value), start, i)
            continue
        advance()


UI_EXCLUDES = re.compile(
    r"accessibilityIdentifier\(|systemImage:|systemName:|Image\(\"|forKey:|UserDefaults|RenderMode\.value|"
    r"Logger|log\.(?:info|debug|error|notice|warning|fault)|\.log\(|print\(|NSLog|fatalError|precondition|"
    r"assert|Notification\.Name|URL\(string:|identifier:|\.tag\(|keyEquivalent|withExtension|forResource|"
    r"\.font\(|named:|id: \"|case .* = \"|rawValue|AIRDRAFT_|environment\[|arguments")


def looks_like_copy(value):
    if len(value) < 2 or not re.search(r"[A-Za-z]{2}", value):
        return False
    if re.fullmatch(r"[a-z0-9_.\-/:%@]+", value):  # identifiers, keys, paths
        return False
    if re.match(r"(https?|x-apple|file)://|com\.|/", value) or "\\n" == value:
        return False
    if re.fullmatch(r"[a-z]{2,3}(-[A-Za-z0-9]{2,8})+|[A-Z][a-z]+(-[A-Z][a-z]+)*-[A-Za-z0-9-]+|[A-Z][A-Za-z]+(-[A-Z][A-Za-z]+)+", value):
        return False  # locale codes and header names
    return bool(re.search(r"[A-Z]", value) or " " in value)


def audit(args):
    objroot = Path(args.objroot) if args.objroot else build_intermediates()
    extracted = {}
    for files in stringsdata(objroot).values():
        for path in files:
            data = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                                             capture_output=True, text=True, check=True).stdout)
            source = data.get("source")
            for table in data.get("tables", {}).values():
                for item in table:
                    location = item.get("location", {})
                    extracted.setdefault(source, set()).add((location.get("startingLine"), location.get("startingColumn")))
    count = 0
    for name, root in SOURCES.items():
        for path in sorted(root.rglob("*.swift")):
            if not args.include_debug and "/Debug/" in str(path):
                continue
            lines = path.read_text().splitlines()
            seen = extracted.get(str(path), set())
            text = path.read_text()
            for line, col, value, start, _ in literals(text):
                if (line, col) in seen or not looks_like_copy(value):
                    continue
                # Already wrapped for localization, or metadata of a localized string.
                if re.search(r"(localized:|defaultValue:|comment:)\s*$", text[max(0, start - 40):start]):
                    continue
                context = lines[line - 1] if line - 1 < len(lines) else ""
                if UI_EXCLUDES.search(context):
                    continue
                count += 1
                suffix = f"  | {context.strip()[:140]}" if args.context else ""
                print(f"{path.relative_to(ROOT)}:{line}:{col}: {value!r}{suffix}")
    print(f"{count} candidate literal(s) not extracted", file=sys.stderr)
    return 0


def wrap(args):
    """Wrap literals at path:line:column in String(localized:); Core literals use its bundle.

    Wrap every branch of a ternary: the compiler extracts only the first branch when a
    ternary of literals is typed as LocalizedStringResource."""
    targets = {}
    for spec in args.locations:
        path, line, col = spec.rsplit(":", 2)
        targets.setdefault(Path(path), set()).add((int(line), int(col)))
    for path, wanted in targets.items():
        full = path if path.is_absolute() else ROOT / path
        text = full.read_text()
        core = "Packages/AirdraftCore" in str(full)
        spans = [(start, end) for line, col, _, start, end in literals(text) if (line, col) in wanted]
        if len(spans) != len(wanted):
            raise SystemExit(f"{path}: found {len(spans)} of {len(wanted)} literals")
        for start, end in sorted(spans, reverse=True):
            literal = text[start:end]
            replacement = f"String(localized: {literal}, bundle: .module)" if core else f"String(localized: {literal})"
            text = text[:start] + replacement + text[end:]
        full.write_text(text)
        print(f"{path}: wrapped {len(spans)}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check").set_defaults(run=check)
    for name, run in (("sync", sync), ("audit", audit)):
        command = commands.add_parser(name)
        command.add_argument("--objroot", help="Build intermediates (default: from xcodebuild -showBuildSettings)")
        if name == "audit":
            command.add_argument("--include-debug", action="store_true")
            command.add_argument("--context", action="store_true", help="Show the source line")
        command.set_defaults(run=run)
    wrapper = commands.add_parser("wrap")
    wrapper.add_argument("locations", nargs="+", help="path:line:column from audit")
    wrapper.set_defaults(run=wrap)
    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
