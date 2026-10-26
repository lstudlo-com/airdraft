#!/usr/bin/env python3
"""Export History dictations (and kept WAV recordings) into a private labeling corpus.

    python3 -B eval/speed/export_corpus.py [--data-dir DIR] [--since YYYY-MM-DD]
        [--families code,terminal] [--limit N] [--audio-only] [--out DIR] [--force]

Copies history.sqlite (+ -wal/-shm) to a temp directory, reads only the copy
(mode=ro) and deletes it. Writes <out>/manifest.jsonl and copies WAVs into
<out>/audio/. The default <out> is eval/speed/private/<today>/, which git
ignores; anything else must be given explicitly with --out. An existing
manifest is never overwritten without --force (it may hold labels).
"""
import argparse, datetime, pathlib, shutil, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import speedlib as S  # noqa: E402


def manifest_item(row, audio):
    flags = row["flags"]
    return {
        "id": row["id"],
        "createdAt": S.iso(row["createdAt"]),
        "family": row["family"],
        "appBundleId": row["appBundleId"],
        "mode": row["mode"],
        "rawTranscript": row["rawTranscript"],
        "finalText": row["finalText"],
        "flags": flags,
        "sendRequest": row["sendRequest"],
        "submitted": row["submitted"],
        "deliveryStatus": row["deliveryStatus"],
        "outputDestination": row["outputDestination"],
        "audioSeconds": row["audioSeconds"],
        "audio": audio,
        # Labeling fields (label.py / --import-csv).
        "reference": "",
        "intentCorrect": None,
        "flagJudgments": [None] * len(flags) if flags else [],
        "changesAIAnswer": None,
    }


def resolve_out(out_arg, today=None):
    """Return the output folder; the implicit default must stay inside private/."""
    if out_arg:
        return pathlib.Path(out_arg).expanduser(), True
    folder = S.PRIVATE_DIR / (today or datetime.date.today().isoformat())
    if not S.inside(folder, S.PRIVATE_DIR) or (S.PRIVATE_DIR.exists() and S.PRIVATE_DIR.is_symlink()):
        raise SystemExit(f"export_corpus: refusing to write outside {S.PRIVATE_DIR}")
    return folder, False


def export(data_dir, out, since=None, families=None, limit=None, audio_only=False, force=False):
    out = pathlib.Path(out)
    manifest = out / "manifest.jsonl"
    if manifest.exists() and not force:
        raise SystemExit(f"export_corpus: {manifest} exists (it may hold labels); pass --force to replace it")
    recordings = pathlib.Path(data_dir).expanduser() / "Recordings"
    with S.history_copy(data_dir) as (conn, _temp):
        rows, _columns = S.load_dictations(conn, since=since, include_text=True)
        filenames = S.recording_filenames(conn)
    if families:
        rows = [r for r in rows if r["family"] in families]
    rows.sort(key=lambda r: (r["createdAt"], r["id"]), reverse=True)  # newest first for --limit
    items = []
    audio_dir = out / "audio"
    for row in rows:
        audio = None
        name = filenames.get(row["recordingID"]) if row["recordingID"] else None
        if name and S.is_safe_audio_filename(name):
            source = recordings / name
            if source.is_file() and not source.is_symlink():
                audio_dir.mkdir(parents=True, exist_ok=True)
                target = audio_dir / name
                if not target.exists():
                    shutil.copy2(source, target)
                audio = f"audio/{name}"
        if audio_only and audio is None:
            continue
        items.append(manifest_item(row, audio))
        if limit and len(items) >= limit:
            break
    items.reverse()  # oldest first in the manifest
    out.mkdir(parents=True, exist_ok=True)
    S.write_jsonl(manifest, items)
    return {"manifest": str(manifest), "items": len(items), "audio": sum(1 for i in items if i["audio"])}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("--data-dir", default=str(S.DEFAULT_DATA_DIR), help="Airdraft data directory (default: %(default)s)")
    parser.add_argument("--since", help="only rows from this local date (YYYY-MM-DD)")
    parser.add_argument("--families", help="comma-separated History families, e.g. code,terminal,general")
    parser.add_argument("--limit", type=int, help="keep the newest N rows")
    parser.add_argument("--audio-only", action="store_true", help="skip rows without a kept recording")
    parser.add_argument("--out", help="output folder (default: eval/speed/private/<today>)")
    parser.add_argument("--force", action="store_true", help="replace an existing manifest.jsonl")
    args = parser.parse_args(argv)
    try:
        since = S.parse_since(args.since)
    except ValueError:
        parser.error("--since must be YYYY-MM-DD")
    out, explicit = resolve_out(args.out)
    if explicit and not S.inside(out, S.PRIVATE_DIR):
        print(f"export_corpus: note: {out} is outside eval/speed/private/ and not git-ignored", file=sys.stderr)
    families = {f.strip() for f in args.families.split(",") if f.strip()} if args.families else None
    try:
        result = export(args.data_dir, out, since=since, families=families, limit=args.limit,
                        audio_only=args.audio_only, force=args.force)
    except FileNotFoundError as error:
        print(f"export_corpus: {error}", file=sys.stderr)
        return 1
    print(f"Wrote {result['items']} items ({result['audio']} with audio) to {result['manifest']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
