#!/usr/bin/env python3
"""Label a speed corpus manifest in the terminal (resumable; saves after every item).

    python3 -B eval/speed/label.py eval/speed/private/<date>/manifest.jsonl [--play] [--all]
    python3 -B eval/speed/label.py <manifest> --export-csv <file.csv>
    python3 -B eval/speed/label.py <manifest> --import-csv <file.csv>

For each unlabeled item: shows the final text and its flags, asks for the
reference (what you meant; Enter keeps the final text), whether the final text
matches your intent (y/n), and for each flag whether it was worth a look (y/n).
Answer `s` to skip an item and `q` to stop; progress is kept.
--play plays the item's WAV with /usr/bin/afplay (only with this flag).

CSV columns: id, reference, intentCorrect, flagJudgments, changesAIAnswer.
Booleans accept y/n, yes/no, true/false, 1/0; blank leaves the field unchanged.
flagJudgments is `y;n;...` in flag order (or a JSON list). A blank reference
keeps the stored one.
"""
import argparse, csv, json, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import speedlib as S  # noqa: E402

AFPLAY = "/usr/bin/afplay"
TRUE, FALSE = {"y", "yes", "true", "1", "t"}, {"n", "no", "false", "0", "f"}


class Quit(Exception):
    pass


class Skip(Exception):
    pass


def parse_bool(text):
    value = (text or "").strip().lower()
    if value in TRUE:
        return True
    if value in FALSE:
        return False
    if value == "":
        return None
    raise ValueError(f"not a yes/no value: {text!r}")


def is_labeled(item):
    flags = item.get("flags") or []
    judgments = item.get("flagJudgments") or []
    return item.get("intentCorrect") is not None and all(j is not None for j in judgments[:len(flags)]) \
        and len(judgments) >= len(flags)


def ask_bool(prompt, ask):
    while True:
        answer = ask(prompt).strip().lower()
        if answer == "q":
            raise Quit
        if answer == "s":
            raise Skip
        if answer in TRUE:
            return True
        if answer in FALSE:
            return False
        print("  please answer y or n (s skip, q quit)")


def play(manifest_dir, item, runner=subprocess.run):
    if not item.get("audio"):
        print("  (no audio for this item)")
        return
    path = (manifest_dir / item["audio"]).resolve()
    if not S.inside(path, manifest_dir) or not path.is_file():
        print("  (audio file missing)")
        return
    try:
        runner([AFPLAY, str(path)], check=False, timeout=600)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"  (playback failed: {error})")


def label_item(item, ask, out=print):
    """Ask for one item's labels; returns the updated fields or raises Skip/Quit."""
    flags = item.get("flags") or []
    out("")
    out(f"#{item['id']}  {item.get('createdAt') or ''}  {item.get('family')}  {item.get('appBundleId') or '-'}"
        f"  mode {item.get('mode')}  delivery {item.get('deliveryStatus')}")
    out("Final text:")
    out("  " + (item.get("finalText") or "").replace("\n", "\n  "))
    if flags:
        out("Flags:")
        for index, flag in enumerate(flags, 1):
            hold = "holds send" if S.flag_holds_send(flag) else "info"
            out(f"  {index}. [{flag.get('kind')}] {flag.get('text')}  ({flag.get('snippet')})  {hold}")
    elif item.get("flags") is None:
        out("Flags: not checked (older row)")
    else:
        out("Flags: none")
    answer = ask("Reference (Enter = keep final text, s skip, q quit): ")
    if answer.strip().lower() == "q":
        raise Quit
    if answer.strip().lower() == "s":
        raise Skip
    reference = answer if answer.strip() else (item.get("finalText") or "")
    intent = ask_bool("Final text matches what you meant? [y/n] ", ask)
    judgments = []
    for index, flag in enumerate(flags, 1):
        judgments.append(ask_bool(f"Flag {index} [{flag.get('kind')}] {flag.get('text')} worth a look? [y/n] ", ask))
    return {"reference": reference, "intentCorrect": intent, "flagJudgments": judgments}


def run_interactive(manifest, ask=input, play_audio=False, relabel=False, runner=subprocess.run, out=print):
    manifest = pathlib.Path(manifest)
    items = S.read_jsonl(manifest)
    pending = [i for i, item in enumerate(items) if relabel or not is_labeled(item)]
    out(f"{len(items)} items, {len(pending)} to label")
    done = 0
    for position, index in enumerate(pending, 1):
        item = items[index]
        out(f"\n[{position}/{len(pending)}]")
        if play_audio:
            play(manifest.parent, item, runner)
        try:
            item.update(label_item(item, ask, out))
        except Skip:
            continue
        except (Quit, EOFError, KeyboardInterrupt):
            out("\nStopped; progress saved.")
            break
        S.write_jsonl(manifest, items)
        done += 1
    return done


def parse_judgments(text, count):
    text = (text or "").strip()
    if text == "":
        return None
    if text.startswith("["):
        values = json.loads(text)
        values = [v if v is None or isinstance(v, bool) else parse_bool(str(v)) for v in values]
    else:
        values = [parse_bool(v) for v in text.replace(",", ";").split(";")]
    if len(values) != count:
        raise ValueError(f"expected {count} flag judgment(s), got {len(values)}")
    return values


def import_csv(manifest, csv_path):
    manifest = pathlib.Path(manifest)
    items = S.read_jsonl(manifest)
    by_id = {str(item["id"]): item for item in items}
    errors, updated = [], 0
    with open(csv_path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if "id" not in (reader.fieldnames or []):
            raise SystemExit("label: CSV needs an `id` column")
        changes = []
        for line, row in enumerate(reader, 2):
            item = by_id.get(str(row.get("id", "")).strip())
            if item is None:
                errors.append(f"line {line}: unknown id {row.get('id')!r}")
                continue
            try:
                change = {}
                if (row.get("reference") or "").strip():
                    change["reference"] = row["reference"]
                for field in ("intentCorrect", "changesAIAnswer"):
                    value = parse_bool(row.get(field))
                    if value is not None:
                        change[field] = value
                judgments = parse_judgments(row.get("flagJudgments"), len(item.get("flags") or []))
                if judgments is not None:
                    change["flagJudgments"] = judgments
            except ValueError as error:
                errors.append(f"line {line}: {error}")
                continue
            changes.append((item, change))
    if errors:
        raise SystemExit("label: CSV not imported:\n  " + "\n  ".join(errors))
    for item, change in changes:
        if change:
            item.update(change)
            updated += 1
    S.write_jsonl(manifest, items)
    return updated


def export_csv(manifest, csv_path):
    items = S.read_jsonl(manifest)
    with open(csv_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["id", "finalText", "flags", "reference", "intentCorrect", "flagJudgments", "changesAIAnswer"])
        for item in items:
            flags = item.get("flags") or []
            def b(v):
                return "" if v is None else ("y" if v else "n")
            writer.writerow([
                item["id"], item.get("finalText") or "",
                "; ".join(f"{f.get('kind')}:{f.get('text')}" for f in flags),
                item.get("reference") or "", b(item.get("intentCorrect")),
                ";".join(b(j) for j in (item.get("flagJudgments") or [])) if flags else "",
                b(item.get("changesAIAnswer")),
            ])
    return len(items)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("manifest", help="manifest.jsonl from export_corpus.py")
    parser.add_argument("--play", action="store_true", help="play each item's WAV with /usr/bin/afplay first")
    parser.add_argument("--all", action="store_true", help="revisit labeled items too")
    parser.add_argument("--import-csv", metavar="CSV", help="merge labels from a CSV instead of asking")
    parser.add_argument("--export-csv", metavar="CSV", help="write a CSV of items and current labels")
    args = parser.parse_args(argv)
    if args.export_csv:
        if not S.inside(args.export_csv, S.PRIVATE_DIR):
            print("label: note: the CSV holds transcripts and is outside eval/speed/private/", file=sys.stderr)
        print(f"Wrote {export_csv(args.manifest, args.export_csv)} rows to {args.export_csv}")
        return 0
    if args.import_csv:
        print(f"Updated {import_csv(args.manifest, args.import_csv)} items in {args.manifest}")
        return 0
    done = run_interactive(args.manifest, play_audio=args.play, relabel=args.all)
    print(f"Labeled {done} item(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
