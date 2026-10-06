#!/usr/bin/env python3
"""Prepare and verify the native library inputs used by the Mac app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
import uuid

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / "Packages/SherpaOnnxKit/native-inputs.json"
VENDOR = ROOT / "Packages/SherpaOnnxKit/Vendor"
MANIFEST = "airdraft-native-inputs.json"


def digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def load_inputs(path=INPUTS):
    inputs = json.loads(Path(path).read_text())
    if inputs.get("schema") != 1 or not isinstance(inputs.get("libraries"), list):
        raise ValueError("Unsupported native input metadata")
    libraries = inputs["libraries"]
    if [item.get("id") for item in libraries] != ["SherpaOnnxC", "onnxruntime"]:
        raise ValueError("Native library identities do not match the Mac package")
    for item in libraries:
        url = urlsplit(item.get("url", ""))
        if (url.scheme != "https" or not url.hostname or url.username or url.password
                or not re.fullmatch(r"[0-9a-f]{64}", item.get("sha256", ""))
                or not item.get("version") or not url.path.endswith(".zip")):
            raise ValueError(f"Invalid pinned native input: {item['id']}")
    return inputs


def verify_archive(path, library):
    path = Path(path)
    if not path.is_file() or path.is_symlink() or digest(path) != library["sha256"]:
        raise ValueError(f"Native archive integrity check failed: {library['id']}")


def file_digests(vendor):
    result = {}
    for path in sorted(Path(vendor).rglob("*")):
        relative = path.relative_to(vendor).as_posix()
        if path.is_symlink():
            raise ValueError(f"Unexpected symlink in native output: {relative}")
        if path.is_file() and relative != MANIFEST:
            result[relative] = digest(path)
        elif not path.is_file() and not path.is_dir():
            raise ValueError(f"Unexpected file type in native output: {relative}")
    return result


def write_manifest(vendor, inputs):
    manifest = {"schema": 1, "inputs": inputs, "recipe_sha256": digest(__file__),
                "files": file_digests(vendor)}
    (Path(vendor) / MANIFEST).write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")


def verify_vendor(vendor=VENDOR, inputs_path=INPUTS):
    vendor = Path(vendor)
    manifest_path = vendor / MANIFEST
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise ValueError("Native input manifest is missing; run scripts/make-sherpa-xcframeworks.sh")
    manifest = json.loads(manifest_path.read_text())
    inputs = load_inputs(inputs_path)
    if manifest.get("schema") != 1 or manifest.get("inputs") != inputs:
        raise ValueError("Native input manifest does not match committed library identities")
    if manifest.get("recipe_sha256") != digest(__file__):
        raise ValueError("Native preparation recipe changed; prepare the libraries again")
    actual = file_digests(vendor)
    # Xcode derives the architecture directory from the input archives. Validate
    # each expected library independently of that generated directory name.
    for item in inputs["libraries"]:
        prefix = f"{item['id']}.xcframework/"
        if (prefix + "Info.plist" not in actual
                or not any(name.startswith(prefix) and name.endswith(f"/lib{item['id']}.a") for name in actual)):
            raise ValueError(f"Native framework is incomplete: {item['id']}")
    if not actual or actual != manifest.get("files"):
        raise ValueError("Native derived files changed or are missing; prepare the libraries again")
    return manifest


def publish_vendor(prepared, vendor):
    """Replace only this directory entry, never an existing symlink's target."""
    prepared, vendor = Path(prepared), Path(vendor)
    previous = vendor.with_name(f".{vendor.name}.previous-{uuid.uuid4().hex}")
    had_previous = os.path.lexists(vendor)
    if had_previous:
        os.replace(vendor, previous)
    try:
        os.replace(prepared, vendor)
    except BaseException:
        if had_previous:
            os.replace(previous, vendor)
        raise
    if had_previous:
        if previous.is_symlink() or previous.is_file():
            previous.unlink()
        else:
            shutil.rmtree(previous)


def prepare_vendor(vendor=VENDOR, archives=None, inputs_path=INPUTS):
    vendor = Path(vendor).absolute()  # Do not resolve an existing Vendor symlink.
    vendor.parent.mkdir(parents=True, exist_ok=True)
    inputs = load_inputs(inputs_path)
    with tempfile.TemporaryDirectory(prefix=".native-prepare-", dir=vendor.parent) as scratch:
        scratch = Path(scratch)
        verified = []
        for item in inputs["libraries"]:
            name = Path(urlsplit(item["url"]).path).name
            archive = Path(archives) / name if archives else scratch / name
            if not archives:
                subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                                "--proto", "=https", "--proto-redir", "=https", "--retry", "2",
                                item["url"], "--output", str(archive)], check=True)
            verify_archive(archive, item)
            verified.append((item, archive))

        prepared = scratch / "Vendor"
        prepared.mkdir()
        for item, archive in verified:
            unpacked = scratch / item["id"]
            unpacked.mkdir()
            subprocess.run(["/usr/bin/unzip", "-q", str(archive), "-d", str(unpacked)], check=True)
            frameworks = [path for path in unpacked.rglob(item["id"] + ".framework")
                          if any("macos" in part for part in path.relative_to(unpacked).parts)]
            if len(frameworks) != 1:
                raise ValueError(f"Expected one macOS framework for {item['id']}")
            framework = frameworks[0] / "Versions/A"
            library = scratch / f"lib{item['id']}.a"
            shutil.copyfile(framework / item["id"], library)
            command = ["xcodebuild", "-create-xcframework", "-library", str(library)]
            if item["id"] == "SherpaOnnxC":
                headers = scratch / "headers"
                shutil.copytree(framework / "Headers", headers)
                (headers / "module.modulemap").write_text(
                    'module SherpaOnnxC {\n  header "sherpa-onnx/c-api/c-api.h"\n  export *\n}\n')
                command += ["-headers", str(headers)]
            subprocess.run(command + ["-output", str(prepared / f"{item['id']}.xcframework")], check=True)
        write_manifest(prepared, inputs)
        verify_vendor(prepared, inputs_path)
        publish_vendor(prepared, vendor)
    return verify_vendor(vendor, inputs_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "verify"])
    parser.add_argument("--vendor", type=Path, default=VENDOR)
    parser.add_argument("--archives", type=Path, help="Use already downloaded, pinned archives during preparation")
    args = parser.parse_args()
    if args.command == "verify" and args.archives:
        parser.error("--archives is only used with prepare")
    try:
        manifest = prepare_vendor(args.vendor, args.archives) if args.command == "prepare" else verify_vendor(args.vendor)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Native inputs: {error}", file=sys.stderr)
        return 1
    print(f"Verified {len(manifest['inputs']['libraries'])} native inputs and {len(manifest['files'])} derived files: {args.vendor}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
