#!/usr/bin/env python3
"""Regenerate the pinned Hugging Face manifest for Qwen3-ASR and Whisper downloads.

Writes `Packages/AirdraftCore/Sources/AirdraftCore/Resources/local-pinned-models.json`.
Every file gets the byte size and SHA-256 at an immutable revision. LFS files take
their SHA-256 from the Hub's LFS pointer; small Git files are downloaded at that
revision into `--work`, checked against the tree's Git blob ID, then hashed.

Optional `--installed <Models dir>` compares each file that exists there (read
only) with the manifest and reports matches and mismatches; it never writes there.

Moving a revision is deliberate: change it below, rerun, review the diff, then
run the Qwen3/Whisper self-tests named in CLAUDE.md.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import pathlib
import sys
import urllib.parse
import urllib.request

HUB = "https://huggingface.co"
QWEN_FILES = ["config.json", "*.safetensors", "model.safetensors.index.json",
              "vocab.json", "merges.txt", "tokenizer_config.json"]
WHISPER_REPO = "argmaxinc/whisperkit-coreml"
WHISPER_REVISION = "0f63a7800b00dd0226abd051b906c246e1907482"
WHISPER_VARIANTS = {
    "large-v3-v20240930_turbo": "openai_whisper-large-v3-v20240930_turbo",
    "large-v3": "openai_whisper-large-v3",
    "large-v3-v20240930_626MB": "openai_whisper-large-v3-v20240930_626MB",
    "distil-large-v3": "distil-whisper_distil-large-v3",
    "distil-large-v3_594MB": "distil-whisper_distil-large-v3_594MB",
    "distil-large-v3_turbo": "distil-whisper_distil-large-v3_turbo",
    "distil-large-v3_turbo_600MB": "distil-whisper_distil-large-v3_turbo_600MB",
}
TOKENIZER_FILES = ["tokenizer.json", "tokenizer_config.json", "special_tokens_map.json", "vocab.json",
                   "merges.txt", "added_tokens.json", "normalizer.json", "config.json", "generation_config.json"]

ARTIFACTS = [
    {"id": "qwen3:aufklarer/Qwen3-ASR-1.7B-MLX-5bit", "repository": "aufklarer/Qwen3-ASR-1.7B-MLX-5bit",
     "revision": "1645ca9ce8767dac9a4a047e9de835950c42596e", "directory": "", "select": QWEN_FILES,
     "installed": "qwen3-asr/aufklarer/Qwen3-ASR-1.7B-MLX-5bit"},
    {"id": "qwen3:aufklarer/Qwen3-ASR-0.6B-MLX-4bit", "repository": "aufklarer/Qwen3-ASR-0.6B-MLX-4bit",
     "revision": "bc441bd1e4295c1f42d9879f056049a925b6e013", "directory": "", "select": QWEN_FILES,
     "installed": "qwen3-asr/aufklarer/Qwen3-ASR-0.6B-MLX-4bit"},
    *[{"id": f"whisper:{variant}", "repository": WHISPER_REPO, "revision": WHISPER_REVISION,
       "directory": directory, "select": ["*"], "installed": f"whisperkit-coreml/{directory}"}
      for variant, directory in WHISPER_VARIANTS.items()],
    {"id": "whisper-tokenizer", "repository": "openai/whisper-large-v3",
     "revision": "06f233fe06e710322aca913c1bc4249a0d71fce1", "directory": "", "select": TOKENIZER_FILES,
     "installed": "tokenizer/whisper-large-v3"},
]


def fetch_json(url: str):
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def git_blob_id(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def pin(artifact: dict, work: pathlib.Path) -> dict:
    repo, revision, directory = artifact["repository"], artifact["revision"], artifact["directory"]
    url = f"{HUB}/api/models/{repo}/tree/{revision}/{directory}?recursive=true"
    tree = [entry for entry in fetch_json(url) if entry["type"] == "file"]
    prefix = directory + "/" if directory else ""
    files = []
    for entry in sorted(tree, key=lambda e: e["path"]):
        relative = entry["path"][len(prefix):]
        if not any(fnmatch.fnmatchcase(relative, pattern) for pattern in artifact["select"]):
            continue
        lfs = entry.get("lfs")
        if lfs:
            sha256 = lfs["oid"].removeprefix("sha256:")
        else:
            quoted = urllib.parse.quote(entry["path"])
            with urllib.request.urlopen(f"{HUB}/{repo}/resolve/{revision}/{quoted}", timeout=120) as response:
                data = response.read()
            if git_blob_id(data) != entry["oid"] or len(data) != entry["size"]:
                sys.exit(f"{repo}@{revision}/{entry['path']}: content does not match the tree's Git blob")
            target = work / repo / revision / entry["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            sha256 = hashlib.sha256(data).hexdigest()
        files.append({"path": relative, "bytes": entry["size"], "sha256": sha256})
    if not files:
        sys.exit(f"{repo}@{revision}/{directory}: no files selected")
    return {key: artifact[key] for key in ("id", "repository", "revision", "directory")} | {"files": files}


def compare_installed(pinned: dict, root: pathlib.Path, installed: str) -> None:
    folder = root / installed
    if not folder.is_dir():
        print(f"  {pinned['id']}: not installed")
        return
    matched = mismatched = missing = 0
    for file in pinned["files"]:
        path = folder / file["path"]
        if not path.is_file():
            missing += 1
        elif path.stat().st_size == file["bytes"] and file_sha256(path) == file["sha256"]:
            matched += 1
        else:
            mismatched += 1
            print(f"    mismatch: {file['path']}")
    print(f"  {pinned['id']}: {matched} match, {mismatched} differ, {missing} missing")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=pathlib.Path, help="empty scratch directory for small files")
    parser.add_argument("--output", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parent.parent
                        / "Packages/AirdraftCore/Sources/AirdraftCore/Resources/local-pinned-models.json")
    parser.add_argument("--installed", type=pathlib.Path, help="read-only Models folder to compare")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    manifest = []
    for artifact in ARTIFACTS:
        pinned = pin(artifact, args.work)
        print(f"{pinned['id']}: {len(pinned['files'])} files, {sum(f['bytes'] for f in pinned['files'])} bytes")
        if args.installed:
            compare_installed(pinned, args.installed, artifact["installed"])
        manifest.append(pinned)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
