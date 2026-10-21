#!/usr/bin/env python3
"""Generate and verify Airdraft's third-party notices.

The notices are built from the resolved SwiftPM graph (root Package.resolved,
including transitive pins and binary targets), the pinned Sherpa-ONNX native
inputs and the bundled model brand assets. ThirdParty/acknowledgements.json
records the reviewed license of every license file; an unreviewed dependency,
license file or unrecognized license text fails instead of being guessed.

  generate      rewrite the bundled notices from resolved SwiftPM checkouts
  check         regenerate in memory and require identical committed output
  check-inputs  without checkouts, require the recorded input fingerprint
                to match Package.resolved, native inputs, policy and texts
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
POLICY = Path("ThirdParty/acknowledgements.json")
TEXTS = Path("ThirdParty/licenses")
OUTPUT = Path("Sources/App/Resources/Acknowledgements.txt")
RESOLVED = Path("Package.resolved")
NATIVE_INPUTS = Path("Packages/SherpaOnnxKit/native-inputs.json")
BRAND_DOC = Path("docs/model-brand-assets.md")
ASSETS = Path("Sources/App/Assets.xcassets")
FINGERPRINT_FILES = [RESOLVED, NATIVE_INPUTS, Path("Packages/TranscribeCppKit/Package.swift"),
                     Path("Packages/AirdraftCore/Package.swift"), POLICY, BRAND_DOC,
                     Path("scripts/acknowledgements.py")]
FINGERPRINT_LINE = "Inputs SHA-256: "
SOURCE_URL = "https://github.com/lstudlo-com/airdraft"

LICENSE_FILE = re.compile(r"^(.*[-_.])?(licen[cs]e|copying|notices?)([-_.].*)?$", re.IGNORECASE)
CODE_SUFFIXES = {".swift", ".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm", ".js", ".ts", ".py",
                 ".json", ".yml", ".yaml", ".sh", ".metal", ".plist"}
SKIPPED_DIRECTORIES = {".git", ".github", "tests", "test", "integrationtests", "docs", "doc",
                       "documentation", "examples", "example", "benchmarks", "benchmark"}

# Marker phrases are matched on lowercase text with collapsed whitespace.
MARKERS = {
    "apache-2.0": ["apache license version 2.0, january 2004",
                   "licensed under the apache license, version 2.0"],
    "swift-exception": ["runtime library exception"],
    "mit": ["permission is hereby granted, free of charge, to any person obtaining a copy of this software"],
    "zlib": ["altered source versions must be plainly marked as such"],
    "mpl-2.0": ["mozilla public license version 2.0"],
    "gpl-3.0": ["gnu general public license version 3, 29 june 2007"],
    "unlicense": ["this is free and unencumbered software released into the public domain"],
    "unicode": ["unicode data files"],
    "isc": ["permission to use, copy, modify, and/or distribute this software for any purpose "
            "with or without fee is hereby granted"],
    "bsl-1.0": ["boost software license - version 1.0"],
}
BSD = "redistribution and use in source and binary forms"
SPDX_KINDS = {
    "Apache-2.0": "apache-2.0", "Swift-exception": "swift-exception", "MIT": "mit",
    "Zlib": "zlib", "MPL-2.0": "mpl-2.0", "GPL-3.0-only": "gpl-3.0",
    "GPL-3.0-or-later": "gpl-3.0", "Unlicense": "unlicense", "Unicode-DFS-2016": "unicode",
    "ISC": "isc", "BSL-1.0": "bsl-1.0", "BSD-2-Clause": "bsd-2-clause",
    "BSD-3-Clause": "bsd-3-clause",
}
NOTICE = "notice"


class AcknowledgementError(RuntimeError):
    pass


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def normalize(data):
    """Text as shipped: UTF-8 without BOM, LF endings, no trailing spaces."""
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    text = text.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip() for line in text.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines) + "\n"


def detect(text):
    """Return the set of license kinds whose text appears in a license file."""
    flat = re.sub(r"\s+", " ", text.lower().replace("’", "'"))
    found = {kind for kind, phrases in MARKERS.items() if any(p in flat for p in phrases)}
    starts = [match.start() for match in re.finditer(re.escape(BSD), flat)]
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(flat)
        clause = flat[start:min(end, start + 2500)]
        found.add("bsd-3-clause" if ("endorse or promote" in clause or "neither the name" in clause)
                  else "bsd-2-clause")
    return found


def expected_kinds(expression):
    tokens = [t for t in re.split(r"\s+|[()]", expression) if t and t not in ("AND", "OR", "WITH")]
    unknown = [t for t in tokens if t not in SPDX_KINDS]
    if unknown or not tokens:
        raise AcknowledgementError(f"Unsupported license expression {expression!r}: {unknown}")
    return {SPDX_KINDS[t] for t in tokens}


def is_full_apache(text):
    return "terms and conditions for use, reproduction, and distribution" in re.sub(r"\s+", " ", text.lower())


def license_like(path):
    return (not path.name.startswith(".") and path.suffix.lower() not in CODE_SUFFIXES
            and bool(LICENSE_FILE.match(path.name)))


def scan(directory):
    """License-like files below a checkout or artifact, excluding test/doc trees."""
    found = []
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory)
        if any(part.lower() in SKIPPED_DIRECTORIES for part in relative.parts[:-1]):
            continue
        if path.is_file() and not path.is_symlink() and license_like(path):
            found.append(relative.as_posix())
    return found


def load_json(root, relative):
    path = root / relative
    if not path.is_file():
        raise AcknowledgementError(f"Missing {relative}")
    return json.loads(path.read_text())


def fingerprint(root):
    digest = hashlib.sha256()
    entries = [(p.as_posix(), (root / p).read_bytes()) for p in FINGERPRINT_FILES]
    texts = root / TEXTS
    for path in sorted(texts.rglob("*")) if texts.is_dir() else []:
        if path.is_file():
            entries.append((path.relative_to(root).as_posix(), path.read_bytes()))
    brands = sorted(p.name for p in (root / ASSETS).glob("ModelBrand*.imageset"))
    entries.append(("brand-imagesets", "\n".join(brands).encode()))
    for name, data in entries:
        digest.update(name.encode() + b"\0" + sha256_bytes(data).encode() + b"\n")
    return digest.hexdigest()


def recorded_fingerprint(text):
    for line in text.splitlines()[:20]:
        if line.startswith(FINGERPRINT_LINE):
            return line[len(FINGERPRINT_LINE):].strip()
    return None


def checkout_name(location):
    name = Path(urlsplit(location).path).name
    return name[:-4] if name.endswith(".git") else name


def git_head(path):
    result = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def default_source_packages(root):
    """SwiftPM's resolved checkouts for this checkout's Xcode build tree."""
    result = subprocess.run(
        ["xcodebuild", "-project", "airdraft.xcodeproj", "-scheme", "airdraft", "-configuration", "Debug",
         "-skipPackagePluginValidation", "-skipMacroValidation", "-packageAuthorizationProvider", "netrc",
         "-showBuildSettings", "-json"], cwd=root, capture_output=True, text=True)
    if result.returncode != 0:
        raise AcknowledgementError("Could not read Xcode build settings; pass --source-packages "
                                   "or build the app once so SwiftPM resolves its checkouts")
    settings = next(item["buildSettings"] for item in json.loads(result.stdout) if item["target"] == "airdraft")
    return Path(settings["BUILD_DIR"]).parents[1] / "SourcePackages"


class Builder:
    def __init__(self, root, source_packages):
        self.root = root
        self.packages = Path(source_packages)
        self.policy = load_json(root, POLICY)
        if self.policy.get("schema") != 1:
            raise AcknowledgementError("Unsupported acknowledgements policy schema")
        self.used_texts = set()
        self.seen_texts = {}
        self.apache_reference = None
        self.sections = []

    # Files ---------------------------------------------------------------

    def committed_text(self, relative):
        record = self.policy.get("texts", {}).get(relative)
        if record is None:
            raise AcknowledgementError(f"{relative} has no source record in {POLICY}")
        path = self.root / relative
        if not path.is_file():
            raise AcknowledgementError(f"Missing committed license text {relative}")
        data = path.read_bytes()
        if sha256_bytes(data) != record.get("sha256"):
            raise AcknowledgementError(f"{relative} differs from its recorded upstream text; "
                                       "refetch it and update its sha256 deliberately")
        self.used_texts.add(relative)
        return data

    def read(self, base, relative):
        if relative.startswith(TEXTS.as_posix() + "/"):
            return self.committed_text(relative)
        path = base / relative
        if not path.is_file():
            raise AcknowledgementError(f"Missing license file {path}")
        return path.read_bytes()

    def file_block(self, owner, label, data, expression):
        text = normalize(data)
        if expression != NOTICE:
            detected = detect(text)
            if not detected:
                raise AcknowledgementError(f"Unknown license text in {owner}: {label}")
            if detected != expected_kinds(expression):
                raise AcknowledgementError(
                    f"{owner}: {label} contains {sorted(detected)}, but the policy records {expression!r}")
        key = sha256_bytes(text.encode())
        heading = f"--- {label} ---"
        if key in self.seen_texts:
            return f"{heading}\nSame text as {self.seen_texts[key]} above.\n"
        self.seen_texts[key] = f"{owner}, {label}"
        if expression != NOTICE and "apache-2.0" in detect(text) and is_full_apache(text):
            self.apache_reference = self.apache_reference or f"{owner}, {label}"
        if expression != NOTICE and "apache-2.0" in detect(text) and not is_full_apache(text):
            if self.apache_reference is None:
                raise AcknowledgementError(f"{owner}: {label} needs a preceding full Apache-2.0 text")
            text += f"\nThe full Apache License 2.0 text appears under {self.apache_reference} above.\n"
        return f"{heading}\n{text}"

    def files(self, owner, base, mapping):
        if not mapping:
            raise AcknowledgementError(f"{owner} has no license files in {POLICY}")
        return [self.file_block(owner, Path(name).name, self.read(base, name), expression)
                for name, expression in mapping.items()]

    @staticmethod
    def component_title(component):
        version = f" {component['version']}" if component.get("version") else ""
        return f"{component['name']}{version} ({component['license']})"

    def component_blocks(self, owner, base, components):
        blocks = []
        for component in components:
            summary = "Includes " + self.component_title(component)
            if component.get("source"):
                summary += f": {component['source']}"
            blocks.append(summary + "\n")
            blocks += self.files(f"{owner} / {component['name']}", base, component["files"])
        return blocks

    def covered(self, entry, found, owner):
        listed = set(entry.get("files", {}))
        for component in entry.get("components", []):
            listed |= set(component["files"])
        excluded = entry.get("excluded", {})
        for relative in found:
            if relative in listed or any(relative.startswith(prefix) for prefix in excluded):
                continue
            raise AcknowledgementError(f"{owner}: unreviewed license file {relative}; "
                                       f"add it to {POLICY} as a component file or exclusion")
        for relative in listed:
            if not relative.startswith("ThirdParty/") and relative not in found:
                raise AcknowledgementError(f"{owner}: recorded license file {relative} no longer exists")

    # Sections ------------------------------------------------------------

    def section(self, group, name, version, license, source, blocks, components=()):
        self.sections.append({"group": group, "name": name, "version": version, "license": license,
                              "source": source, "blocks": blocks,
                              "includes": [self.component_title(c) for c in components]})

    def swiftpm(self):
        resolved = load_json(self.root, RESOLVED)
        policy = self.policy.get("swiftpm", {})
        identities = {pin["identity"] for pin in resolved["pins"]}
        stale = sorted(set(policy) - identities)
        if stale:
            raise AcknowledgementError(f"{POLICY} lists packages that are no longer resolved: {stale}")
        checkouts = self.packages / "checkouts"
        for pin in sorted(resolved["pins"], key=lambda p: policy.get(p["identity"], {}).get("name", p["identity"]).lower()):
            identity = pin["identity"]
            entry = policy.get(identity)
            if entry is None:
                raise AcknowledgementError(f"New SwiftPM dependency {identity} ({pin['location']}); "
                                           f"review its license and add it to {POLICY}")
            checkout = checkouts / checkout_name(pin["location"])
            revision = pin["state"]["revision"]
            if not checkout.is_dir():
                raise AcknowledgementError(f"Missing SwiftPM checkout {checkout}; resolve packages first")
            if git_head(checkout) != revision:
                raise AcknowledgementError(f"{checkout} is not at the pinned revision {revision}; "
                                           "resolve packages with -onlyUsePackageVersionsFromResolvedFile")
            self.covered(entry, scan(checkout), identity)
            version = pin["state"].get("version") or f"revision {revision[:12]}"
            source = re.sub(r"\.git$", "", pin["location"])
            blocks = self.files(entry["name"], checkout, entry["files"])
            blocks += self.component_blocks(entry["name"], checkout, entry.get("components", []))
            self.section("Swift packages", entry["name"], version, entry["license"],
                         f"{source} ({revision[:12]})", blocks, entry.get("components", []))

    def binary_targets(self):
        state = load_json(self.packages, Path("workspace-state.json"))
        policy = self.policy.get("binaryTargets", {})
        artifacts = {f"{a['packageRef']['identity']}/{a['targetName']}": a for a in state["object"]["artifacts"]}
        stale = sorted(set(policy) - set(artifacts))
        if stale:
            raise AcknowledgementError(f"{POLICY} lists binary targets that are no longer resolved: {stale}")
        for key in sorted(artifacts, key=lambda k: policy.get(k, {}).get("name", k).lower()):
            artifact, entry = artifacts[key], policy.get(key)
            if entry is None:
                raise AcknowledgementError(f"New binary target {key}; review its license and add it to {POLICY}")
            if "coveredBy" in entry:
                continue
            if artifact["source"].get("url") != entry.get("url"):
                raise AcknowledgementError(f"Binary target {key} now downloads {artifact['source'].get('url')}; "
                                           "review its license and update the policy URL and texts")
            directory = self.packages / "artifacts" / key
            self.covered(entry, scan(directory) if directory.is_dir() else [], key)
            blocks = self.files(entry["name"], directory, entry["files"])
            blocks += self.component_blocks(entry["name"], directory, entry.get("components", []))
            self.section("Binary frameworks", entry["name"], entry["version"], entry["license"],
                         entry["source"], blocks, entry.get("components", []))

    def native(self):
        inputs = load_json(self.root, NATIVE_INPUTS)["libraries"]
        policy = self.policy.get("native", {})
        if sorted(policy) != sorted(item["id"] for item in inputs):
            raise AcknowledgementError(f"{POLICY} native entries differ from {NATIVE_INPUTS}")
        for item in inputs:
            entry = policy[item["id"]]
            if entry["version"] != item["version"]:
                raise AcknowledgementError(f"Native input {item['id']} is now {item['version']}; "
                                           f"refetch its license texts and update {POLICY}")
            blocks = self.files(entry["name"], self.root, entry["files"])
            blocks += self.component_blocks(entry["name"], self.root, entry.get("components", []))
            self.section("Native libraries", entry["name"], entry["version"], entry["license"],
                         entry["source"], blocks, entry.get("components", []))

    def brands(self):
        rows = []
        for line in (self.root / BRAND_DOC).read_text().splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
            if len(cells) == 2 and cells[0] not in ("Asset", "---") and not set(cells[0]) <= {"-"}:
                source = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 <\2>", cells[1])
                rows.append((cells[0], source))
        keys = {re.sub(r"[^a-z0-9]", "", name.split("/")[0].lower()): name for name, _ in rows}
        imagesets = sorted(p.name[len("ModelBrand"):-len(".imageset")]
                           for p in (self.root / ASSETS).glob("ModelBrand*.imageset"))
        missing = [n for n in imagesets if n.lower() not in keys]
        unused = [keys[k] for k in keys if k not in {n.lower() for n in imagesets}]
        if missing or unused:
            raise AcknowledgementError(f"{BRAND_DOC} and ModelBrand image sets disagree: "
                                       f"undocumented {missing}, without an image set {unused}")
        return rows

    def build(self):
        self.swiftpm()
        self.binary_targets()
        self.native()
        brands = self.brands()
        texts = {p.relative_to(self.root).as_posix() for p in (self.root / TEXTS).rglob("*") if p.is_file()}
        recorded = set(self.policy.get("texts", {}))
        if texts != recorded or recorded != self.used_texts:
            raise AcknowledgementError(f"{TEXTS} and its source records disagree: "
                                       f"unrecorded {sorted(texts - recorded)}, missing {sorted(recorded - texts)}, "
                                       f"unused {sorted(recorded - self.used_texts)}")
        return self.render(brands)

    def render(self, brands):
        out = ["Airdraft Acknowledgements", "=========================", "",
               "Airdraft is free software licensed under the GNU General Public License,",
               f"version 3 only (GPL-3.0-only). Source code: {SOURCE_URL}", "",
               "Airdraft includes the third-party software listed below. Each component is",
               "used under the license reproduced here. Speech and language models that you",
               "download in Airdraft are not part of the app and keep their own licenses.", "",
               "Generated by scripts/acknowledgements.py from Package.resolved, the pinned",
               "native inputs and docs/model-brand-assets.md. Do not edit by hand.",
               FINGERPRINT_LINE + fingerprint(self.root), ""]
        groups = []
        for section in self.sections:
            if section["group"] not in groups:
                groups.append(section["group"])
        out += ["Contents", "--------"]
        for group in groups:
            members = [s for s in self.sections if s["group"] == group]
            out.append(f"{group} ({len(members)})")
            for member in members:
                out.append(f"  {member['name']} {member['version']} ({member['license']})")
                out += [f"    includes {title}" for title in member["includes"]]
        out += [f"Model brand assets ({len(brands)})", ""]
        for section in self.sections:
            out += ["=" * 78, f"{section['name']} {section['version']}",
                    f"License: {section['license']}", f"Source: {section['source']}", ""]
            out += [block.rstrip("\n") + "\n" for block in section["blocks"]]
        out += ["=" * 78, "Model brand assets", "",
                "Model and provider logos are trademarks of their respective owners. Airdraft",
                "shows them only to identify the corresponding models and services; they do not",
                "imply endorsement. Sources:", ""]
        out += [f"  {name}: {source}" for name, source in brands]
        return "\n".join(out).rstrip("\n") + "\n"

    def copies(self):
        result = {}
        for target, record in self.policy.get("copies", {}).items():
            entry = self.policy["swiftpm"][record["package"]]
            pin = next(p for p in load_json(self.root, RESOLVED)["pins"] if p["identity"] == record["package"])
            checkout = self.packages / "checkouts" / checkout_name(pin["location"])
            result[target] = normalize((checkout / record["file"]).read_bytes())
            if record["file"] not in entry["files"]:
                raise AcknowledgementError(f"{target} copies an unreviewed file")
        return result


def outputs(root, source_packages):
    builder = Builder(root, source_packages)
    result = {OUTPUT.as_posix(): builder.build()}
    result.update(builder.copies())
    return result


def check_inputs(root=ROOT):
    path = root / OUTPUT
    if not path.is_file():
        raise AcknowledgementError(f"Missing {OUTPUT}; run scripts/acknowledgements.py generate")
    if recorded_fingerprint(path.read_text()) != fingerprint(root):
        raise AcknowledgementError(f"{OUTPUT} is stale: Package.resolved, native inputs, license policy, "
                                   "texts or brand assets changed. Run scripts/acknowledgements.py generate "
                                   "after resolving packages, then commit the result")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["generate", "check", "check-inputs"])
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--source-packages", type=Path,
                        help="Xcode SourcePackages directory (default: this checkout's DerivedData)")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        if args.command == "check-inputs":
            check_inputs(root)
            print(f"Acknowledgements fingerprint matches its inputs: {OUTPUT}")
            return 0
        packages = args.source_packages or default_source_packages(root)
        generated = outputs(root, packages)
        if args.command == "generate":
            for relative, text in generated.items():
                (root / relative).write_text(text)
                print(f"Wrote {relative} ({len(text.encode())} bytes)")
            return 0
        stale = [r for r, text in generated.items()
                 if not (root / r).is_file() or (root / r).read_text() != text]
        if stale:
            raise AcknowledgementError(f"Stale generated notices: {stale}; run scripts/acknowledgements.py generate")
        print(f"Acknowledgements match the resolved dependencies: {', '.join(generated)}")
        return 0
    except (AcknowledgementError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"Acknowledgements: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
