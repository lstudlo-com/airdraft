#!/usr/bin/env python3
"""Attach the app's `asr-guard` log lines (no transcript text) to run_guards.py results.

  python3 -I eval/mixed-asr/guard_log.py --work <dir> --tag after

Each run JSON gains `guard_log`: the asr-guard messages logged between its
`started` and `ended` wall-clock bounds (runs are sequential).
"""
import argparse, datetime, json, pathlib, subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    paths = sorted((args.work / f"runs-{args.tag}").glob("*/*.json"))
    runs = [(p, json.loads(p.read_text())) for p in paths]
    runs = [(p, r) for p, r in runs if "started" in r]
    if not runs:
        return
    fmt = lambda t: datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")
    start = min(r["started"] for _, r in runs) - 1
    end = max(r["ended"] for _, r in runs) + 1
    out = subprocess.run(["/usr/bin/log", "show", "--style", "ndjson", "--start", fmt(start), "--end", fmt(end),
                          "--predicate", 'subsystem BEGINSWITH "com.lightiichen.airdraft" AND category == "asr-guard"'],
                         capture_output=True, text=True, check=True).stdout
    entries = []
    for line in out.splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "eventMessage" not in entry:
            continue
        stamp = datetime.datetime.strptime(entry["timestamp"][:26], "%Y-%m-%d %H:%M:%S.%f").timestamp()
        entries.append((stamp, entry["eventMessage"]))
    for path, run in runs:
        run["guard_log"] = [message for stamp, message in entries if run["started"] <= stamp <= run["ended"]]
        path.write_text(json.dumps(run, ensure_ascii=False, indent=1))
    print(f"{len(entries)} guard log lines over {len(runs)} runs")


if __name__ == "__main__":
    main()
