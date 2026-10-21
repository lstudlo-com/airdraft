#!/usr/bin/env python3
"""Score AD-074 runs.  python3 -I eval/mixed-asr/score.py --work /tmp/airdraft-groupA/asr-eval

Normalization (applied identically to reference and the app's final text):
 1. ICU Hans-Hant (the transform ChineseScriptConverter uses), via to_traditional.swift.
 2. NFKC, lowercase; apostrophes dropped (what's -> whats).
 3. Every character that is not a Han character, Latin letter or digit becomes a space.
 4. Tokens: each Han character; each run of [a-z0-9]. Runs of single-letter Latin
    tokens are joined (p r -> pr), so spelled acronyms compare with written ones.
 5. Fillers removed: 呃 嗯 欸 誒 唔 / uh um uhm hmm mm erm.
Numbers are not converted between digits and Chinese numerals.

MER = edit distance over the combined token sequence / reference tokens.
CER = edit distance over Han tokens only; WER = over Latin tokens only.
Retention = reference Latin tokens found in the hypothesis (multiset), / reference
Latin tokens. Case-exact retention (tw-tts only) compares original-case words.
"""
import argparse, collections, csv, json, pathlib, random, re, statistics, subprocess, tempfile, unicodedata

HERE = pathlib.Path(__file__).resolve().parent
HAN = r"㐀-䶿一-鿿豈-﫿"
FILLERS = set("呃嗯欸誒唔") | {"uh", "um", "uhm", "hmm", "mm", "erm"}


def to_traditional(strings):
    binary = pathlib.Path(tempfile.gettempdir()) / "airdraft-ad074-to-traditional"
    if not binary.exists():
        subprocess.run(["xcrun", "swiftc", "-O", str(HERE / "to_traditional.swift"), "-o", str(binary)], check=True)
    out = subprocess.run([str(binary)], input=json.dumps(strings).encode(), capture_output=True, check=True)
    return json.loads(out.stdout)


def merge_letters(raw):
    """Join runs of single-letter Latin tokens: ['p','r','merge'] -> ['pr','merge']."""
    out, run = [], []
    for token in raw + [None]:
        if token is not None and re.fullmatch(r"[A-Za-z]", token):
            run.append(token)
            continue
        if run:
            out.append("".join(run))
            run = []
        if token is not None:
            out.append(token)
    return out


def tokenize(text, keep_case=False):
    text = unicodedata.normalize("NFKC", text).replace("'", "").replace("’", "")
    if not keep_case:
        text = text.lower()
    text = re.sub(rf"[^{HAN}A-Za-z0-9]+", " ", text)
    raw = re.findall(rf"[{HAN}]|[A-Za-z]+|[0-9]+", text)
    return [t for t in merge_letters(raw) if t.lower() not in FILLERS]


def is_han(token):
    return re.fullmatch(rf"[{HAN}]", token) is not None


def is_latin(token):
    return re.fullmatch(r"[A-Za-z]+", token) is not None


def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x != y)))
        previous = current
    return previous[-1]


def retained(ref, hyp):
    counts = collections.Counter(hyp)
    hit = 0
    for token in ref:
        if counts[token] > 0:
            counts[token] -= 1
            hit += 1
    return hit


def percentile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def bootstrap(rows, key_err, key_ref, seed=74, n=2000):
    rng = random.Random(seed)
    stats = []
    for _ in range(n):
        sample = [rows[rng.randrange(len(rows))] for _ in rows]
        ref = sum(r[key_ref] for r in sample)
        stats.append(sum(r[key_err] for r in sample) / ref if ref else 0)
    return round(percentile(stats, 0.025), 4), round(percentile(stats, 0.975), 4)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True, type=pathlib.Path)
    args = parser.parse_args()
    manifest = json.loads((HERE / "manifest.json").read_text())
    items = {i["id"]: i for i in manifest["items"]}
    runs = [json.loads(p.read_text()) for p in sorted((args.work / "runs").glob("*/*.json")) if p.parent.name != "load"]
    loads = [json.loads(p.read_text()) for p in sorted((args.work / "runs/load").glob("*.json"))]

    texts = [items[r["id"]]["reference"] for r in runs] + [r.get("final") or "" for r in runs] + [r.get("raw") or "" for r in runs]
    converted = to_traditional(texts)
    n = len(runs)
    rows = []
    for index, run in enumerate(runs):
        item = items[run["id"]]
        ref_text, hyp_text, raw_text = converted[index], converted[n + index], converted[2 * n + index]
        ref, hyp = tokenize(ref_text), tokenize(hyp_text)
        ref_han, hyp_han = [t for t in ref if is_han(t)], [t for t in hyp if is_han(t)]
        ref_lat, hyp_lat = [t for t in ref if is_latin(t)], [t for t in hyp if is_latin(t)]
        row = {
            "id": run["id"], "corpus": item["corpus"], "model": run["model"], "language": run["language"],
            "status": run["status"], "duration": item["duration"], "asrMs": run.get("asrMs"),
            "peak_footprint": run.get("peak_footprint"), "max_rss": run.get("max_rss"),
            "reference": item["reference"], "final": run.get("final") or "",
            "ref_tokens": len(ref), "err": distance(ref, hyp),
            "ref_han": len(ref_han), "err_han": distance(ref_han, hyp_han),
            "ref_lat": len(ref_lat), "err_lat": distance(ref_lat, hyp_lat),
            "kept_lat": retained(ref_lat, hyp_lat),
            # Raw ASR output already Traditional before the app's converter?
            "raw_simplified": (run.get("raw") or "") != raw_text,
            # Code-switch collapse: English dropped, or Chinese translated away.
            "english_dropped": bool(ref_lat) and not hyp_lat,
            "chinese_lost": len(ref_han) >= 4 and len(hyp_han) < 0.3 * len(ref_han),
            "punctuated": re.search(r"[，。？！、,.?!]", run.get("final") or "") is not None,
            "uppercase_latin": any(w.isupper() and len(w) > 1 for w in re.findall(r"[A-Za-z]+", run.get("final") or "")),
        }
        if item["corpus"].startswith("tw-tts"):
            ref_case = [t for t in tokenize(item["reference"], keep_case=True) if is_latin(t)]
            hyp_case = [t for t in tokenize(hyp_text, keep_case=True) if is_latin(t)]
            row["kept_lat_case"] = retained(ref_case, hyp_case)
        rows.append(row)

    groups = collections.defaultdict(list)
    for row in rows:
        groups[(row["model"], row["language"], row["corpus"])].append(row)
    summary = []
    for (model, language, corpus), group in sorted(groups.items()):
        ok = [r for r in group if r["status"] == "passed"]
        # Failed runs count as full deletions so a crash cannot improve a score.
        scored = [r if r["status"] == "passed" else {**r, "err": r["ref_tokens"], "err_han": r["ref_han"],
                  "err_lat": r["ref_lat"], "kept_lat": 0, "kept_lat_case": 0} for r in group]
        latencies = [r["asrMs"] for r in ok if r["asrMs"] is not None]
        rtf = [r["asrMs"] / 1000 / r["duration"] for r in ok if r["asrMs"] is not None]
        xs, ys = [r["duration"] for r in ok], [r["asrMs"] for r in ok]
        slope = statistics.linear_regression(xs, ys) if len(ok) > 2 else None
        ref_lat = sum(r["ref_lat"] for r in scored)
        entry = {
            "model": model, "language": language, "corpus": corpus, "utterances": len(group), "failures": len(group) - len(ok),
            "mer": round(sum(r["err"] for r in scored) / sum(r["ref_tokens"] for r in scored), 4),
            "mer_ci95": bootstrap(scored, "err", "ref_tokens"),
            "cer_han": round(sum(r["err_han"] for r in scored) / sum(r["ref_han"] for r in scored), 4),
            "wer_latin": round(sum(r["err_lat"] for r in scored) / ref_lat, 4),
            "english_retention": round(sum(r["kept_lat"] for r in scored) / ref_lat, 4),
            "english_dropped_utts": sum(r["english_dropped"] for r in scored),
            "chinese_lost_utts": sum(r["chinese_lost"] for r in scored),
            "raw_simplified_utts": sum(r["raw_simplified"] for r in ok),
            "uppercase_latin_utts": sum(r["uppercase_latin"] for r in ok),
            "punctuated_utts": sum(r["punctuated"] for r in ok),
            "latency_ms_median": round(statistics.median(latencies)) if latencies else None,
            "latency_ms_p90": round(percentile(latencies, 0.9)) if latencies else None,
            "rtf_median": round(statistics.median(rtf), 4) if rtf else None,
            "latency_fit_ms": {"intercept": round(slope.intercept), "per_audio_second": round(slope.slope)} if slope else None,
            "peak_footprint_mb_max": round(max(r["peak_footprint"] or 0 for r in ok) / 2**20) if ok else None,
            "max_rss_mb_max": round(max(r["max_rss"] or 0 for r in ok) / 2**20) if ok else None,
        }
        if corpus.startswith("tw-tts"):
            entry["english_retention_case_exact"] = round(sum(r.get("kept_lat_case", 0) for r in scored) / ref_lat, 4)
        summary.append(entry)

    # Paired bootstrap against the current onboarding choice (SenseVoice, Auto):
    # same utterances resampled for both systems; negative = fewer errors.
    paired = []
    index = {(r["model"], r["language"], r["id"]): r for r in rows}
    def score_of(r):
        return r if r["status"] == "passed" else {**r, "err": r["ref_tokens"], "kept_lat": 0}
    for (model, language, corpus), group in sorted(groups.items()):
        if (model, language) == ("sherpa:senseVoice", "auto"):
            continue
        pairs = [(score_of(index[("sherpa:senseVoice", "auto", r["id"])]), score_of(r)) for r in group]
        rng = random.Random(74)
        def delta(sample, key, ref_key):
            ref = sum(a[ref_key] for a, _ in sample)
            return (sum(b[key] for _, b in sample) - sum(a[key] for a, _ in sample)) / ref if ref else 0
        mer, keep = [], []
        for _ in range(2000):
            sample = [pairs[rng.randrange(len(pairs))] for _ in pairs]
            mer.append(delta(sample, "err", "ref_tokens"))
            keep.append(delta(sample, "kept_lat", "ref_lat"))
        paired.append({"model": model, "language": language, "corpus": corpus,
                       "mer_delta": round(delta(pairs, "err", "ref_tokens"), 4),
                       "mer_delta_ci95": [round(percentile(mer, 0.025), 4), round(percentile(mer, 0.975), 4)],
                       "retention_delta": round(delta(pairs, "kept_lat", "ref_lat"), 4),
                       "retention_delta_ci95": [round(percentile(keep, 0.025), 4), round(percentile(keep, 0.975), 4)]})

    by_voice = []
    voices = collections.defaultdict(list)
    for row in rows:
        if row["corpus"] == "tw-tts":
            voices[(row["model"], row["language"], items[row["id"]]["voice"])].append(row)
    for (model, language, voice), group in sorted(voices.items()):
        scored = [r if r["status"] == "passed" else {**r, "err": r["ref_tokens"], "kept_lat": 0} for r in group]
        by_voice.append({"model": model, "language": language, "voice": voice, "utterances": len(group),
                         "mer": round(sum(r["err"] for r in scored) / sum(r["ref_tokens"] for r in scored), 4),
                         "english_retention": round(sum(r["kept_lat"] for r in scored) / sum(r["ref_lat"] for r in scored), 4)})

    load = {}
    for model in sorted({l["model"] for l in loads}):
        cold = {l["rep"]: l["asrMs"] for l in loads if l["model"] == model and not l["prepare"] and l["status"] == "passed"}
        prep = {l["rep"]: l["asrMs"] for l in loads if l["model"] == model and l["prepare"] and l["status"] == "passed"}
        diffs = [cold[k] - prep[k] for k in cold if k in prep]
        walls = [l["wall_s"] for l in loads if l["model"] == model and l["prepare"]]
        load[model] = {"load_ms_median": round(statistics.median(diffs)) if diffs else None, "load_ms_samples": diffs,
                       "process_wall_s_median": round(statistics.median(walls), 2) if walls else None}

    results = HERE / "results"
    results.mkdir(exist_ok=True)
    (results / "summary.json").write_text(json.dumps({"summary": summary, "paired_vs_sensevoice_auto": paired, "tw_tts_by_voice": by_voice, "load": load}, ensure_ascii=False, indent=1) + "\n")
    with open(results / "summary.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(summary[0].keys()) + ["english_retention_case_exact"], extrasaction="ignore")
        writer.writeheader()
        for entry in summary:
            writer.writerow({**entry, "mer_ci95": "%.4f-%.4f" % tuple(entry["mer_ci95"]),
                             "latency_fit_ms": json.dumps(entry["latency_fit_ms"])})
    with open(results / "utterances.csv", "w", newline="") as f:
        fields = ["id", "corpus", "model", "language", "status", "duration", "asrMs", "ref_tokens", "err", "ref_han",
                  "err_han", "ref_lat", "err_lat", "kept_lat", "english_dropped", "chinese_lost", "raw_simplified", "final"]
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for row in sorted(rows, key=lambda r: (r["corpus"], r["id"], r["model"], r["language"])):
            writer.writerow({**row, "final": row["final"][:300]})
    for entry in summary:
        print(f"{entry['corpus']:7} {entry['model']:18} {entry['language']:4} MER {entry['mer']:.3f} "
              f"CER {entry['cer_han']:.3f} WER {entry['wer_latin']:.3f} keep {entry['english_retention']:.3f} "
              f"drop {entry['english_dropped_utts']} lost {entry['chinese_lost_utts']} fail {entry['failures']} "
              f"p50 {entry['latency_ms_median']}ms rtf {entry['rtf_median']} mem {entry['peak_footprint_mb_max']}MB")
    print(json.dumps(load, indent=1))


if __name__ == "__main__":
    main()
