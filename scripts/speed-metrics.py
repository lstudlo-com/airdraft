#!/usr/bin/env python3
"""Read-only AD-104 speed report from local History and counters.

    python3 -B scripts/speed-metrics.py [--data-dir DIR] [--since YYYY-MM-DD] [--json]
                                        [--corpus eval/speed/private/<date>]

Copies history.sqlite (and -wal/-shm) into a fresh temporary directory, opens
only the copy with mode=ro, and deletes it afterwards. Reads
<data dir>/speed-metrics.json for press and capture-latency counters.

Prints only counts, rates, durations, bundle-ID prefixes and app families:
never transcript text, window titles, URLs or flag text.

Definitions
- Refinement change rate: refinedText differs from rawTranscript after trimming.
- Flag rate: rows with at least one flag among rows whose `flags` is not NULL.
  Family split uses History's family column (code+terminal vs other).
- Gate 5 comes from the `deliveries` counters in speed-metrics.json (cursor
  outcomes per destination bundle ID), not History: History stores bundle IDs
  only when Read app context is on. AI destinations: bundle ID starts with
  com.openai.chat, com.anthropic.claudefordesktop or a code/terminal prefix
  from AppFamily.swift; browsers never count. Rate = delivered / (delivered +
  sentUnverified + notDelivered); the one-sided 95% Clopper-Pearson lower bound
  must reach 95% (n >= 59 with all confirmed). Self-drawing editors (Warp, Zed,
  Ghostty, kitty, Alacritty, WezTerm) can only be sentUnverified; a second line
  excludes them for reference.
- Web apps: deliveries keys starting com.apple.Safari.WebApp. or
  com.google.Chrome.app. (prefix, destination count and deliveries only).
- Capture latency: median and p90 (nearest rank) of speed-metrics.json samples.
- --since filters from local midnight of that date.
"""
import argparse, json, math, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "eval" / "speed"))
import speedlib as S  # noqa: E402


def percentile(values, q):
    """Nearest-rank percentile."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, math.ceil(q * len(ordered)))
    return ordered[rank - 1]


def median(values):
    if not values:
        return None
    ordered = sorted(values)
    mid = len(ordered) // 2
    return ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2


def changed(row):
    return (row["rawTranscript"] or "").strip() != (row["refinedText"] or "").strip()


def refinement_section(rows):
    clean = [r for r in rows if r["mode"] == "Clean"]
    refined = [r for r in rows if r["llmEngine"]]
    def block(subset):
        k = sum(1 for r in subset if changed(r))
        return {"n": len(subset), "changed": k, "rate": S.rate(k, len(subset))}
    return {"all": block(rows), "clean": block(clean), "withRefiner": block(refined)}


def flag_section(rows, has_column):
    checked = [r for r in rows if r["flags"] is not None]
    unreadable = sum(1 for r in rows if not r["flagsReadable"])

    def block(subset):
        flagged = [r for r in subset if r["flags"]]
        holding = [r for r in subset if any(S.flag_holds_send(f) for f in r["flags"])]
        kinds = {}
        for kind in S.FLAG_KINDS + ("other",):
            with_kind = [r for r in subset if any(_kind(f) == kind for f in r["flags"])]
            total = sum(1 for r in subset for f in r["flags"] if _kind(f) == kind)
            if kind == "other" and not total:
                continue
            kinds[kind] = {"rows": len(with_kind), "rowRate": S.rate(len(with_kind), len(subset)), "flags": total}
        flags = [f for r in subset for f in r["flags"]]
        return {
            "checked": len(subset), "flagged": len(flagged), "rate": S.rate(len(flagged), len(subset)),
            "flags": len(flags),
            "holdsSend": {"rows": len(holding), "rowRate": S.rate(len(holding), len(subset)),
                          "flags": sum(1 for f in flags if S.flag_holds_send(f)),
                          "nonHoldingFlags": sum(1 for f in flags if not S.flag_holds_send(f))},
            "byKind": kinds,
        }

    return {
        "columnPresent": has_column,
        "unchecked": len(rows) - len(checked) - unreadable,
        "unreadable": unreadable,
        "overall": block(checked),
        "codeTerminal": block([r for r in checked if r["family"] in S.CODE_FAMILIES]),
        "other": block([r for r in checked if r["family"] not in S.CODE_FAMILIES]),
    }


def _kind(flag):
    kind = flag.get("kind")
    return kind if kind in S.FLAG_KINDS else "other"


def readback_block(delivered, unverified, failed):
    n = delivered + unverified + failed
    lower = S.cp_lower(delivered, n)
    needed = S.n_needed_for_lower(n - delivered)
    if n == 0:
        status = "no data"
    elif lower >= 0.95:
        status = "pass"
    elif S.cp_upper(delivered, n) < 0.95:
        status = "fail"
    else:
        status = f"not yet: needs n >= {needed} at {n - delivered} failure(s)" if needed else "not yet"
    return {"n": n, "delivered": delivered, "sentUnverified": unverified, "notDelivered": failed,
            "rate": S.rate(delivered, n), "lower95": lower, "nNeeded": needed, "status": status}


def readback_section(counters):
    """Gate 5 from speed-metrics.json `deliveries` (cursor outcomes per destination)."""
    deliveries = counters.get("deliveries")
    if deliveries is None:
        return {"present": False, "since": counters.get("since"), "overall": readback_block(0, 0, 0),
                "excludingSelfDrawing": readback_block(0, 0, 0), "byDestination": {}}
    rows = {bundle: c for bundle, c in deliveries.items() if S.is_ai_destination_bundle(bundle)}
    def total(subset):
        return readback_block(sum(c["delivered"] for c in subset), sum(c["sentUnverified"] for c in subset),
                              sum(c["notDelivered"] for c in subset))
    return {
        "present": True, "since": counters.get("since"),
        "overall": total(rows.values()),
        "excludingSelfDrawing": total([c for b, c in rows.items() if not S.is_self_drawing(b)]),
        "byDestination": {b: dict(c, label=S.ai_app_label(b) or S.code_terminal_family(b),
                                  selfDrawing=S.is_self_drawing(b)) for b, c in sorted(rows.items())},
    }


def send_section(rows, has_column):
    table = {}
    for r in rows:
        request = r["sendRequest"] or "none"
        submitted = {True: "submitted", False: "held", None: "null"}[r["submitted"]]
        table.setdefault(request, {}).setdefault(submitted, 0)
        table[request][submitted] += 1
    return {"columnPresent": has_column, "table": table}


def web_app_section(counters):
    """Web apps from `deliveries` keys: prefix, destination count and deliveries only."""
    deliveries = counters.get("deliveries")
    result = {}
    for prefix in S.WEB_APP_PREFIXES:
        hits = [c for b, c in (deliveries or {}).items() if b.startswith(prefix)]
        result[prefix] = {"destinations": len(hits),
                          "deliveries": sum(c["delivered"] + c["sentUnverified"] + c["notDelivered"] for c in hits)}
    return {"present": deliveries is not None, "byPrefix": result}


def counters_section(data_dir, since):
    path = pathlib.Path(data_dir).expanduser() / "speed-metrics.json"
    if not path.is_file():
        return {"present": False}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"present": True, "readable": False}
    ignored, accepted = int(data.get("ignoredPresses", 0) or 0), int(data.get("acceptedPresses", 0) or 0)
    samples = []
    for sample in data.get("captureSamples", []) or []:
        if not isinstance(sample, dict) or not isinstance(sample.get("ms"), (int, float)):
            continue
        at = S.parse_time(sample.get("at"))
        if since and (at is None or at < since):
            continue
        transport = sample.get("transport") if sample.get("transport") in S.CAPTURE_TRANSPORTS else "unknown"
        samples.append((transport, float(sample["ms"])))

    deliveries = None
    if isinstance(data.get("deliveries"), dict):
        deliveries = {}
        for bundle, counts in data["deliveries"].items():
            if not isinstance(bundle, str) or not isinstance(counts, dict):
                continue
            deliveries[bundle] = {k: max(0, int(counts.get(k, 0) or 0))
                                  for k in ("delivered", "sentUnverified", "notDelivered")}

    def stats(values):
        return {"n": len(values), "medianMs": median(values), "p90Ms": percentile(values, 0.9)}

    by_transport = {}
    for transport, ms in samples:
        by_transport.setdefault(transport, []).append(ms)
    return {
        "present": True, "readable": True, "version": data.get("version"), "since": data.get("since"),
        "ignoredPresses": ignored, "acceptedPresses": accepted,
        "ignoredPer100Accepted": (100.0 * ignored / accepted) if accepted else None,
        "deliveries": deliveries,
        "capture": {"overall": stats([ms for _, ms in samples]),
                    "byTransport": {t: stats(v) for t, v in sorted(by_transport.items())}},
    }


def corpus_section(folder):
    if not folder:
        return None
    folder = pathlib.Path(folder)
    out = {}
    for name in ("score.json", "compare-summary.json"):
        path = folder / name
        if path.is_file():
            try:
                out[name] = json.loads(path.read_text(encoding="utf-8"))
            except ValueError:
                out[name] = None
    return out


def gates(report):
    rb = report["readback"]["overall"]
    corpus = report.get("corpus") or {}
    compare = corpus.get("compare-summary.json") or {}
    score = corpus.get("score.json") or {}
    g2 = compare.get("gate2", {}).get("status") if compare else None
    g3 = score.get("gate3", {}).get("status") if score else None
    return [
        {"gate": 1, "rule": "A/B median time per AI prompt down >= 20%", "status": "needs user test"},
        {"gate": 2, "rule": "errors that change the AI answer <= 25%",
         "status": g2 or "needs recorded corpus (eval/speed/compare_answers.py)"},
        {"gate": 3, "rule": "flag precision >= 30%",
         "status": g3 or "needs recorded corpus (eval/speed/score.py)"},
        {"gate": 4, "rule": "long-prompt review baseline median >= 5 s", "status": "needs user test"},
        {"gate": 5, "rule": "AI-destination read-back confirmation >= 95% (n >= 59 if no failures)",
         "status": rb["status"]},
    ]


def build_report(data_dir, since=None, corpus=None):
    with S.history_copy(data_dir) as (conn, _temp):
        rows, columns = S.load_dictations(conn, since=since, include_text=True)
    report = {
        "window": {"since": S.iso(since), "dictations": len(rows),
                   "first": S.iso(rows[0]["createdAt"]) if rows else None,
                   "last": S.iso(rows[-1]["createdAt"]) if rows else None},
        "refinement": refinement_section(rows),
        "flags": flag_section(rows, "flags" in columns),
        "send": send_section(rows, "sendRequest" in columns),
    }
    counters = counters_section(data_dir, since)
    report["readback"] = readback_section(counters)
    report["webApps"] = web_app_section(counters)
    counters.pop("deliveries", None)  # reported through readback and webApps
    report["counters"] = counters
    # Drop text references as soon as the aggregates exist.
    for r in rows:
        r.pop("rawTranscript", None); r.pop("refinedText", None); r.pop("finalText", None); r.pop("flags", None)
    if corpus:
        report["corpus"] = corpus_section(corpus)
    report["gates"] = gates(report)
    return report


def fmt_ms(value):
    return "n/a" if value is None else f"{value:.0f} ms"


def render_text(report):
    out = []
    w = report["window"]
    out.append(f"Airdraft speed metrics (AD-104)  since {w['since'] or 'all history'}")
    out.append(f"Dictations: {w['dictations']}  ({w['first'] or '-'} .. {w['last'] or '-'})")
    out.append("")
    ref = report["refinement"]
    out.append("Refinement change rate (refined != raw after trimming)")
    for key, label in (("all", "all rows"), ("withRefiner", "with a refiner"), ("clean", "mode Clean")):
        b = ref[key]
        out.append(f"  {label:<16} {b['changed']}/{b['n']}  {S.pct(b['rate'])}")
    out.append("")
    fl = report["flags"]
    out.append("Flags (rows with >= 1 flag among checked rows)")
    if not fl["columnPresent"]:
        out.append("  flags column missing: History is older than migration v9-speed")
    out.append(f"  unchecked rows (flags NULL): {fl['unchecked']}   unreadable: {fl['unreadable']}")
    for key, label in (("overall", "overall"), ("codeTerminal", "code+terminal"), ("other", "other")):
        b = fl[key]
        out.append(f"  {label:<14} {b['flagged']}/{b['checked']}  {S.pct(b['rate'])}   "
                   f"holds send: {b['holdsSend']['rows']} rows {S.pct(b['holdsSend']['rowRate'])}")
        for kind, kb in b["byKind"].items():
            out.append(f"      {kind:<12} rows {kb['rows']:>4}  {S.pct(kb['rowRate']):>6}   flags {kb['flags']}")
    out.append("")
    rb = report["readback"]
    out.append(f"AI-destination read-back confirmation (speed-metrics.json deliveries, since {rb['since'] or '-'})")
    if not rb["present"]:
        out.append("  no deliveries counters yet (app older than AD-104 or nothing delivered)")
    for key, label in (("overall", "all AI"), ("excludingSelfDrawing", "w/o self-drawing")):
        o = rb[key]
        out.append(f"  {label:<17} {o['delivered']}/{o['n']}  {S.pct(o['rate'])}  lower95 {S.pct(o['lower95'], 2)}  "
                   f"unverified {o['sentUnverified']}  failed {o['notDelivered']}  -> {o['status']}")
    for bundle, c in rb["byDestination"].items():
        mark = "  self-drawing: only sentUnverified possible" if c["selfDrawing"] else ""
        out.append(f"    {bundle:<34} delivered {c['delivered']}  unverified {c['sentUnverified']}  "
                   f"failed {c['notDelivered']}{mark}")
    out.append("")
    sd = report["send"]
    out.append("Send requests (sendRequest x submitted)")
    if not sd["columnPresent"]:
        out.append("  sendRequest column missing: History is older than migration v9-speed")
    for request, cells in sorted(sd["table"].items()):
        out.append(f"  {request:<6} " + "  ".join(f"{k} {v}" for k, v in sorted(cells.items())))
    out.append("")
    c = report["counters"]
    out.append("Presses and capture latency (speed-metrics.json)")
    if not c.get("present"):
        out.append("  speed-metrics.json not found")
    elif not c.get("readable"):
        out.append("  speed-metrics.json unreadable")
    else:
        per100 = c["ignoredPer100Accepted"]
        out.append(f"  since {c['since']}: ignored {c['ignoredPresses']}, accepted {c['acceptedPresses']}, "
                   f"ignored per 100 accepted {'n/a' if per100 is None else f'{per100:.1f}'}")
        cap = c["capture"]
        out.append(f"  capture overall  n {cap['overall']['n']}  median {fmt_ms(cap['overall']['medianMs'])}  "
                   f"p90 {fmt_ms(cap['overall']['p90Ms'])}")
        for t, b in cap["byTransport"].items():
            out.append(f"    {t:<11} n {b['n']:>3}  median {fmt_ms(b['medianMs'])}  p90 {fmt_ms(b['p90Ms'])}")
    out.append("")
    out.append("Web-app destinations from deliveries (prefix, destinations, deliveries)")
    for prefix, b in report["webApps"]["byPrefix"].items():
        out.append(f"  {prefix:<26} {b['destinations']}  {b['deliveries']}")
    out.append("")
    out.append("Gates")
    for g in report["gates"]:
        out.append(f"  {g['gate']}  {g['rule']:<70} {g['status']}")
    return "\n".join(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("--data-dir", default=str(S.DEFAULT_DATA_DIR),
                        help="Airdraft data directory (default: %(default)s)")
    parser.add_argument("--since", help="only rows from this local date (YYYY-MM-DD)")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--corpus", help="eval/speed/private/<date> folder with score.json / compare-summary.json")
    args = parser.parse_args(argv)
    try:
        since = S.parse_since(args.since)
    except ValueError:
        parser.error("--since must be YYYY-MM-DD")
    try:
        report = build_report(args.data_dir, since=since, corpus=args.corpus)
    except FileNotFoundError as error:
        print(f"speed-metrics: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, ensure_ascii=False) if args.json else render_text(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
